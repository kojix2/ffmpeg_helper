require "uing"
require "./command"
require "./job"
require "./preview"
require "./timeline"

module FFmpegGUI
  class App
    WIDTHS       = [0, 1920, 1280, 854, 640, 480]
    RATES        = [0, 60, 30, 24, 15, 12, 10]
    SPEEDS       = ["ultrafast", "fast", "medium", "slow"]
    BITRATES     = [96, 128, 192, 256, 320]
    SAMPLE_RATES = [0, 48000, 44100, 22050]
    CHANNELS     = [0, 2, 1]

    @window : UIng::Window
    @toolbar : UIng::Toolbar
    @open_item : UIng::ToolbarItem
    @run_item : UIng::ToolbarItem
    @stop_item : UIng::ToolbarItem
    @about_item : UIng::ToolbarItem
    @timeline : Timeline
    @input : UIng::Entry
    @output : UIng::Entry
    @start : UIng::Entry
    @finish : UIng::Entry
    @quality : UIng::Slider
    @quality_label : UIng::Label
    @speed : UIng::Combobox
    @width : UIng::Combobox
    @fps : UIng::Combobox
    @bitrate : UIng::Combobox
    @sample_rate : UIng::Combobox
    @channels : UIng::Combobox
    @mute : UIng::Checkbox
    @overwrite : UIng::Checkbox
    @metadata : UIng::Checkbox
    @command : UIng::MultilineEntry
    @log : UIng::MultilineEntry
    @status : UIng::Label
    @info : UIng::Label
    @preset_label : UIng::Label
    @progress : UIng::ProgressBar
    @tabs : UIng::Tab
    @sidebar : UIng::Box
    @settings_box : UIng::Box
    @files : UIng::Group
    @preset_buttons = [] of UIng::Button
    @icons = [] of UIng::Image
    @preset = 0
    @duration : Float64?
    @job : Job?
    @probe : Job?
    @probe_path = ""
    @probe_started = Time.instant
    @run_duration : Float64?
    @closing = false
    @closed = false
    @updating = false
    @last_log = ""
    @suggested_output = ""
    @preview = Preview.new
    @preview_revision = -1
    @has_video = false
    @preview_controls : UIng::Box
    @crop_reset : UIng::Button

    def initialize
      @window = UIng::Window.new("FFmpeg Helper", 920, 620, margined: true)
      @toolbar = UIng::Toolbar.new
      @toolbar.display_mode = UIng::Toolbar::DisplayMode::IconAndTextHorizontal
      @open_item = @toolbar.append_button(I18n.t!("ui.open"), icon(:open))
      @toolbar.append_separator
      @run_item = @toolbar.append_button(I18n.t!("ui.start"), icon(:play))
      @stop_item = @toolbar.append_button(I18n.t!("ui.stop"), icon(:stop))
      @toolbar.append_separator
      command_item = @toolbar.append_button(I18n.t!("ui.show_command"), icon(:command))
      @toolbar.append_separator
      @about_item = @toolbar.append_button(I18n.t!("ui.about"), icon(:info))
      @window.toolbar = @toolbar
      @window.set_content_size(920, 620)
      @stop_item.disable
      @open_item.tooltip = I18n.t!("ui.open_tooltip")
      @run_item.tooltip = I18n.t!("ui.start_tooltip")
      @stop_item.tooltip = I18n.t!("ui.stop_tooltip")
      command_item.tooltip = I18n.t!("ui.command_tooltip")
      @about_item.tooltip = I18n.t!("ui.about_tooltip")

      @input = UIng::Entry.new
      @output = UIng::Entry.new
      @start = UIng::Entry.new
      @finish = UIng::Entry.new
      @quality = UIng::Slider.new(0, 51)
      @quality.value = 23
      @quality_label = UIng::Label.new("CRF 23")
      @speed = combo([I18n.t!("ui.speed_ultrafast"), I18n.t!("ui.speed_fast"), I18n.t!("ui.speed_medium"), I18n.t!("ui.speed_slow")], 2)
      @width = combo([I18n.t!("ui.original_size"), "1920 px", "1280 px", "854 px", "640 px", "480 px"])
      @fps = combo([I18n.t!("ui.original_fps"), "60", "30", "24", "15", "12", "10"])
      @bitrate = combo(["96 kbps", "128 kbps", "192 kbps", "256 kbps", "320 kbps"], 2)
      @sample_rate = combo([I18n.t!("ui.original_sample_rate"), "48 kHz", "44.1 kHz", "22.05 kHz"])
      @channels = combo([I18n.t!("ui.original_channels"), I18n.t!("ui.stereo"), I18n.t!("ui.mono")])
      @mute = UIng::Checkbox.new(I18n.t!("ui.mute"))
      @overwrite = UIng::Checkbox.new(I18n.t!("ui.overwrite"))
      @metadata = UIng::Checkbox.new(I18n.t!("ui.strip_metadata"))
      @command = UIng::MultilineEntry.new(wrapping: false, read_only: true)
      @log = UIng::MultilineEntry.new(wrapping: false, read_only: true)
      @status = UIng::Label.new(I18n.t!("ui.ready_open"))
      @info = UIng::Label.new(I18n.t!("ui.media_placeholder"))
      @preset_label = UIng::Label.new("")
      @progress = UIng::ProgressBar.new
      @tabs = UIng::Tab.new
      @sidebar = UIng::Box.new(:vertical, padded: true)
      @settings_box = UIng::Box.new(:vertical, padded: true)
      @files = UIng::Group.new(I18n.t!("ui.files"), margined: true)
      @preview_controls = UIng::Box.new(:horizontal, padded: true)
      @timeline = Timeline.new(->(seconds : Float64) { request_preview(seconds) }) do |seconds, finish|
        @updating = true
        if finish
          @finish.text = seconds.round(3).to_s
        else
          @start.text = seconds.round(3).to_s
        end
        @updating = false
        refresh
      end
      @crop_reset = button(I18n.t!("ui.reset_crop")) { @timeline.reset_crop }
      @crop_reset.disable

      build_layout
      @timeline.on_crop do
        @crop_reset.enable if @timeline.crop
        @crop_reset.disable unless @timeline.crop
        refresh
      end
      @open_item.on_clicked { choose_input }
      @run_item.on_clicked { run_conversion }
      @stop_item.on_clicked { stop }
      command_item.on_clicked { @tabs.selected = 2 }
      @about_item.on_clicked { @window.msg_box(I18n.t!("ui.about"), about_text) }
      @input.on_changed do
        reset_preview
        @info.text = I18n.t!("ui.input_hint")
        suggest_output
        refresh
      end
      [@output, @start, @finish].each { |entry| entry.on_changed { refresh } }
      [@speed, @width, @fps, @bitrate, @sample_rate, @channels].each { |control| control.on_selected { refresh } }
      @mute.on_toggled { update_audio_controls; refresh }
      [@overwrite, @metadata].each { |control| control.on_toggled { refresh } }
      @quality.on_changed { refresh }
      @window.on_closing { request_close }
      UIng.on_should_quit do
        if request_close
          @window.destroy
          true
        else
          false
        end
      end
      select_preset(0)
    end

    def run(path : String? = nil)
      load_input(path) if path
      @window.show
      UIng.timer(100) do
        tick unless @closed
        # Process.wait is notified through Crystal's event loop. Let it run
        # briefly while libui-ng owns the GUI loop.
        Fiber.yield
        @closed ? 0 : 1
      end
      UIng.main
    ensure
      @timeline.free
    end

    private def combo(values, selected = 0)
      box = UIng::Combobox.new(values)
      box.selected = selected
      box
    end

    private def button(text, &block : -> Nil)
      control = UIng::Button.new(text)
      control.on_clicked { block.call }
      control
    end

    private def preset_button_title(preset : Preset) : String
      return preset.title if preset.key.in?("mp4", "hevc")
      preset.extension == "webm" ? "WebM" : preset.extension.upcase
    end

    # Small code-drawn RGBA icons; no image assets or extra dependencies.
    private def icon(kind : Symbol) : UIng::Image
      pixels = Bytes.new(24 * 24 * 4, 0)
      if kind == :info
        draw_info_icon(pixels)
      else
        24.times do |y|
          24.times do |x|
            inside = case kind
                     when :play then x >= 6 && x <= 18 && (y - 12).abs <= (18 - x) * 0.7
                     when :stop then x.in?(6..17) && y.in?(6..17)
                     when :open then (x.in?(3..20) && y.in?(8..19)) || (x.in?(3..10) && y.in?(5..8))
                     else            (x.in?(4..8) || x.in?(15..19)) && ((y - 12).abs - (x < 12 ? 8 - x : x - 15)).abs < 2
                     end
            next unless inside
            offset = (y * 24 + x) * 4
            pixels[offset] = kind == :stop ? 216_u8 : 36_u8
            pixels[offset + 1] = kind == :stop ? 80_u8 : 143_u8
            pixels[offset + 2] = kind == :stop ? 80_u8 : 126_u8
            pixels[offset + 3] = 255_u8
          end
        end
      end
      image = UIng::Image.new(24, 24)
      image.append(pixels, 24, 24, 24 * 4)
      @icons << image
      image
    end

    private def draw_info_icon(pixels : Bytes)
      # Four samples per axis keep the circle and the white letter smooth at 24 px.
      24.times do |y|
        24.times do |x|
          circle_samples = 0
          letter_samples = 0
          4.times do |sample_y|
            4.times do |sample_x|
              px = x + (sample_x + 0.5) / 4
              py = y + (sample_y + 0.5) / 4
              circle_x = px - 12
              circle_y = py - 12
              next if circle_x * circle_x + circle_y * circle_y > 8.25 * 8.25
              circle_samples += 1
              dot_x = px - 12
              dot_y = py - 8.4
              dot = dot_x * dot_x + dot_y * dot_y <= 1.2 * 1.2
              stem = px >= 11.1 && px <= 12.9 && py >= 10.8 && py <= 16.8
              letter_samples += 1 if dot || stem
            end
          end
          next if circle_samples == 0
          offset = (y * 24 + x) * 4
          blue_samples = circle_samples - letter_samples
          pixels[offset] = ((37 * blue_samples + 255 * letter_samples) / 16).round.to_u8
          pixels[offset + 1] = ((99 * blue_samples + 255 * letter_samples) / 16).round.to_u8
          pixels[offset + 2] = ((235 * blue_samples + 255 * letter_samples) / 16).round.to_u8
          pixels[offset + 3] = (255 * circle_samples / 16).round.to_u8
        end
      end
    end

    private def build_layout
      root = UIng::Box.new(:vertical, padded: true)
      body = UIng::Box.new(:horizontal, padded: true)
      @sidebar.append(UIng::Label.new(I18n.t!("ui.format")))
      @sidebar.append(UIng::Separator.new(:horizontal))
      PRESETS.each_with_index do |preset, index|
        control = button(preset_button_title(preset)) { select_preset(index) }
        @preset_buttons << control
        @sidebar.append(control)
      end
      @sidebar.append(UIng::Label.new(""), true)
      body.append(@sidebar)
      body.append(UIng::Separator.new(:vertical))

      main = UIng::Box.new(:vertical, padded: true)
      file_form = UIng::Form.new(padded: true)
      input_row = UIng::Box.new(:horizontal, padded: true)
      input_row.append(@input, true)
      input_row.append(button(I18n.t!("ui.browse_input")) { choose_input })
      input_row.append(button(I18n.t!("ui.probe")) { probe_input })
      output_row = UIng::Box.new(:horizontal, padded: true)
      output_row.append(@output, true)
      output_row.append(button(I18n.t!("ui.browse_output")) { choose_output })
      file_form.append(I18n.t!("ui.input"), input_row)
      file_form.append(I18n.t!("ui.output"), output_row)
      @files.child = file_form
      main.append(@files)
      preview_page = UIng::Box.new(:vertical, padded: true)
      preview_page.append(@timeline.area, true)
      @preview_controls.append(button(I18n.t!("ui.mark_in")) { @timeline.trim_at_cursor(false) })
      @preview_controls.append(button(I18n.t!("ui.mark_out")) { @timeline.trim_at_cursor(true) })
      @preview_controls.append(button(I18n.t!("ui.reset_trim")) do
        @start.text = ""
        @finish.text = ""
        refresh
      end)
      @preview_controls.append(@crop_reset)
      preview_page.append(@preview_controls)
      @tabs.append(I18n.t!("ui.tab_preview"), preview_page, margined: true)
      build_settings
      @tabs.append(I18n.t!("ui.tab_settings"), @settings_box, margined: true)
      command_box = UIng::Box.new(:vertical, padded: true)
      command_box.append(UIng::Label.new(I18n.t!("ui.command_help")))
      command_box.append(@command, true)
      command_box.append(button(I18n.t!("ui.save_command")) { save_command })
      @tabs.append(I18n.t!("ui.tab_command"), command_box, margined: true)
      log_box = UIng::Box.new(:vertical, padded: true)
      log_box.append(UIng::Label.new(I18n.t!("ui.log_help")))
      log_box.append(@log, true)
      @tabs.append(I18n.t!("ui.tab_log"), log_box, margined: true)
      media_box = UIng::Box.new(:vertical, padded: true)
      media_box.append(@info)
      media_box.append(UIng::Label.new(I18n.t!("ui.media_help")))
      @tabs.append(I18n.t!("ui.tab_media"), media_box, margined: true)
      main.append(@tabs, true)
      body.append(main, true)
      root.append(body, true)
      root.append(UIng::Separator.new(:horizontal))
      root.append(@progress)
      root.append(@status)
      @window.child = root
    end

    private def build_settings
      @settings_box.append(@preset_label)
      columns = UIng::Box.new(:horizontal, padded: true)
      video = UIng::Form.new(padded: true)
      quality = UIng::Box.new(:horizontal, padded: true)
      quality.append(@quality, true)
      quality.append(@quality_label)
      video.append(I18n.t!("ui.quality"), quality)
      video.append(I18n.t!("ui.encode_speed"), @speed)
      video.append(I18n.t!("ui.width"), @width)
      video.append(I18n.t!("ui.fps"), @fps)
      audio = UIng::Form.new(padded: true)
      audio.append(I18n.t!("ui.audio_bitrate"), @bitrate)
      audio.append(I18n.t!("ui.sample_rate"), @sample_rate)
      audio.append(I18n.t!("ui.channels"), @channels)
      audio.append(I18n.t!("ui.audio"), @mute)
      audio.append(I18n.t!("ui.trim_start"), @start)
      audio.append(I18n.t!("ui.trim_end"), @finish)
      columns.append(video, true)
      columns.append(audio, true)
      @settings_box.append(columns)
      @settings_box.append(UIng::Separator.new(:horizontal))
      options = UIng::Box.new(:horizontal, padded: true)
      options.append(@metadata)
      options.append(@overwrite)
      @settings_box.append(options)
    end

    private def settings : Settings
      Settings.new.tap do |s|
        s.input = @input.text.to_s
        s.output = @output.text.to_s
        s.preset = @preset
        s.crf = @quality.value
        s.speed = SPEEDS[@speed.selected || 2]
        s.width = WIDTHS[@width.selected || 0]
        s.fps = RATES[@fps.selected || 0]
        s.audio_bitrate = BITRATES[@bitrate.selected || 2]
        s.audio_sample_rate = SAMPLE_RATES[@sample_rate.selected || 0]
        s.audio_channels = CHANNELS[@channels.selected || 0]
        s.mute = @mute.checked?
        s.start = @start.text.to_s
        s.finish = @finish.text.to_s
        s.overwrite = @overwrite.checked?
        s.strip_metadata = @metadata.checked?
        s.crop = @timeline.crop if @preset.in?(0, 1, 4, 6)
      end
    end

    private def refresh
      return if @updating
      s = settings
      @quality_label.text = "CRF #{s.crf}"
      replace_read_only_text(@command, s.command)
      @timeline.duration = @duration || 0.0
      @timeline.from = Settings.seconds(s.start) || 0.0
      @timeline.ending = Settings.seconds(s.finish) || @duration || 0.0
      name = File.basename(s.input)
      @timeline.title = s.input.empty? ? I18n.t!("ui.choose_source") : (name.size > 48 ? name[0, 45] + "…" : name)
      @timeline.subtitle = "#{PRESETS[@preset].title}    /    #{@duration ? Timeline.time(@duration.not_nil!) : I18n.t!("ui.duration_unknown")}"
      @timeline.area.queue_redraw_all
    rescue ex : ArgumentError
      replace_read_only_text(@command, ex.message.to_s)
      @status.text = ex.message.to_s
    end

    private def select_preset(index)
      if index == 4 && @preset != 4
        @width.selected = 5
        @fps.selected = 5
      end
      @preset = index
      @preset_buttons.each_with_index do |control, i|
        control.text = "#{i == index ? "●" : "◯"}  #{preset_button_title(PRESETS[i])}"
      end
      @preset_label.text = "#{PRESETS[index].title} — #{PRESETS[index].detail}"
      set_enabled(@quality, index.in?(0, 1, 6))
      set_enabled(@speed, index.in?(0, 6))
      set_enabled(@width, index.in?(0, 1, 4, 6))
      set_enabled(@fps, index.in?(0, 1, 4, 6))
      set_enabled(@mute, index.in?(0, 1, 5, 6))
      @timeline.crop_editable = index.in?(0, 1, 4, 6)
      update_audio_controls
      # Keep the chosen directory and filename stem when switching formats.
      current = @output.text.to_s
      unless current.empty?
        ext = File.extname(current)
        stem = ext.empty? ? current : current[0, current.size - ext.size]
        @output.text = "#{stem}.#{PRESETS[index].extension}"
        @suggested_output = @output.text.to_s if current == @suggested_output
      end
      suggest_output
      refresh
    end

    private def update_audio_controls
      audio = @preset.in?(2, 3, 7) || (@preset.in?(0, 1, 6) && !@mute.checked?)
      set_enabled(@bitrate, audio && @preset.in?(0, 1, 2, 6))
      set_enabled(@sample_rate, audio)
      set_enabled(@channels, audio)
    end

    private def about_text : String
      I18n.t!("ui.about_details", app_version: VERSION, crystal_version: Crystal::VERSION,
        uing_version: UIng::VERSION, libui_version: UIng.libui_version)
    end

    private def set_enabled(control, enabled)
      enabled ? control.enable : control.disable
    end

    private def replace_read_only_text(control : UIng::MultilineEntry, text : String) : Nil
      control.read_only = false
      control.text = text
    ensure
      control.read_only = true
    end

    private def choose_input
      if path = @window.open_file
        load_input(path)
      end
    end

    private def load_input(path)
      @input.text = path
      reset_preview
      @start.text = ""
      @finish.text = ""
      @timeline.progress = 0.0
      suggest_output
      refresh
      probe_input
    end

    private def reset_preview
      @duration = nil
      @has_video = false
      @preview.clear
      @timeline.reset
      @crop_reset.disable
    end

    private def request_preview(seconds : Float64) : Nil
      return if @closing || @job || @probe || !@has_video
      path = @input.text.to_s
      return unless File.file?(path)
      # Seeking exactly to EOF can return no frame.
      time = @duration ? seconds.clamp(0.0, Math.max(0.0, @duration.not_nil! - 0.1)) : seconds
      @preview.request(path, time)
    end

    private def suggest_output
      input = @input.text.to_s
      return if input.empty?
      current = @output.text.to_s
      if current.empty? || current == @suggested_output
        @suggested_output = File.join(File.dirname(input), "#{File.basename(input, File.extname(input))}_converted.#{PRESETS[@preset].extension}")
        @output.text = @suggested_output
      end
    end

    private def choose_output
      if path = @window.save_file
        path += ".#{PRESETS[@preset].extension}" if File.extname(path).empty?
        @output.text = path
        refresh
      end
    end

    private def probe_input
      return if @probe
      path = @input.text.to_s
      unless File.file?(path)
        @window.msg_box_error(I18n.t!("ui.input_file"), I18n.t!("ui.input_missing"))
        return
      end
      @probe_path = path
      @probe_started = Time.instant
      @probe = Job.new("ffprobe", ["-v", "error", "-show_format", "-show_streams", "-of", "json", File.expand_path(path)])
      @status.text = I18n.t!("ui.probing")
      busy(true)
    rescue ex
      @info.text = I18n.t!("ui.probe_launch_error", error: ex.message.to_s)
      @status.text = I18n.t!("ui.probe_missing")
    end

    private def run_conversion
      return if @job || @probe
      s = settings
      s.validate!(@duration)
      @run_duration = s.duration(@duration)
      @job = Job.new("ffmpeg", s.args, progress: true)
      @preview.cancel
      @timeline.progress = 0.0
      @progress.value = @run_duration ? 0 : -1
      @last_log = ""
      replace_read_only_text(@log, "")
      @status.text = I18n.t!("ui.converting")
      @tabs.selected = 3
      busy(true)
    rescue ex
      @window.msg_box_error(I18n.t!("ui.start_error"), "#{ex.message}\n\n#{I18n.t!("ui.ffmpeg_path_hint")}")
    end

    private def busy(value)
      [@files, @settings_box, @sidebar, @preview_controls].each { |control| set_enabled(control, !value) }
      set_enabled(@open_item, !value)
      set_enabled(@run_item, !value)
      set_enabled(@stop_item, value)
      @timeline.editable = !value
      @timeline.running = !@job.nil?
      select_preset(@preset) unless value
      request_preview(@timeline.cursor) unless value
    end

    private def stop
      @job.try &.cancel
      @probe.try &.cancel
      @stop_item.disable
      @status.text = I18n.t!("ui.stopping")
    end

    private def tick
      if probe = @probe
        probe.tick
        probe.cancel if Time.instant - @probe_started > 15.seconds
        if probe.done
          if probe.success
            begin
              media = MediaInfo.parse(probe.output)
              @duration = media.duration
              @has_video = media.video
              @timeline.video_size = media.video_size
              @preview.clear(I18n.t!("ui.audio_timeline")) unless media.video
              @info.text = I18n.t!("ui.media_details", path: @probe_path, duration: @duration ? Timeline.time(@duration.not_nil!) : I18n.t!("ui.unknown"), summary: media.summary)
              @status.text = I18n.t!("ui.ready_convert")
            rescue ex
              @info.text = I18n.t!("ui.media_parse_error", error: ex.message.to_s)
            end
          else
            @info.text = I18n.t!("ui.probe_error", log: probe.log[-2000..]? || probe.log)
            @status.text = I18n.t!("ui.probe_stopped")
          end
          @probe = nil
          busy(false)
        end
      end
      if job = @job
        job.tick
        if @last_log != job.log
          @last_log = job.log
          replace_read_only_text(@log, @last_log)
        end
        ratio = @run_duration.try { |duration| duration > 0 ? (job.seconds / duration).clamp(0.0, 0.99) : 0.0 }
        if ratio
          @timeline.progress = ratio
          @progress.value = (ratio * 100).to_i
        end
        state = I18n.t!(job.cancelled ? "ui.job_stopping" : "ui.job_converting")
        @status.text = if ratio
                         I18n.t!("ui.job_progress", state: state, progress: (ratio * 100).to_i, time: Timeline.time(job.seconds), speed: job.speed)
                       else
                         I18n.t!("ui.job_progress_unknown", state: state, time: Timeline.time(job.seconds), speed: job.speed)
                       end
        @timeline.area.queue_redraw_all
        if job.done
          @progress.value = job.success ? 100 : 0
          @timeline.progress = 1.0 if job.success
          @status.text = if job.success
                           I18n.t!("ui.complete", path: @output.text.to_s)
                         elsif job.cancelled
                           I18n.t!("ui.cancelled")
                         else
                           I18n.t!("ui.failed", code: job.exit_code.to_s)
                         end
          @job = nil
          busy(false)
        end
      end
      @preview.tick
      if @preview_revision != @preview.revision
        @preview_revision = @preview.revision
        pixels = @preview.pixels
        @timeline.frame = pixels ? {pixels, @preview.time} : nil
      end
      if @timeline.preview_message != @preview.message
        @timeline.preview_message = @preview.message
        @timeline.area.queue_redraw_all
      end
      if @closing && !@job && !@probe && !@preview.busy?
        cleanup
        @window.destroy
        UIng.quit
      end
    end

    private def save_command
      if path = @window.save_file
        if File.exists?(path)
          raise ArgumentError.new(I18n.t!("ui.save_new_file"))
        end
        File.write(path, settings.command + "\n")
        @status.text = I18n.t!("ui.command_saved", path: path)
      end
    rescue ex
      @window.msg_box_error(I18n.t!("ui.save_error"), ex.message.to_s)
    end

    private def request_close : Bool
      @preview.cancel
      if @job || @probe || @preview.busy?
        @closing = true
        stop
        false
      else
        cleanup
        UIng.quit
        true
      end
    end

    private def cleanup
      return if @closed
      @closed = true
      @window.toolbar = nil
      @toolbar.free
      @icons.each &.free
    end
  end
end
