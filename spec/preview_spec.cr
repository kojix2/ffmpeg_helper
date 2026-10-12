require "spec"
require "file/tempfile"
require "../src/preview"

private def await_preview(preview : FFmpegGUI::Preview, seconds : Float64)
  started = Time.instant
  loop do
    preview.tick
    break if preview.pixels && preview.time == seconds && !preview.busy?
    raise "preview timed out: #{preview.message}" if started.elapsed > 10.seconds
    sleep 10.milliseconds
  end
end

if ENV["FFMPEG_INTEGRATION"]? == "1"
  describe FFmpegGUI::Preview do
    it "decodes real frames and discards obsolete requests after a source reset" do
      File.tempfile("uing-preview", ".mkv") do |source|
        status = Process.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-t", "2", "-c:v", "libx264", source.path])
        status.success?.should be_true
        preview = FFmpegGUI::Preview.new
        begin
          preview.request(source.path, 0.0)
          await_preview(preview, 0.0)
          first = preview.pixels.not_nil!.dup
          first.size.should eq(FFmpegGUI::Preview::WIDTH * FFmpegGUI::Preview::HEIGHT * 4)
          preview.request(source.path, 1.0)
          await_preview(preview, 1.0)
          preview.pixels.should_not eq(first)

          preview.request(source.path, 0.25)
          sleep 200.milliseconds
          preview.tick
          preview.busy?.should be_true
          preview.clear
          preview.pixels.should be_nil
          preview.request(source.path, 0.5)
          preview.request(source.path, 1.25)
          await_preview(preview, 1.25)
          preview.time.should eq(1.25)
        ensure
          preview.cancel
          until !preview.busy?
            preview.tick
            sleep 10.milliseconds
          end
        end
      end
    end

    it "handles an undecodable input without publishing a partial image" do
      File.tempfile("uing-not-media", ".mp4") do |source|
        job = FFmpegGUI::Job.new("ffmpeg", FFmpegGUI::Preview.args(source.path, 0.0), frame_bytes: 480 * 270 * 4)
        started = Time.instant
        until job.done
          job.tick
          raise "decode did not exit" if started.elapsed > 10.seconds
          sleep 10.milliseconds
        end
        job.success.should be_false
        job.pixels.should be_nil
      end
    end
  end
end
