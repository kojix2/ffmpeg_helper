require "spec"
require "yaml"
require "../src/command"

private def translations(node : YAML::Any, prefix = "", result = {} of String => String) : Hash(String, String)
  if children = node.as_h?
    children.each do |key, value|
      name = prefix.empty? ? key.as_s : "#{prefix}.#{key.as_s}"
      translations(value, name, result)
    end
  else
    result[prefix] = node.as_s
  end
  result
end

describe FFmpegGUI::Localization do
  it "accepts language tags and rejects unsupported explicit languages" do
    previous = I18n.locale
    begin
      FFmpegGUI::Localization.activate("ja_JP.UTF-8")
      I18n.locale.should eq("ja")
      FFmpegGUI::Localization.activate("en-US")
      I18n.locale.should eq("en")
      FFmpegGUI::Localization.activate("zh_CN.UTF-8")
      I18n.locale.should eq("zh")
      FFmpegGUI::Localization.activate("es-ES")
      I18n.locale.should eq("es")
      expect_raises(ArgumentError) { FFmpegGUI::Localization.activate("fr") }
      expect_raises(ArgumentError) { FFmpegGUI::Localization.activate("") }
    ensure
      I18n.locale = previous
    end
  end

  it "detects Chinese and Spanish from the language environment" do
    previous_locale = I18n.locale
    previous_language = ENV["FFMPEG_HELPER_LANG"]?
    begin
      ENV["FFMPEG_HELPER_LANG"] = "zh_CN.UTF-8"
      FFmpegGUI::Localization.activate
      I18n.locale.should eq("zh")
      ENV["FFMPEG_HELPER_LANG"] = "es_ES.UTF-8"
      FFmpegGUI::Localization.activate
      I18n.locale.should eq("es")
    ensure
      if previous_language
        ENV["FFMPEG_HELPER_LANG"] = previous_language
      else
        ENV.delete("FFMPEG_HELPER_LANG")
      end
      I18n.locale = previous_locale
    end
  end

  it "provides the same nonempty keys and interpolation parameters in all languages" do
    en = translations(YAML.parse(File.read(File.expand_path("../locales/en.yml", __DIR__)))["en"])
    ["ja", "zh", "es"].each do |locale|
      translated = translations(YAML.parse(File.read(File.expand_path("../locales/#{locale}.yml", __DIR__)))[locale])
      en.keys.sort.should eq(translated.keys.sort)
      en.each do |key, value|
        value.should_not be_empty
        translated[key].should_not be_empty
        value.scan(/%\{[^}]+\}/).map(&.[0]).sort.should eq(translated[key].scan(/%\{[^}]+\}/).map(&.[0]).sort)
      end
    end
  end

  it "translates preset names and validation errors without changing command arguments" do
    settings = FFmpegGUI::Settings.new
    settings.preset = 2
    args = settings.args
    I18n.with_locale(:en) do
      FFmpegGUI::PRESETS[2].title.should eq("MP3 / Audio")
      expect_raises(ArgumentError, "Choose an input file.") { settings.validate! }
    end
    I18n.with_locale(:ja) do
      FFmpegGUI::PRESETS[2].title.should eq("MP3 / 音声抽出")
      expect_raises(ArgumentError, "入力ファイルを選択してください。") { settings.validate! }
    end
    I18n.with_locale(:zh) do
      FFmpegGUI::PRESETS[2].title.should eq("MP3 / 提取音频")
      expect_raises(ArgumentError, "请选择输入文件。") { settings.validate! }
    end
    I18n.with_locale(:es) do
      FFmpegGUI::PRESETS[2].title.should eq("MP3 / Audio")
      expect_raises(ArgumentError, "Selecciona un archivo de entrada.") { settings.validate! }
    end
    settings.args.should eq(args)
  end
end
