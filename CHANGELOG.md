# Changes to the "[Video Transcoding](https://github.com/Bad-Request/video_transcoding)" project

Entries from 2025.01.28 and earlier are from the [upstream project](https://github.com/lisamelton/video_transcoding), which this repository forked from.

## Unreleased — PowerShell rewrite

The three Ruby scripts are reimplemented in PowerShell 7. This is a breaking fork: it will not be merged back upstream, and existing command lines will not work unchanged.

### Requirements

* Ruby is no longer needed. **PowerShell 7.4 or later** is, on Windows, Linux and macOS alike. Windows PowerShell 5.1 is not supported.
* `HandBrakeCLI`, `ffprobe` and `ffmpeg` are still required, and are now checked for up front rather than surfacing as a spawn failure part-way through.

### Breaking: the command-line interface is native PowerShell

GNU-style options are gone. `--mode hevc` is now `-Mode hevc`, `-x format=av_mp4` is now `-Extra format=av_mp4`, and so on throughout. Scripts and aliases built on the old spelling will need updating.

This is not a stylistic choice. PowerShell's parameter binder runs before a script's own code, and rejects `--mode` before the script is reached. Keeping the old spelling required declaring no parameters at all, which in turn rules out tab completion, `[ValidateSet]` validation, `-WhatIf`, pipeline input and `Get-Help`. The two could not coexist on one entry point.

What that buys:

* Pipeline input — `Get-ChildItem *.mkv | ./transcode-video.ps1`.
* Tab completion of parameter names, and of `-Mode`, `-AudioMode` and `-AacEncoder` values.
* `-WhatIf` and `-Confirm`, alongside the existing `-DryRun`.
* `Get-Help ./transcode-video.ps1 -Full`, replacing the hand-maintained usage text.
* `-Verbose` and `-Debug` in place of `--debug`.
* `detect-crop.ps1 -AsObject`, emitting structured results instead of text to be parsed.

### Breaking: options no longer depend on their order

Named parameters are a set, not a sequence, so three behaviours that turned on argument position are now explicit rules:

* `--bitrate` and `--quality` used to override each other, last one winning. `-Bitrate` and `-Quality` are now mutually exclusive, and PowerShell refuses the combination.
* `--add-subtitle` used to cancel an earlier `--burn-subtitle`. `-AddSubtitle` now takes precedence over `-BurnSubtitle` whichever order they appear in.
* `--mode av1` used to overwrite an earlier `--audio-mode`. An explicit `-AudioMode` now always wins over the Opus default that the AV1 modes imply.

### Fixed: `convert-video` could not convert some Matroska files at all

The subtitle counter advanced for tracks that were dropped as well as tracks that were kept, but `-c:s:N` numbers the tracks that are kept. Any `.mkv` with an unsupported subtitle ahead of a supported one — an ASS track before a SubRip one, say — produced `-c:s:1` for what was output subtitle 0, leaving that stream with no encoder. ffmpeg refused the file with "Automatic encoder selection failed … (codec none) is probably disabled" and wrote nothing.

### Fixed: `transcode-video` flagged the wrong default subtitle

`--subtitle-default` is documented by HandBrake as "an index into the subtitle list specified with `--subtitle`", but the absolute input track number was being passed. On a disc whose forced subtitle was not track 1, this flagged the wrong track — or an index past the end of the list. Because the forced track is always placed first in the selection, the correct value is always `1`.

### Changed: MP4 output starts with its index

MP4 output now has its index moved to the front of the file so it can begin playing before it has fully downloaded — `--optimize` for HandBrake, `-movflags +faststart` for ffmpeg. This costs a second pass over the finished file, so `-NoFaststart` turns it off. Matroska output is unaffected.

### Changed: smaller things

* `-DryRun` and `-WhatIf` print a command line that can be pasted back into PowerShell. The Ruby version emitted `cmd.exe`-style quoting on Windows, which was not valid in the shell the user was standing in.
* Console output encoding is pinned to UTF-8, so non-ASCII track titles survive on a default Windows host.
* Runtime errors now exit 1 rather than 255. PowerShell's binder owns argument errors, which also exit 1, so the previous split between the two no longer exists.
* `detect-crop`'s undocumented and non-functional `--debug` option is gone, replaced by the standard `-Verbose`.

### Added: a golden-file test harness

`test/` verifies the tools by comparing the argument vectors they hand to HandBrakeCLI and ffmpeg against recorded expectations, using fake tools on `PATH`. No media is touched and no encoding happens, so the full sweep runs in seconds. The Ruby originals are kept in `legacy/` as the reference those expectations were recorded from.


## [2025.01.28](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.28)

Tuesday, January 28, 2025

* Change the `rc-lookahead` value for the `nvenc-hevc` video mode in `transcode-video.rb` from `32` to `20` per current Nvidia guidelines. A value of `32` is the maximum allowed but it's probably unnecessary.
* Add ratecontrol code for the `nvenc-av1` video mode which functionally matches that of `nvenc-hevc` mode.
* Change the `nvenc-av1` video mode `quality` value from `35` to `37`. This will lower output bitrates below that of `nvenc-hevc` mode, a sensible move because AV1 format is supposed to be more size-efficient than HEVC at the same perceived level of quality.

## [2025.01.24](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.24)

Friday, January 24, 2025

* Fix the bogus VBV being set when using a custom encoder with `transcode-video.rb`. This bug was introduced by the previous change.

## [2025.01.23](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.23)

Thursday, January 23, 2025

* Add missing ratecontrol code for the `nvenc-hevc` video mode that was _stupidly_ left out of the original rewrite of `transcode-video.rb`. This also implements the `--no-bframe-refs` option.

## [2025.01.19](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.19)

Sunday, January 19, 2025

* Add `nvenc-av1` video mode to `transcode-video.rb`.

## [2025.01.10](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.10)

Friday, January 10, 2025

* Fix bug preventing `encopts` arguments being passed to the `--extra` option of `transcode-video.rb`.
* Clarify that the automatic behavior of `transcode-video.rb` described in the `README.md` file is for a single forced subtitle and does not apply to multiple subtitles.
* Add note to the `README.md` file regarding possible future video modes for `transcode-video.rb`.

## [2025.01.09](https://github.com/lisamelton/video_transcoding/releases/tag/2025.01.09)

Thursday, January 9, 2025

* Deprecate and remove legacy [RubyGems](https://en.wikipedia.org/wiki/RubyGems)-based project files.
* Remove `*.gem` files from the list to ignore.
* Add redesigned and rewritten tools to the project, i.e. the `transcode-video.rb`, `detect-crop.rb` and `convert-video.rb` scripts.
* Completely update the `README.md` file.
* Begin using a date-based version numbering scheme for the project and all the scripts.

> [!NOTE]
> Changes before version 2025.01.09 are no longer relevant and not included in this document.
