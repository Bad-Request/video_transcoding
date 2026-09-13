# Video Transcoding

Tools to transcode, inspect and convert videos.

## About

> [!IMPORTANT]
> *This is a breaking fork of [Lisa Melton's video_transcoding](https://github.com/lisamelton/video_transcoding), rewritten in PowerShell. The Ruby runtime is no longer needed, and the command-line interface is now native PowerShell rather than GNU-style: `-Mode hevc` instead of `--mode hevc`. Every example below has changed accordingly. See [CHANGELOG.md](CHANGELOG.md) for the full list of differences, including two bug fixes that change behaviour.*

These tools transcode Blu-ray Discs and DVDs into a smaller, more portable format while remaining high enough quality to be mistaken for the originals.

Most of them are intelligent wrappers around [HandBrake](https://handbrake.fr/) and [FFmpeg](http://ffmpeg.org/), designed to be run from a command line:

* `transcode-video.ps1`
Transcode essential media tracks into a smaller, more portable format while remaining high enough quality to be mistaken for the original.

* `detect-crop.ps1`
Detect the unused outside area of video tracks and print TOP:BOTTOM:LEFT:RIGHT crop values.

* `convert-video.ps1`
Convert a media file from Matroska `.mkv` to MP4, or other media to Matroska, without transcoding.

## Installation

These tools work on Windows, Linux and macOS. Clone the repository:

    git clone https://github.com/Bad-Request/video_transcoding.git

On Linux and macOS, make the scripts executable:

    chmod +x transcode-video.ps1 detect-crop.ps1 convert-video.ps1

They carry a `#!/usr/bin/env pwsh` shebang, so they can then be run directly. Move or copy them, together with `VideoTranscoding.psd1` and `VideoTranscoding.psm1`, to a directory on your `PATH`. The two module files must stay alongside the scripts.

### Requirements

**PowerShell 7.4 or later.** Windows PowerShell 5.1 will not work: it lacks features these scripts rely on, and has the broken native-argument quoting this rewrite exists to stop working around. See "[Installing PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)".

These command line programs must also be on your `PATH`:

* `HandBrakeCLI`
* `ffprobe`
* `ffmpeg`

See "[HandBrake Downloads (Command Line)](https://handbrake.fr/downloads2.php)" and "[Download FFmpeg](https://ffmpeg.org/download.html)".

On macOS, both are available via [Homebrew](http://brew.sh/):

    brew install handbrake ffmpeg

On Windows, via [winget](https://learn.microsoft.com/windows/package-manager/winget/):

    winget install HandBrake.HandBrake.CLI
    winget install Gyan.FFmpeg

`ffprobe` is included with `ffmpeg`.

## Usage

Every tool takes one or more media files:

    ./transcode-video.ps1 C:\Rips\Movie.mkv

They accept pipeline input, which is the easy way to do a batch:

    Get-ChildItem C:\Rips\*.mkv | ./transcode-video.ps1

Use `Get-Help` for the full list of options:

    Get-Help ./transcode-video.ps1 -Full

Parameter names tab-complete, and so do the values of `-Mode`, `-AudioMode` and `-AacEncoder`.

Use `-WhatIf` to see the `HandBrakeCLI` command a run would produce without running it:

    ./transcode-video.ps1 C:\Rips\Movie.mkv -WhatIf

> [!NOTE]
> *Calling these scripts as `pwsh -File transcode-video.ps1 ...` — from a shell script, say — cannot pass a list to `-AddAudio`, `-AddSubtitle` or `-Extra`. `-File` hands arguments over as plain strings and never parses `2,3` as two values. Use `pwsh -Command` for those, or call the script from a PowerShell prompt.*

## Default `transcode-video.ps1` behavior

Creates a Matroska `.mkv` file in the current working directory with video in 8-bit H.264 and audio in multichannel AAC.

4K inputs are automatically scaled to 1080p and HDR is converted to SDR. Video is automatically cropped. The first audio track, if available, is automatically selected. Any forced subtitle is automatically burned into the video track or included as a separate text-only track depending on its original format.

The venerable `x264` software-based encoder is used with two-pass ratecontrol to produce a constant bitrate. Using two passes _is_ a bit slower than other methods but the output quality is worth the wait, as is the output size. This Is The Way™.

**Video:**

Resolution | H.264 bitrate
--- | ---
1080p (Blu-ray) | 5000 Kbps
720p | 2500 Kbps
480p (DVD) | 1250 Kbps

**Audio:**

Channels | AAC bitrate
--- | ---
Surround | 384 Kbps
Stereo | 128 Kbps
Mono | 80 Kbps

All of this can be changed with `-Mode` and `-AudioMode`, with options like `-AddAudio`, or by passing arguments straight to `HandBrakeCLI` via `-Extra`. It's very, very flexible.

## Other video modes

The default is focused on high-quality 1080p and smaller SDR video. Other modes are available.

### `-Mode hevc`

Designed for 4K HDR content, this mode uses the `x265_10bit` software-based encoder with a constant quality (instead of a constant bitrate) ratecontrol system. But it's reeeeeally slow. I mean, really slow. However, it does produce high-quality output. You just have to decide whether it's worth it.

One big selling point is that the `x265_10bit` encoder can produce output compatible with both the [HDR10](https://en.wikipedia.org/wiki/HDR10) and [HDR10+](https://en.wikipedia.org/wiki/HDR10%2B) standards as well as [Dolby Vision](https://en.wikipedia.org/wiki/Dolby_Vision).

### `-Mode nvenc-hevc`

Also designed for 4K HDR content, this mode uses the `nvenc_h265_10bit` Nvidia hardware-based encoder, also with a constant quality ratecontrol system, because you can't always afford to wait on `x265_10bit`. The output will be slightly larger and somewhat lesser in quality but you'll get it a LOT faster. A lot.

But be aware that the `nvenc_h265_10bit` encoder can only produce HDR10-compatible output.

### `-Mode av1`

This Is The Future. Unfortunately, the [AV1 video format](https://en.wikipedia.org/wiki/AV1) is currently the Star Trek Future. Other than desktop PCs, most devices can't play it yet. This mode uses the `svt_av1_10bit` software-based encoder with a constant quality ratecontrol system. Although the encoder is already quite good, it's still a work in progress. But it's faster than `x265_10bit` and usually produces smaller output. So it's certainly worth a try. Especially on 4K HDR content.

The `svt_av1_10bit` encoder can produce output compatible with the HDR10 and HDR10+ standards and pass through Dolby Vision metadata.

When using this mode, audio output is in Opus format at slightly lower bitrates. Why Opus? Because it's higher quality than AAC and if you can play AV1 format video then you can certainly play Opus format audio. An explicit `-AudioMode` always overrides that.

### `-Mode nvenc-av1`

This mode uses the `nvenc_av1_10bit` Nvidia hardware-based encoder, also with a constant quality ratecontrol system. The output is actually about the same size as that from the software-based `svt_av1_10bit` encoder in `av1` mode, but this is MUCH faster.

Be aware that, like other Nvidia encoders, `nvenc_av1_10bit` can only produce HDR10-compatible output. And like `av1` mode, audio output is in Opus format at slightly lower bitrates.

## Ratecontrol

`-Bitrate` and `-Quality` cannot be combined; PowerShell will refuse the command. Pick the one that suits the mode:

    ./transcode-video.ps1 C:\Rips\Movie.mkv -Bitrate 4000
    ./transcode-video.ps1 C:\Rips\Movie.mkv -Mode hevc -Quality 22

`-Bitrate` tunes the default for the input resolution rather than replacing it: the value is clamped to between 80% and 160% of the figure in the table above.

## Calling `HandBrakeCLI` from `transcode-video.ps1`

`transcode-video.ps1` has around twenty options. The `HandBrakeCLI` API has over a hundred. It's YUUUUUGE! And you can pass arguments straight to that API with `-Extra`.

Tweak a crop instead of relying on `HandBrakeCLI`'s algorithm:

    ./transcode-video.ps1 -Extra crop=140:140:0:0 C:\Rips\Movie.mkv

Get faster results, living dangerously, by disabling two-pass transcoding:

    ./transcode-video.ps1 -Extra no-multi-pass C:\Rips\Movie.mkv

Apply any of `HandBrakeCLI`'s built-in filters:

    ./transcode-video.ps1 -Extra detelecine C:\Rips\Movie.mkv

Waste space by keeping your original audio track:

    ./transcode-video.ps1 -Extra aencoder=copy C:\Rips\Movie.mkv

Output only an excerpt:

    ./transcode-video.ps1 -Extra chapters=3-5 C:\Rips\Movie.mkv

Pass several at once — from a PowerShell prompt, since this is a list:

    ./transcode-video.ps1 -Extra detelecine,no-multi-pass C:\Rips\Movie.mkv

## Output format

Matroska is the default. `-Format` picks another container:

    ./transcode-video.ps1 C:\Rips\Movie.mkv -Format mp4
    ./transcode-video.ps1 C:\Rips\Movie.mkv -Format webm

The value tab-completes, and the output file gets the matching extension. This
is shorthand for `-Extra format=av_mp4`, which still works; giving both is an
error rather than one silently winning.

## MP4 faststart

MP4 output gets its index moved to the front of the file, so it can start playing before it has fully downloaded. `transcode-video.ps1` does this with HandBrake's `--optimize` whenever `-Format mp4` is in play; `convert-video.ps1` does it with ffmpeg's `-movflags +faststart`.

It costs a second pass over the finished file, which on a large remux means rewriting every byte again. Turn it off with `-NoFaststart` when you are working locally and nothing will ever stream the result:

    ./convert-video.ps1 C:\Rips\Movie.mkv -NoFaststart
    ./transcode-video.ps1 C:\Rips\Movie.mkv -Format mp4 -NoFaststart

Matroska output is unaffected — it has no such index.

## Detecting crop values

    ./detect-crop.ps1 C:\Rips\Movie.mkv
    140:140:0:0

Use `-AsObject` when a script is reading the result rather than a person:

    Get-ChildItem C:\Rips\*.mkv | ./detect-crop.ps1 -AsObject |
        Where-Object { $_.Top -gt 0 }

## Testing

The repository carries a golden-file harness that verifies the tools without running a single encode. See [test/README.md](test/README.md).

    ./test/Compare-Golden.ps1
    ./test/Test-Module.ps1

## Feedback

Please report bugs or ask questions by [creating a new issue](https://github.com/Bad-Request/video_transcoding/issues) on GitHub.

## Acknowledgements

This project exists because of [Lisa Melton](http://lisamelton.net/), who wrote the original and spent years tuning the ratecontrol settings that make it worth using. The [Video Transcoding Slack](https://videotranscoding.slack.com/) reviewed, tested, documented and supported that work.

## License

Video Transcoding is copyright [Lisa Melton](http://lisamelton.net/) and available under an [MIT license](LICENSE).
