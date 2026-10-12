require "spec"
require "file/tempfile"
require "../src/command"
require "../src/job"

# Explicit opt-in: these tests invoke the installed ffmpeg / ffprobe binaries.
private def wait_for(job : FFmpegGUI::Job)
  deadline = Time.instant + 20.seconds
  until job.done
    job.tick
    if Time.instant > deadline
      job.cancel
      raise "ffmpeg test timed out"
    end
    sleep 10.milliseconds
  end
end

if ENV["FFMPEG_INTEGRATION"]? == "1"
  describe "FFmpeg integration" do
    it "encodes all eight presets with real media and reports progress" do
      File.tempfile("uing ffmpeg 日本語 '", ".mkv") do |source|
        status = Process.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "2", "-c:v", "libx264", "-c:a", "aac", source.path])
        status.success?.should be_true
        FFmpegGUI::PRESETS.each_with_index do |preset, index|
          File.tempfile("uing output '", ".#{preset.extension}") do |output|
            settings = FFmpegGUI::Settings.new
            settings.input = source.path
            settings.output = output.path
            settings.preset = index
            settings.overwrite = true
            settings.start = "0.25"
            settings.finish = "1.25"
            settings.width = 128
            settings.validate!(2.0)
            job = FFmpegGUI::Job.new("ffmpeg", settings.args, progress: true)
            wait_for(job)
            job.success.should be_true, "#{preset.title}: #{job.log}"
            job.seconds.should be > 0
            File.size(output.path).should be > 0
            probe = FFmpegGUI::Job.new("ffprobe", ["-v", "error", "-show_format", "-show_streams", "-of", "json", output.path])
            wait_for(probe)
            probe.success.should be_true
            info = FFmpegGUI::MediaInfo.parse(probe.output)
            info.duration.not_nil!.should be > 0
          end
        end
      end
    end

    it "captures stderr and handles nonzero exit" do
      job = FFmpegGUI::Job.new("ffmpeg", ["-definitely-not-a-real-option"])
      wait_for(job)
      job.success.should be_false
      job.log.should_not be_empty
    end

    it "encodes the selected source rectangle at the expected dimensions" do
      File.tempfile("uing-crop-source", ".mkv") do |source|
        status = Process.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-t", "1", "-c:v", "libx264", source.path])
        status.success?.should be_true
        [0, 4].each do |preset|
          File.tempfile("uing-crop-output", ".#{FFmpegGUI::PRESETS[preset].extension}") do |output|
            settings = FFmpegGUI::Settings.new
            settings.input = source.path
            settings.output = output.path
            settings.preset = preset
            settings.crop = FFmpegGUI::Crop.new(16, 18, 80, 54)
            settings.overwrite = true
            settings.validate!
            job = FFmpegGUI::Job.new("ffmpeg", settings.args, progress: true)
            wait_for(job)
            job.success.should be_true, job.log
            probe = FFmpegGUI::Job.new("ffprobe", ["-v", "error", "-show_streams", "-of", "json", output.path])
            wait_for(probe)
            probe.success.should be_true
            FFmpegGUI::MediaInfo.parse(probe.output).video_size.should eq({80, 54})
          end
        end
      end
    end

    it "cancels an active process and waits for its exit" do
      job = FFmpegGUI::Job.new("ffmpeg", ["-nostdin", "-re", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-progress", "pipe:1", "-f", "null", "-"], progress: true)
      sleep 150.milliseconds
      job.cancel
      wait_for(job)
      job.cancelled.should be_true
      job.success.should be_false
      job.done.should be_true
    end
  end
end
