# FFmpeg Helper

A small native desktop app for building, reviewing, and running FFmpeg commands. Built with [Crystal](https://crystal-lang.org/) and [UIng](https://github.com/kojix2/uing). Available in English, Japanese, Simplified Chinese, and Spanish. 

## Requirements and build

- Crystal 1.21 or newer
- `ffmpeg` and `ffprobe` on `PATH` (`ffprobe` is optional for command generation and conversion)
- The platform libraries required by UIng; see its [installation guide](https://kojix2.github.io/uing/books/guide_en/installation.html)

From this repository's root:

```sh
shards install
make run
```

`shards install` installs UIng, libui-ng, and [crystal-i18n/i18n](https://github.com/crystal-i18n/i18n). To build without launching the GUI, use `make build`. You can open a source file at launch:

```sh
./bin/ffmpeg_helper "/path/to/video.mp4"
```

## Language

The app checks `FFMPEG_HELPER_LANG`, `LC_ALL`, `LC_MESSAGES`, then `LANG`. Use `--lang en`, `--lang ja`, `--lang zh`, or `--lang es` to override detection. Region tags such as `zh_CN.UTF-8` also work. Unsupported system languages fall back to English. Translations are embedded in the binary at build time.

```sh
./bin/ffmpeg_helper --lang ja
```

## Using the app

1. Open one local video or audio file. When available, `ffprobe` reads its duration, streams, and dimensions.
2. Choose an output format in the sidebar, then adjust conversion settings and the output path.
3. Use the Preview & Trim tab to inspect source frames, select a time range, and drag on the frame to select a rectangular crop. Crop works with re-encoding video presets.
4. Review or save the generated command in the Command tab. It is formatted with one option per line and platform-appropriate quoting.
5. Start conversion. Progress and the FFmpeg log appear in the app; Stop cancels the process.

The preview shows frames from the original file, not the encoded result. The timeline supports Left/Right to move by one second, Shift+Left/Right by ten seconds, Home/End to jump, and I/O to set the trim points.

Available presets are MP4/H.264, WebM/VP9, MP3, WAV, GIF, MKV stream copy, MP4/H.265, and FLAC. The app processes one file at a time and uses the first video and audio streams. It does not include subtitles, attachments, batch processing, or playback. Stream-copy trim points can differ from the selected times because they depend on keyframes.

Output files are not overwritten by default. A cancelled or failed conversion may leave a partial output file. Commands are executed with an argument array, without invoking a shell; the formatted command is for review and manual use.

## Development

```sh
make test          # command, localization, and preview tests
make integration   # FFmpeg/ffprobe presets, progress, and cancellation
make smoke         # GUI smoke test; requires a display
```

The interface uses UIng's toolbar, boxes, grid, Area, tabs, controls, and file dialogs. FFmpeg and ffprobe jobs run on separate Crystal execution contexts; the GUI polls their state on the main thread.

## License

MIT. See [LICENSE](LICENSE). FFmpeg, UIng, libui-ng, and i18n are separate projects with their own licenses.
