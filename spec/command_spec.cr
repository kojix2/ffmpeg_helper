require "spec"
require "file/tempfile"
require "../src/command"

describe FFmpegGUI::Settings do
  it "keeps shell metacharacters and spaces in a single input argument" do
    settings = FFmpegGUI::Settings.new
    settings.input = File.expand_path("a '日本語'; $(touch nope).mp4", Dir.tempdir)
    settings.output = File.expand_path("my output.mp4", Dir.tempdir)
    args = settings.args
    args[args.index("-i").not_nil! + 1].should eq(settings.input)
    args.last.should eq(settings.output)
    command = settings.command
    {% if flag?(:win32) %}
      Process.parse_arguments(command.gsub(" ^\r\n  ", " ")).should eq(["ffmpeg"] + args)
    {% else %}
      command.should contain("-progress pipe:1 \\\n  -nostats")
      Process.parse_arguments(command.gsub(" \\\n  ", " ")).should eq(["ffmpeg"] + args)
    {% end %}
    args.should contain("-n")
    args.should_not contain("-y")
  end

  it "converts an absolute out point to duration and seeks before input" do
    settings = FFmpegGUI::Settings.new
    settings.start = "00:01:02.5"
    settings.finish = "70"
    args = settings.args
    args[args.index("-ss").not_nil! + 1].should eq("62.5")
    args[args.index("-t").not_nil! + 1].should eq("7.5")
    args.index("-ss").not_nil!.should be < args.index("-i").not_nil!
    settings.duration(120.0).should eq(7.5)
  end

  it "rejects nonfinite, negative, and invalid timestamps" do
    ["NaN", "Infinity", "-1", "00:60:00", "x", "1:2:3:4"].each do |value|
      expect_raises(ArgumentError) { FFmpegGUI::Settings.seconds(value) }
    end
    FFmpegGUI::Settings.seconds("").should be_nil
    settings = FFmpegGUI::Settings.new
    settings.start = "10"
    settings.finish = "9"
    expect_raises(ArgumentError) { settings.args }
  end

  it "never includes encoder or filter options in stream copy mode" do
    settings = FFmpegGUI::Settings.new
    settings.preset = 5
    settings.width = 640
    settings.fps = 30
    settings.args.should contain("copy")
    settings.args.should_not contain("-vf")
    settings.args.should_not contain("-crf")
  end

  it "does not let the video mute checkbox suppress extracted audio" do
    settings = FFmpegGUI::Settings.new
    settings.mute = true
    [2, 3].each do |preset|
      settings.preset = preset
      settings.args.should_not contain("-an")
      settings.args.should contain("0:a:0")
    end
  end

  it "builds H.265 MP4 and FLAC outputs" do
    settings = FFmpegGUI::Settings.new
    settings.preset = 6
    settings.args.should contain("libx265")
    settings.args.should contain("hvc1")
    settings.preset = 7
    settings.args.should contain("flac")
    settings.args.should_not contain("-b:a")
  end

  it "applies channel count and sample rate only when encoding audio" do
    settings = FFmpegGUI::Settings.new
    settings.audio_sample_rate = 44100
    settings.audio_channels = 1
    [0, 1, 2, 3, 6, 7].each do |preset|
      settings.preset = preset
      args = settings.args
      args[args.index("-ar").not_nil! + 1].should eq("44100")
      args[args.index("-ac").not_nil! + 1].should eq("1")
    end
    settings.mute = true
    settings.preset = 0
    settings.args.should_not contain("-ar")
    settings.args.should_not contain("-ac")
    [4, 5].each do |preset|
      settings.preset = preset
      settings.args.should_not contain("-ar")
      settings.args.should_not contain("-ac")
    end
  end

  it "crops before scaling or GIF palette generation and rejects stream copy" do
    settings = FFmpegGUI::Settings.new
    settings.crop = FFmpegGUI::Crop.new(16, 18, 80, 54)
    settings.width = 128
    [0, 1, 6].each do |preset|
      settings.preset = preset
      filter = settings.args[settings.args.index("-vf").not_nil! + 1]
      filter.should start_with("crop=80:54:16:18:exact=1,scale=")
    end
    settings.preset = 4
    filter = settings.args[settings.args.index("-vf").not_nil! + 1]
    filter.should start_with("crop=80:54:16:18:exact=1,")
    filter.should contain("palettegen")
    settings.preset = 5
    expect_raises(ArgumentError, I18n.t!("settings.crop_requires_reencoding")) { settings.args }
    settings.preset = 0
    settings.crop = FFmpegGUI::Crop.new(-1, 0, 80, 54)
    expect_raises(ArgumentError, I18n.t!("settings.crop_invalid")) { settings.args }
  end

  it "rejects input aliases and protects existing outputs" do
    File.tempfile("ffmpeg-source", ".mp4") do |input|
      File.tempfile("ffmpeg-target", ".mp4") do |output|
        settings = FFmpegGUI::Settings.new
        settings.input = input.path
        settings.output = input.path
        settings.overwrite = true
        expect_raises(ArgumentError, I18n.t!("settings.distinct_files")) { settings.validate! }
        settings.output = output.path
        settings.overwrite = false
        expect_raises(ArgumentError, I18n.t!("settings.output_exists")) { settings.validate! }
        settings.overwrite = true
        settings.validate!
        settings.start = "30"
        expect_raises(ArgumentError, I18n.t!("settings.start_after_duration")) { settings.validate!(10.0) }
      end
    end
  end

  {% unless flag?(:win32) %}
    it "protects the input even through symlinks and hard links" do
      File.tempfile("ffmpeg-alias-source", ".mp4") do |input|
        alias_path = input.path + ".alias.mp4"
        settings = FFmpegGUI::Settings.new
        settings.input = input.path
        settings.output = alias_path
        settings.overwrite = true
        begin
          File.symlink(input.path, alias_path)
          expect_raises(ArgumentError, I18n.t!("settings.distinct_files")) { settings.validate! }
          File.delete(alias_path)
          File.link(input.path, alias_path)
          expect_raises(ArgumentError, I18n.t!("settings.distinct_files")) { settings.validate! }
        ensure
          File.delete(alias_path) if File.exists?(alias_path)
        end
      end
    end
  {% end %}
end

describe FFmpegGUI::MediaInfo do
  it "accepts streams with missing duration" do
    info = FFmpegGUI::MediaInfo.parse(%({"streams":[{"codec_type":"audio","codec_name":"mp3"}],"format":{}}))
    info.duration.should be_nil
    info.summary.should eq("#{I18n.t!("media.audio")}: mp3")
  end

  it "reads the first video dimensions for crop coordinates" do
    info = FFmpegGUI::MediaInfo.parse(%({"streams":[{"codec_type":"video","codec_name":"h264","width":160,"height":90},{"codec_type":"video","codec_name":"h264","width":1920,"height":1080}],"format":{}}))
    info.video_size.should eq({160, 90})
  end
end
