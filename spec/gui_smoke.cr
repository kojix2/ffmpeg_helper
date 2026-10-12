# Run manually with a display: make smoke
require "file/tempfile"
require "../src/app"

class FFmpegGUI::Timeline
  getter frame_drawn = false

  def observe_draws
    @handler.draw do |_, params|
      draw(params)
      @frame_drawn = true if @frame
    end
  end

  def choose_crop_for_smoke
    x, y, width, height = picture_rect(640.0, 300.0).not_nil!
    begin_crop(x + width * 0.1, y + height * 0.2, 640.0, 300.0)
    drag_crop_to(x + width * 0.6, y + height * 0.8, 640.0, 300.0)
  end
end

class FFmpegGUI::App
  def install_smoke_checks
    @timeline.observe_draws
    phase = 0
    started = Time.instant
    UIng.timer(100) do
      if started.elapsed > 15.seconds
        raise "GUI smoke test timed out: phase=#{phase}, probe=#{@probe.try(&.done)}, probe_log=#{@probe.try(&.log)}, preview=#{@preview.message}, pixels=#{!@preview.pixels.nil?}, drawn=#{@timeline.frame_drawn}, job=#{@job.try(&.done)}, status=#{@status.text}"
      end
      case phase
      when 0
        if !@probe && @preview.pixels && @timeline.frame_drawn
          raise "preview tab must be initially visible" unless @tabs.selected == 0
          expected_title = {"en" => "Open File", "ja" => "ファイルを開く", "zh" => "打开文件", "es" => "Abrir"}[I18n.locale]
          raise "toolbar was not localized" unless @open_item.text == expected_title
          raise "About button was not localized" unless @about_item.text == I18n.t!("ui.about")
          raise "About text is missing versions" unless [FFmpegGUI::VERSION, Crystal::VERSION, UIng::VERSION, UIng.libui_version].all? { |version| about_text.includes?(version) }
          width, height = @window.content_size
          raise "window exceeded its compact size: #{width}x#{height}" if width > 920 || height > 620
          raise "ffprobe did not supply duration" unless @duration
          raise "sidebar must remain visible" unless @sidebar.visible?
          @timeline.begin_drag(24.0, 1000.0)
          @timeline.drag_to(262.0, 1000.0)
          raise "in handle did not update settings" unless (FFmpegGUI::Settings.seconds(settings.start).not_nil! - @duration.not_nil! * 0.25).abs < 0.002
          @timeline.begin_drag(976.0, 1000.0)
          @timeline.drag_to(738.0, 1000.0)
          raise "out handle did not update settings" unless (FFmpegGUI::Settings.seconds(settings.finish).not_nil! - @duration.not_nil! * 0.75).abs < 0.002
          command = settings.command
          @timeline.begin_drag(500.0, 1000.0)
          raise "scrubbing must not change trim" unless settings.command == command
          @timeline.seek(0.75)
          @timeline.trim_at_cursor(false)
          raise "mark in failed" unless FFmpegGUI::Settings.seconds(settings.start) == 0.75
          raise "source dimensions missing" unless @timeline.video_size == {160, 120}
          @timeline.choose_crop_for_smoke
          raise "crop coordinates are wrong" unless @timeline.crop == FFmpegGUI::Crop.new(16, 24, 80, 72)
          raise "crop not reflected in command" unless @command.text.to_s.includes?("crop=80:72:16:24:exact=1")
          raise "crop reset button was not enabled" unless @crop_reset.enabled?
          FFmpegGUI::PRESETS.each_index do |index|
            select_preset(index)
            @preset_buttons.each_with_index do |control, i|
              marker = i == index ? "●" : "◯"
              raise "button selection out of sync" unless control.text.to_s.starts_with?("#{marker}  ")
            end
            raise "stale command preview" unless @command.text == settings.command
            raise "crop applied to stream copy" if index == 5 && @command.text.to_s.includes?("crop=")
          end
          @mute.checked = true
          select_preset(2)
          raise "extracted audio controls must stay enabled" unless @bitrate.enabled? && @sample_rate.enabled? && @channels.enabled?
          @mute.checked = false
          select_preset(0)
          raise "crop lost after switching formats" unless @command.text.to_s.includes?("crop=80:72:16:24:exact=1")
          @timeline.reset_crop
          raise "crop reset failed" if @timeline.crop || @command.text.to_s.includes?("crop=") || @crop_reset.enabled?
          @sample_rate.selected = 1
          @channels.selected = 2
          refresh
          raise "audio settings not reflected in command" unless @command.text.to_s.includes?("-ar 48000") && @command.text.to_s.includes?("-ac 1")
          @sample_rate.selected = 0
          @channels.selected = 0
          @start.text = "0.25"
          @finish.text = "1.25"
          refresh
          run_conversion
          raise "conversion did not start" unless @job
          raise "conversion must show the run log" unless @tabs.selected == 3
          phase = 1
        end
      when 1
        unless @job
          raise "conversion did not finish successfully: #{@status.text}" unless @progress.value == 100
          raise "missing output" unless File.size(@output.text.to_s) > 0
          # Exercise closing while the child is still running, including wait,
          # cancellation, toolbar/image disposal, and window destruction.
          @job = FFmpegGUI::Job.new("ffmpeg", ["-nostdin", "-re", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-f", "null", "-"])
          busy(true)
          raise "close must wait for active child" if request_close
          phase = 2
        end
      end
      @closed ? 0 : 1
    end
  end

  def verify_smoke
    raise "child still active after close" if @job || @probe || @preview.busy?
    raise "window not closed" unless @closed
    puts "GUI smoke passed: preview, crop, scrub, trim handles, mark in, fixed sidebar, conversion, cancellation, close"
  end
end

File.tempfile("uing-gui-smoke", ".mkv") do |source|
  output = File.join(File.dirname(source.path), "#{File.basename(source.path, ".mkv")}_converted.mp4")
  begin
    status = Process.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=12", "-t", "2", "-c:v", "libx264", source.path])
    raise "fixture generation failed" unless status.success?
    UIng.init do
      UIng.on_error do |ex, context|
        STDERR.puts "#{context}: #{ex.message}"
        exit 1
      end
      app = FFmpegGUI::App.new
      app.install_smoke_checks
      app.run(source.path)
      app.verify_smoke
    end
  ensure
    File.delete(output) if File.exists?(output)
  end
end
