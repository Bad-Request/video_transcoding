# The golden sweep matrix.
#
# Each case names a tool, a fixture, and the arguments to pass. The harness
# runs the case against an implementation (ruby or powershell) and compares
# the emitted command line to test/golden/<set>/<name>.txt.
#
# Cases are grouped only for readability; the names must stay unique and
# stable, because they are the golden filenames.
#
# `Diverges` marks a case whose expected output is NOT the same for the Ruby
# original and the PowerShell port, because the port deliberately fixes a
# defect or changes a default. Those cases live in golden/divergent instead
# of golden/parity, and the harness knows to expect two different answers.

@{
    # -----------------------------------------------------------------
    # transcode-video: video modes
    # -----------------------------------------------------------------
    'mode-default-1080p' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @()
    }
    'mode-default-720p' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @()
    }
    'mode-default-480p' = @{
        Tool = 'transcode-video'; Fixture = 'dvd-ntsc'; Arguments = @()
    }
    'mode-default-4k' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @()
    }
    'mode-h264-explicit' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--mode', 'h264')
    }
    'mode-hevc' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'hevc')
    }
    'mode-nvenc-hevc' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'nvenc-hevc')
    }
    'mode-av1' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'av1')
    }
    'mode-nvenc-av1' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'nvenc-av1')
    }
    'mode-none' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--mode', 'none')
    }
    'mode-nvenc-hevc-no-bframe-refs' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'
        Arguments = @('--mode', 'nvenc-hevc', '--no-bframe-refs')
    }
    'mode-nvenc-av1-no-bframe-refs' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'
        Arguments = @('--mode', 'nvenc-av1', '--no-bframe-refs')
    }

    # -----------------------------------------------------------------
    # transcode-video: ratecontrol
    # -----------------------------------------------------------------
    'rate-bitrate-h264' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--bitrate', '4000')
    }
    'rate-bitrate-clamped-low' = @{
        # Clamped up to 80% of the tier default (5000 -> 4000 floor).
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--bitrate', '1')
    }
    'rate-bitrate-clamped-high' = @{
        # Clamped down to 160% of the tier default (5000 -> 8000 ceiling).
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--bitrate', '99999')
    }
    'rate-quality-h264' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--quality', '22.5')
    }
    'rate-quality-clamped-low' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--quality', '0.1')
    }
    'rate-quality-clamped-high' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--quality', '99')
    }
    'rate-quality-av1' = @{
        # av1 re-clamps to 0..63 after the generic 1..51 clamp; 55 is only
        # reachable through the av1 branch.
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'av1', '--quality', '55')
    }
    'rate-quality-hevc' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'hevc', '--quality', '26')
    }
    'rate-bitrate-then-quality' = @{
        # Last one wins, and clears the other.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'
        Arguments = @('--bitrate', '4000', '--quality', '22')
    }
    'rate-quality-then-bitrate' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'
        Arguments = @('--quality', '22', '--bitrate', '4000')
    }
    'preset-av1' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'av1', '--preset', '4')
    }
    'preset-av1-clamped' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'av1', '--preset', '99')
    }
    'preset-hevc' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'; Arguments = @('--mode', 'hevc', '--preset', 'slow')
    }

    # -----------------------------------------------------------------
    # transcode-video: audio
    # -----------------------------------------------------------------
    'audio-default-surround' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @()
    }
    'audio-mode-opus' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--audio-mode', 'opus')
    }
    'audio-mode-eac3' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--audio-mode', 'eac3')
    }
    'audio-mode-none' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--audio-mode', 'none')
    }
    'audio-ac3-surround' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--ac3-surround')
    }
    'audio-ac3-surround-copy' = @{
        # ac3 + >2ch + --ac3-surround takes the copy branch rather than ac3.
        Tool = 'transcode-video'; Fixture = 'multitrack'
        Arguments = @('--ac3-surround', '--add-audio', '1')
    }
    'audio-aac-encoder-fdk' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--aac-encoder', 'fdk_aac')
    }
    'audio-aac-passthrough' = @{
        # Source is already aac and <= 6ch, so the encoder is copy.
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @()
    }
    'audio-add-by-track' = @{
        Tool = 'transcode-video'; Fixture = 'multitrack'
        Arguments = @('--add-audio', '2', '--add-audio', '3')
    }
    'audio-add-by-language' = @{
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('--add-audio', 'fra')
    }
    'audio-add-by-language-all' = @{
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('--add-audio', 'all')
    }
    'audio-add-by-title' = @{
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('--add-audio', 'Commentary')
    }
    'audio-add-title-non-ascii' = @{
        # The title carries a non-ASCII character all the way to --aname.
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('--add-audio', 'Fran')
    }
    'audio-add-title-with-comma' = @{
        # The title contains a comma, which gets the gsub(/,/, '","') treatment
        # because --aname is itself a comma-separated list.
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('--add-audio', 'Komma')
    }
    'audio-add-out-of-order' = @{
        # Selection order drives output order; track 1's name suppression is
        # keyed on the SOURCE index, which is the behaviour under review.
        Tool = 'transcode-video'; Fixture = 'multitrack'
        Arguments = @('--add-audio', '3', '--add-audio', '1')
    }
    'audio-add-duplicate' = @{
        # uniq! collapses a repeated identical selection.
        Tool = 'transcode-video'; Fixture = 'multitrack'
        Arguments = @('--add-audio', '2', '--add-audio', '2')
    }
    'audio-add-missing-track' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('--add-audio', '9')
    }

    # -----------------------------------------------------------------
    # transcode-video: subtitles
    # -----------------------------------------------------------------
    'sub-forced-text-default' = @{
        # A forced TEXT subtitle is included and flagged default, not burned.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @()
    }
    'sub-forced-pgs-burned' = @{
        # A forced BITMAP subtitle is burned into the video instead.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-pgs'; Arguments = @()
    }
    'sub-burn-explicit-track' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @('--burn-subtitle', '3')
    }
    'sub-burn-none' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-pgs'; Arguments = @('--burn-subtitle', 'none')
    }
    'sub-add-by-track' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'
        Arguments = @('--add-subtitle', '2')
    }
    'sub-add-by-language' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @('--add-subtitle', 'fra')
    }
    'sub-add-all' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @('--add-subtitle', 'all')
    }
    'sub-add-by-title' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @('--add-subtitle', 'Signs')
    }
    'sub-add-disables-burn' = @{
        # --add-subtitle clears a previously requested burn.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-pgs'
        Arguments = @('--burn-subtitle', '1', '--add-subtitle', '1')
    }
    'sub-forced-late-add-all' = @{
        # The forced track is subtitle 3, and get_subtitle_options always puts
        # the forced track FIRST in the selection. So --subtitle reads "3,1,2"
        # while --subtitle-default is given "3" - an absolute track number
        # sitting in list position 1. If HandBrakeCLI reads that argument as a
        # list index, this flags the wrong track as default.
        Tool = 'transcode-video'; Fixture = 'forced-late'
        Arguments = @('--add-subtitle', 'all')
    }
    'sub-forced-late-add-language' = @{
        # Narrower version of the same question: only the forced French track
        # is selected, so --subtitle is "3" and --subtitle-default is "3",
        # where the list index would be 1.
        Tool = 'transcode-video'; Fixture = 'forced-late'
        Arguments = @('--add-subtitle', 'fra')
    }
    'sub-add-with-forced-default' = @{
        # The forced track is picked up first and becomes --subtitle-default.
        # This is the case that exposes whether the default index is absolute
        # or relative to the --subtitle list.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'
        Arguments = @('--add-subtitle', 'all')
    }

    # -----------------------------------------------------------------
    # transcode-video: --extra passthrough
    # -----------------------------------------------------------------
    'extra-simple-flag' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'no-multi-pass')
    }
    'extra-name-value' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'chapters=3-5')
    }
    'extra-equals-list-member' = @{
        # One of the 23 names that must be emitted as --name=value.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'detelecine=light')
    }
    'extra-equals-list-deblock' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'deblock=strong')
    }
    'extra-format-mp4' = @{
        # Changes the output extension, and is the faststart path.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'format=av_mp4')
        Diverges = 'faststart: adds --optimize'
    }
    'extra-format-mkv' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'format=av_mkv')
    }
    'extra-format-webm' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'format=av_webm')
    }
    'extra-encopts-merge' = @{
        # User encopts are appended to the generated VBV settings.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'
        Arguments = @('-x', 'encopts=ref=5:bframes=8')
    }
    'extra-encopts-merge-nvenc' = @{
        Tool = 'transcode-video'; Fixture = 'uhd-hdr'
        Arguments = @('--mode', 'nvenc-hevc', '-x', 'encopts=temporal-aq=1')
    }
    'extra-custom-encoder' = @{
        # A custom encoder suppresses all generated encoder options and VBV.
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'encoder=x264_10bit')
    }
    'extra-crop-override' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'crop=140:140:0:0')
    }
    'extra-aencoder-copy' = @{
        Tool = 'transcode-video'; Fixture = 'bluray-1080p-forced'; Arguments = @('-x', 'aencoder=copy')
    }
    'extra-rate-override' = @{
        Tool = 'transcode-video'; Fixture = 'dvd-ntsc'; Arguments = @('-x', 'rate=25')
    }
    'extra-audio-override' = @{
        Tool = 'transcode-video'; Fixture = 'multitrack'; Arguments = @('-x', 'all-audio')
    }
    'extra-subtitle-override' = @{
        Tool = 'transcode-video'; Fixture = 'mixed-subtitles'; Arguments = @('-x', 'all-subtitles')
    }

    # -----------------------------------------------------------------
    # convert-video
    # -----------------------------------------------------------------
    'convert-mkv-to-mp4' = @{
        Tool = 'convert-video'; Fixture = 'bluray-1080p-forced'; Arguments = @()
        Diverges = 'faststart: -movflags +faststart+disable_chpl'
    }
    'convert-mkv-mixed-subtitles' = @{
        # The defect case: an ASS track is dropped before a subrip track is
        # mapped, so the Ruby original emits -c:s:1 for output subtitle 0.
        Tool = 'convert-video'; Fixture = 'mixed-subtitles'; Arguments = @()
        Diverges = 'subtitle ordinal fix, and faststart'
    }
    'convert-mp4-to-mkv' = @{
        # The other branch: no faststart, no stream mapping, -c:s copy.
        Tool = 'convert-video'; Fixture = 'mp4-source'; Arguments = @()
    }
    'convert-multitrack' = @{
        Tool = 'convert-video'; Fixture = 'multitrack'; Arguments = @()
        Diverges = 'faststart'
    }

    # -----------------------------------------------------------------
    # detect-crop
    # -----------------------------------------------------------------
    'crop-conservative' = @{
        Tool = 'detect-crop'; Fixture = 'bluray-1080p-forced'; Arguments = @()
    }
    'crop-auto' = @{
        Tool = 'detect-crop'; Fixture = 'bluray-1080p-forced'; Arguments = @('--mode', 'auto')
    }
}
