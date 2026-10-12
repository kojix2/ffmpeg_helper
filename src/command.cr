require "json"
require "./localization"

module FFmpegGUI
  VERSION = {{ `shards version #{__DIR__}/..`.chomp.stringify }}

  record Preset, key : String, extension : String do
    def title : String
      I18n.t!("presets.#{key}.title")
    end

    def detail : String
      I18n.t!("presets.#{key}.detail")
    end
  end

  PRESETS = [
    Preset.new("mp4", "mp4"),
    Preset.new("webm", "webm"),
    Preset.new("mp3", "mp3"),
    Preset.new("wav", "wav"),
    Preset.new("gif", "gif"),
    Preset.new("mkv", "mkv"),
    Preset.new("hevc", "mp4"),
    Preset.new("flac", "flac"),
  ]

  record Crop, x : Int32, y : Int32, width : Int32, height : Int32 do
    def valid? : Bool
      x >= 0 && y >= 0 && width >= 2 && height >= 2
    end

    def filter : String
      "crop=#{width}:#{height}:#{x}:#{y}:exact=1"
    end
  end

  class Settings
    VALUELESS_OPTIONS = ["-hide_banner", "-nostdin", "-y", "-n", "-nostats", "-an", "-vn"]

    property input = ""
    property output = ""
    property preset = 0
    property crf = 23
    property speed = "medium"
    property width = 0
    property fps = 0
    property audio_bitrate = 192
    property audio_sample_rate = 0
    property audio_channels = 0
    property mute = false
    property start = ""
    property finish = ""
    property overwrite = false
    property strip_metadata = false
    property crop : Crop?

    def self.seconds(text : String) : Float64?
      return nil if text.strip.empty?
      parts = text.strip.split(':')
      raise ArgumentError.new(I18n.t!("settings.time_format")) unless 1 <= parts.size <= 3
      values = parts.map do |part|
        value = part.to_f64?
        raise ArgumentError.new(I18n.t!("settings.time_nonnegative")) unless value && value.finite? && value >= 0
        value
      end
      if values.size > 1 && values[1..].any? { |value| value >= 60 }
        raise ArgumentError.new(I18n.t!("settings.time_minute_second"))
      end
      values.reduce(0.0) { |total, value| total * 60 + value }
    end

    def duration(total : Float64?) : Float64?
      from = Settings.seconds(start) || 0.0
      ending = Settings.seconds(finish) || total
      ending.try { |value| value - from }
    end

    def validate!(total : Float64? = nil)
      raise ArgumentError.new(I18n.t!("settings.input_required")) unless File.file?(input)
      raise ArgumentError.new(I18n.t!("settings.output_required")) if output.empty?
      raise ArgumentError.new(I18n.t!("settings.output_directory")) unless Dir.exists?(File.dirname(File.expand_path(output)))
      same = File.expand_path(input) == File.expand_path(output)
      same ||= File.exists?(output) && File.same?(input, output, follow_symlinks: true)
      raise ArgumentError.new(I18n.t!("settings.distinct_files")) if same
      raise ArgumentError.new(I18n.t!("settings.output_exists")) if File.exists?(output) && !overwrite
      expected = ".#{PRESETS[preset].extension}"
      raise ArgumentError.new(I18n.t!("settings.extension", extension: expected)) unless File.extname(output).downcase == expected
      from = Settings.seconds(start) || 0.0
      ending = Settings.seconds(finish)
      raise ArgumentError.new(I18n.t!("settings.end_after_start")) if ending && ending <= from
      raise ArgumentError.new(I18n.t!("settings.start_after_duration")) if total && from >= total
      raise ArgumentError.new(I18n.t!("settings.end_after_duration")) if total && ending && ending > total + 0.05
    end

    def args : Array(String)
      if selected_crop = crop
        raise ArgumentError.new(I18n.t!("settings.crop_requires_reencoding")) unless preset.in?(0, 1, 4, 6)
        raise ArgumentError.new(I18n.t!("settings.crop_invalid")) unless selected_crop.valid?
      end
      from = Settings.seconds(start)
      ending = Settings.seconds(finish)
      raise ArgumentError.new(I18n.t!("settings.end_after_start")) if ending && ending <= (from || 0.0)
      args = ["-hide_banner", "-nostdin", overwrite ? "-y" : "-n", "-progress", "pipe:1", "-nostats"]
      args.concat(["-ss", from.to_s]) if from && from > 0
      args.concat(["-i", File.expand_path(input.empty? ? "input.mp4" : input)])
      args.concat(["-t", (ending - (from || 0.0)).to_s]) if ending
      case preset
      when 0, 1, 6
        args.concat(["-map", "0:v:0", "-map", "0:a:0?"])
        if preset == 0
          args.concat(["-c:v", "libx264", "-preset", speed, "-crf", crf.to_s, "-pix_fmt", "yuv420p", "-movflags", "+faststart"])
        elsif preset == 1
          args.concat(["-c:v", "libvpx-vp9", "-crf", crf.to_s, "-b:v", "0", "-pix_fmt", "yuv420p"])
        else
          args.concat(["-c:v", "libx265", "-preset", speed, "-crf", crf.to_s, "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-tag:v", "hvc1"])
        end
        filters = [] of String
        filters << crop.not_nil!.filter if crop
        filters << (width > 0 ? "scale=#{width}:-2" : "scale=trunc(iw/2)*2:trunc(ih/2)*2")
        filters << "fps=#{fps}" if fps > 0
        args.concat(["-vf", filters.join(',')])
        if mute
          args << "-an"
        else
          args.concat(["-c:a", preset == 1 ? "libopus" : "aac", "-b:a", "#{audio_bitrate}k"])
          append_audio_options(args)
        end
      when 2, 3, 7
        codec = {2 => "libmp3lame", 3 => "pcm_s16le", 7 => "flac"}[preset]
        args.concat(["-map", "0:a:0", "-vn", "-c:a", codec])
        args.concat(["-b:a", "#{audio_bitrate}k"]) if preset == 2
        append_audio_options(args)
      when 4
        filters = [] of String
        filters << crop.not_nil!.filter if crop
        filters << "fps=#{fps}" if fps > 0
        filters << "scale=#{width}:-1:flags=lanczos" if width > 0
        filters << "split[a][b];[a]palettegen[p];[b][p]paletteuse"
        args.concat(["-map", "0:v:0", "-an", "-vf",
                     filters.join(','),
                     "-loop", "0"])
      when 5
        args.concat(["-map", "0:v:0?", "-map", "0:a:0?", "-c", "copy"])
        args << "-an" if mute
      end
      args.concat(["-map_metadata", "-1"]) if strip_metadata
      args << File.expand_path(output.empty? ? "output.#{PRESETS[preset].extension}" : output)
    end

    private def append_audio_options(args : Array(String))
      args.concat(["-ar", audio_sample_rate.to_s]) if audio_sample_rate > 0
      args.concat(["-ac", audio_channels.to_s]) if audio_channels > 0
    end

    def command : String
      arguments = args
      lines = ["ffmpeg"]
      index = 0
      while index < arguments.size - 1
        option = arguments[index]
        if VALUELESS_OPTIONS.includes?(option)
          lines << Process.quote(option)
        else
          lines << Process.quote([option, arguments[index + 1]])
          index += 1
        end
        index += 1
      end
      lines << Process.quote(arguments.last)
      {% if flag?(:win32) %}
        lines.join(" ^\r\n  ")
      {% else %}
        lines.join(" \\\n  ")
      {% end %}
    end
  end

  record MediaInfo, duration : Float64?, summary : String, video : Bool = false,
    video_width : Int32? = nil, video_height : Int32? = nil do
    def video_size : Tuple(Int32, Int32)?
      if (width = video_width) && (height = video_height)
        {width, height}
      end
    end

    def self.parse(text : String) : self
      json = JSON.parse(text)
      duration = json["format"]?.try(&.["duration"]?).try(&.as_s?).try(&.to_f64?)
      duration = nil unless duration && duration.finite? && duration > 0
      streams = json["streams"]?.try(&.as_a?) || [] of JSON::Any
      descriptions = streams.map do |stream|
        type = stream["codec_type"]?.try(&.as_s?) || "?"
        type = I18n.t!("media.#{type}") if type == "video" || type == "audio"
        codec = stream["codec_name"]?.try(&.as_s?) || "?"
        size = type == "video" ? "  #{stream["width"]?} × #{stream["height"]?}" : ""
        "#{type}: #{codec}#{size}"
      end
      first_video = streams.find { |stream| stream["codec_type"]?.try(&.as_s?) == "video" }
      width = first_video.try(&.["width"]?.try(&.as_i?))
      height = first_video.try(&.["height"]?.try(&.as_i?))
      new(duration, descriptions.join("\n"), !first_video.nil?, width, height)
    end
  end
end
