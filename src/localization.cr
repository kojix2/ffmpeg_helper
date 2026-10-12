require "i18n"

module FFmpegGUI
  module Localization
    SUPPORTED_LANGUAGES = ["en", "ja", "zh", "es"]
    LANGUAGE_HINT       = "en, ja, zh or es"

    I18n.config.default_locale = :en
    I18n.config.loaders << I18n::Loader::YAML.embed("#{__DIR__}/../locales")
    I18n.init

    def self.activate(locale : String? = nil) : Nil
      raise ArgumentError.new("--lang requires #{LANGUAGE_HINT}") if locale && locale.empty?
      value = [locale, ENV["FFMPEG_HELPER_LANG"]?, ENV["LC_ALL"]?, ENV["LC_MESSAGES"]?, ENV["LANG"]?].compact.find { |candidate| !candidate.empty? } || "en"
      language = value.downcase.split(/[_.-]/, 2).first
      unless SUPPORTED_LANGUAGES.includes?(language)
        raise ArgumentError.new("Unsupported language: #{value} (use #{LANGUAGE_HINT})") if locale
        language = "en"
      end
      I18n.locale = language
    end
  end
end

FFmpegGUI::Localization.activate
