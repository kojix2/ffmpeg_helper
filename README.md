# FFmpeg Helper

A small native GUI for building and running FFmpeg commands. 

Built with [Crystal](https://crystal-lang.org/) and [UIng](https://github.com/kojix2/uing).

Requires Crystal 1.21+, `ffmpeg`, `ffprobe`, and [UIng's platform dependencies](https://kojix2.github.io/uing/books/guide_en/installation.html).

```sh
shards install
make
bin/ffmpeg_helper
```

Supports English, Japanese, Simplified Chinese, and Spanish (`--lang en|ja|zh|es`). [MIT licensed](LICENSE).
