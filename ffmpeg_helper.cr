require "./src/app"

path = nil
language = nil
arguments = ARGV.dup
until arguments.empty?
  argument = arguments.shift
  if argument == "--lang"
    language = arguments.shift? || raise ArgumentError.new("--lang requires #{FFmpegGUI::Localization::LANGUAGE_HINT}")
  elsif argument.starts_with?("--lang=")
    language = argument[7..]
  elsif path.nil?
    path = argument
  else
    raise ArgumentError.new("Unexpected argument: #{argument}")
  end
end
FFmpegGUI::Localization.activate(language) if language

UIng.init do
  FFmpegGUI::App.new.run(path)
end
