#!/usr/bin/env pwsh

# The blank line above is load-bearing. Without it PowerShell reads the
# shebang and the help block below as one contiguous comment attached to
# nothing, and Get-Help silently falls back to auto-generated syntax.

<#
.SYNOPSIS
    Transcode essential media tracks into a smaller, more portable format
    while remaining high enough quality to be mistaken for the original.

.DESCRIPTION
    Creates a Matroska .mkv file in the current working directory, with video
    in 8-bit H.264 and audio in multichannel AAC.

    4K input is scaled to 1080p and HDR converted to SDR. Video is cropped
    automatically. The first audio track is selected. Any forced subtitle is
    burned into the video or included as a text track, depending on its
    original format.

.PARAMETER Path
    One or more media files. Accepts pipeline input:

        Get-ChildItem *.mkv | ./transcode-video.ps1

.PARAMETER Mode
    Video encoding mode.

      h264        x264, two-pass constant bitrate. The default, and the one
                  tuned hardest. Slower than the alternatives; worth it.
      hevc        x265_10bit, constant quality. Very slow, very good, and the
                  only software mode that can produce Dolby Vision.
      nvenc-hevc  Nvidia hardware HEVC. Much faster, slightly larger, HDR10
                  only.
      av1         svt_av1_10bit, constant quality. Smaller than HEVC and
                  faster than x265, but few devices can play it yet.
      nvenc-av1   Nvidia hardware AV1. About the same size as svt_av1_10bit
                  and far faster.
      none        Emit no encoder options at all, leaving HandBrake's own
                  defaults in place.

.PARAMETER Preset
    Video encoder preset. Defaults to 8 in av1 mode, and to the encoder's own
    default otherwise.

.PARAMETER Bitrate
    Video bitrate target in Kbps. Clamped to between 80% and 160% of the
    default for the input resolution, so it tunes the tier rather than
    overriding it. Cannot be combined with -Quality.

.PARAMETER Quality
    Constant quality value. Cannot be combined with -Bitrate.

    The two are mutually exclusive on purpose. The Ruby tool this replaces
    accepted both and silently honoured whichever appeared last on the
    command line, which named parameters cannot express and which was a poor
    answer regardless.

.PARAMETER AudioMode
    Audio encoding mode. Defaults to opus in av1 and nvenc-av1 modes, and to
    aac otherwise. An explicit value always wins over that default.

.PARAMETER AddAudio
    Audio tracks to include, in addition to the first. Each entry is a track
    number, a three-letter language code, 'all', or a string matched against
    the track title.

.PARAMETER Ac3Surround
    Use AC-3 for surround audio instead of AAC, for wider player
    compatibility. Raises the default surround bitrate to 448 Kbps.

.PARAMETER AacEncoder
    Which AAC encoder to use. ca_aac exists only on macOS.

.PARAMETER BurnSubtitle
    Subtitle track to burn into the video, or 'none' to burn nothing.
    Defaults to automatic, which burns a forced bitmap subtitle if there is
    one. Text subtitles are included as a track rather than burned.

.PARAMETER AddSubtitle
    Subtitle tracks to include. Each entry is a track number, a three-letter
    language code, 'all', or a string matched against the track title.

    Takes precedence over -BurnSubtitle whichever order they are given in.

.PARAMETER Format
    Output container: mkv (the default), mp4 or webm.

    MP4 output also has its index moved to the front of the file so it can
    start playing before it has fully downloaded; -NoFaststart turns that off.

    Equivalent to -Extra format=av_mp4 and friends, which still work. Giving
    both is an error rather than a silent winner.

.PARAMETER Extra
    Options passed straight through to HandBrakeCLI, each as NAME or
    NAME=VALUE. transcode-video has around twenty options; the HandBrakeCLI
    API has over a hundred, and this is how to reach the rest.

.PARAMETER NoBframeRefs
    Do not use B-frames as reference frames, for compatibility with older
    Nvidia GPUs.

.PARAMETER NoFaststart
    Leave the MP4 index at the end of the file rather than moving it to the
    front. Only meaningful when the output is MP4, via -Format mp4.

.PARAMETER DryRun
    Print the HandBrakeCLI command that would run, and stop. Equivalent to
    -WhatIf.

.PARAMETER Version
    Print version information and exit.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv'

    Transcode with the defaults: H.264 video at the bitrate for the input's
    resolution, multichannel AAC audio, automatic crop, and any forced
    subtitle burned or included. Writes Movie.mkv to the current directory.

.EXAMPLE
    Get-ChildItem 'C:\Rips\*.mkv' | ./transcode-video.ps1

    Transcode a whole directory. Output lands in the current directory, so
    run this from somewhere other than where the sources live - the tool
    refuses to overwrite a file that already exists, and a source and its
    output share a name.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -WhatIf

    Print the HandBrakeCLI command this would run, and stop. The line is
    valid PowerShell, so it can be pasted and edited.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Mode hevc -Quality 22

    Constant-quality HEVC, for 4K HDR sources. Slow, but the only software
    mode that can carry Dolby Vision.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Mode nvenc-hevc

    The same territory on Nvidia hardware: much faster, slightly larger,
    HDR10 only.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -AddAudio 2,fra

    Keep the first audio track, plus track 2 and every French track.
    Selectors are a track number, a three-letter language code, 'all', or
    text matched against the track title.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -AddSubtitle all -BurnSubtitle none

    Include every subtitle as a selectable track and burn none of them into
    the picture. -AddSubtitle wins over -BurnSubtitle anyway, so the second
    switch is belt and braces.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Format mp4

    Output MP4 rather than Matroska. MP4 output also gets its index moved to
    the front of the file; -NoFaststart turns that off.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Format mp4 -NoFaststart

    MP4 without the index move, which costs a second pass over the finished
    file. Worth skipping when nothing will ever stream the result.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Extra crop=140:140:0:0

    Override the automatic crop. ./detect-crop.ps1 prints values in exactly
    this form.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Extra detelecine,no-multi-pass

    Pass several HandBrakeCLI options at once. Note that this list form needs
    a PowerShell prompt or pwsh -Command; pwsh -File cannot parse it.

.EXAMPLE
    ./transcode-video.ps1 'C:\Rips\Movie.mkv' -Verbose

    Show the command line and elapsed time as it works.

.INPUTS
    System.String[]

    File paths, by value or by the FullName property, so output from
    Get-ChildItem pipes in directly.

.OUTPUTS
    None by default; the transcode is the result.

    With -DryRun or -WhatIf, the HandBrakeCLI command line as a string.

.NOTES
    Requires HandBrakeCLI and ffprobe.
.LINK
    detect-crop.ps1

.LINK
    convert-video.ps1

.LINK
    https://github.com/Bad-Request/video_transcoding

.LINK
    https://handbrake.fr/docs/en/latest/cli/command-line-reference.html
#>
[CmdletBinding(DefaultParameterSetName = 'Bitrate', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Bitrate', Mandatory, Position = 0,
               ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Parameter(ParameterSetName = 'Quality', Mandatory, Position = 0,
               ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]] $Path,

    [ValidateSet('h264', 'hevc', 'nvenc-hevc', 'av1', 'nvenc-av1', 'none')]
    [string] $Mode = 'h264',

    [string] $Preset,

    [Parameter(ParameterSetName = 'Bitrate')]
    [int] $Bitrate,

    [Parameter(ParameterSetName = 'Quality')]
    [double] $Quality,

    [ValidateSet('aac', 'opus', 'eac3', 'none')]
    [string] $AudioMode,

    [string[]] $AddAudio,

    [switch] $Ac3Surround,

    [ValidateSet('av_aac', 'fdk_aac', 'ca_aac')]
    [string] $AacEncoder = 'av_aac',

    [string] $BurnSubtitle,

    [string[]] $AddSubtitle,

    [ValidateSet('mkv', 'mp4', 'webm')]
    [string] $Format,

    [string[]] $Extra,

    [switch] $NoBframeRefs,

    [switch] $NoFaststart,

    [switch] $DryRun,

    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch] $Version
)

begin {
    Set-StrictMode -Version 3.0
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'VideoTranscoding.psd1')

    if ($Version) {
        Get-VersionText 'transcode-video.ps1'
        exit 0
    }

    Test-Prerequisite 'HandBrakeCLI', 'ffprobe'

    # -----------------------------------------------------------------
    # -Extra parsing
    # -----------------------------------------------------------------

    # HandBrakeCLI options that must be written --name=value rather than
    # --name value. Getting this list wrong silently regresses a fix that took
    # the upstream project years to land, so it is reproduced verbatim.
    $EqualsRequired = @(
        'verbose', 'comb-detect', 'deinterlace', 'bwdif'
        'decomb', 'detelecine', 'hqdn3d', 'denoise', 'nlmeans'
        'chroma-smooth', 'unsharp', 'lapsharp', 'deblock', 'rotate'
        'subtitle-forced', 'subtitle-burned', 'subtitle-default'
        'srt-default', 'srt-burn', 'ssa-default', 'ssa-burn'
        'qsv-async-depth', 'qsv-adapter'
    )

    # Ordered, because HandBrakeCLI is given these in the order they were
    # written, and a repeated name replaces its value while keeping position.
    $extraOptions = [ordered] @{}

    foreach ($entry in $Extra) {
        if ($entry -notmatch '^([a-zA-Z][a-zA-Z0-9-]+)(?:=(.+))?$') {
            throw "invalid HandBrakeCLI option: $entry"
        }

        $name = $Matches[1]
        $value = if ($Matches.Count -gt 2) { $Matches[2] } else { $null }

        # These either conflict with what this script generates, or would
        # leave it talking to a HandBrake that is doing something else
        # entirely.
        if ($name -in 'help', 'version', 'json', 'queue-import-file', 'input', 'output' -or
                $name -like 'preset*' -or $name -match '^encoder-[^-]+-list$') {
            throw "unsupported HandBrakeCLI option name: $name"
        }

        if ($null -ne $value -and $name -in $EqualsRequired) {
            $name = "$name=$value"
            $value = $null
        }

        $extraOptions[$name] = $value
    }

    # -Format is sugar for -Extra format=av_<name>, and is implemented by
    # folding it into the same collection rather than as a second path to the
    # same place. Everything downstream - the output extension, the faststart
    # decision - already reads this, and the argv comes out identical.
    if ($PSBoundParameters.ContainsKey('Format')) {
        if ($extraOptions.Contains('format')) {
            throw "use either -Format or -Extra format=..., not both"
        }

        $extraOptions['format'] = "av_$Format"
    }

    function Test-Extra {
        <# Was this option given via -Extra? #>
        param([string[]] $Name)
        foreach ($candidate in $Name) {
            if ($extraOptions.Contains($candidate)) { return $true }
        }
        $false
    }

    # -----------------------------------------------------------------
    # Defaults that depend on other options
    # -----------------------------------------------------------------

    # av1 output pairs with Opus audio: it is better than AAC at these
    # bitrates, and anything that can decode AV1 can certainly decode Opus.
    #
    # An explicit -AudioMode always wins. The Ruby original made this depend
    # on argument order - `-a aac -m av1` produced opus, `-m av1 -a aac`
    # produced aac - which named parameters cannot express.
    $resolvedAudioMode = if ($PSBoundParameters.ContainsKey('AudioMode')) {
        $AudioMode
    } elseif ($Mode -in 'av1', 'nvenc-av1') {
        'opus'
    } else {
        'aac'
    }

    $hasBitrate = $PSBoundParameters.ContainsKey('Bitrate')
    $hasQuality = $PSBoundParameters.ContainsKey('Quality')
    $hasPreset  = $PSBoundParameters.ContainsKey('Preset')

    # Set while building video options, consumed when building --encopts.
    $script:VbvSize = $null

    # -----------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------

    function Format-Quality {
        <#
            Ruby renders a Float with to_s and then strips a trailing ".0",
            so 22.5 stays 22.5 while 51.0 becomes 51. Invariant culture, or a
            comma-decimal locale would emit "22,5" into a comma-separated
            argument list.
        #>
        param([double] $Value)

        $text = $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $text -replace '\.0$', ''
    }

    function Get-Clamped {
        param([double] $Value, [double] $Minimum, [double] $Maximum)
        [Math]::Min([Math]::Max($Value, $Minimum), $Maximum)
    }

    function Select-Requested {
        <#
            Turns one -AddAudio / -AddSubtitle entry into stream matches.

            The entry's shape decides how it is read, exactly as the original
            did: all digits is a track number, three lowercase letters is a
            language (which is why 'all' lands here), anything else is a title
            pattern.
        #>
        param([object] $MediaInfo, [string] $CodecType, [string] $Selector)

        if ($Selector -match '^[0-9]+$') {
            Select-MediaStream $MediaInfo $CodecType -Track ([int] $Selector)
        } elseif ($Selector -match '^[a-z]{3}$') {
            Select-MediaStream $MediaInfo $CodecType -Language $Selector
        } else {
            Select-MediaStream $MediaInfo $CodecType -Title $Selector
        }
    }

    function Get-UniqueStream {
        <# Ruby's uniq! over {index, stream} pairs, preserving order. #>
        param([object[]] $Selection)

        $seen = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($item in $Selection) {
            if ($seen.Add($item.Index)) { $item }
        }
    }

    function Get-CommaSafe {
        <#
            Track names go into --aname and --subname, which are themselves
            comma-separated lists, so a comma inside a name has to be quoted
            the way HandBrake expects.
        #>
        param([string] $Text)
        $Text -replace ',', '","'
    }

    # -----------------------------------------------------------------
    # Option builders
    # -----------------------------------------------------------------

    function Get-VideoOption {
        param([object] $MediaInfo)

        $video = @(Select-MediaStream $MediaInfo video -Track 1)
        if (-not $video) { return @() }
        $video = $video[0].Stream

        $options = [System.Collections.Generic.List[string]]::new()

        # NOTE: these locals must NOT be named $preset / $bitrate / $quality.
        # PowerShell variable names are case-insensitive, so those would be
        # the very same variables as the $Preset, $Bitrate and $Quality
        # parameters, and assigning one would silently overwrite the input.
        $presetArg  = if ($hasPreset) { $Preset } else { $null }
        $bitrateArg = if ($hasBitrate) { "$Bitrate" } else { $null }
        $qualityArg = if ($hasQuality) { Format-Quality $Quality } else { $null }

        if (-not (Test-Extra 'encoder')) {
            $encoder = $null

            if ($hasQuality) {
                $qualityArg = Format-Quality (Get-Clamped $Quality 1.0 51.0)
            }

            switch ($Mode) {
                'h264' {
                    $encoder = 'x264'
                    $width  = [int] $video.width
                    $height = [int] $video.height

                    if ($width -gt 1280 -or $height -gt 720) {
                        $tier = 5000

                        if ($width -gt 1920 -or $height -gt 1080) {
                            $options.AddRange([string[]] @(
                                '--maxWidth', '1920'
                                '--maxHeight', '1080'
                                '--loose-anamorphic'
                            ))

                            # Absent color_space reads as bt709, so an unknown
                            # colour space is left alone rather than converted.
                            $colorSpace = if ($video.PSObject.Properties.Name -contains 'color_space') {
                                "$($video.color_space)"
                            } else {
                                'bt709'
                            }

                            if ($colorSpace -ne 'bt709') {
                                $options.AddRange([string[]] @('--colorspace', 'bt709'))
                            }
                        }
                    } elseif ($width -gt 720 -or $height -gt 576) {
                        $tier = 2500
                    } else {
                        $tier = 1250
                    }

                    # The VBV buffer is three seconds of the target bitrate.
                    $script:VbvSize = $tier * 3

                    if (-not $hasQuality) {
                        if ($hasBitrate) {
                            # A requested bitrate tunes the tier rather than
                            # replacing it: 80% to 160% of the default.
                            $tier = [int] (Get-Clamped $Bitrate `
                                ([Math]::Truncate($tier * 0.8)) ([Math]::Truncate($tier * 1.6)))
                        }
                        $bitrateArg = "$tier"
                        $options.AddRange([string[]] @('--multi-pass', '--turbo'))
                    } else {
                        $bitrateArg = $null
                    }
                }
                'hevc' {
                    $encoder = 'x265_10bit'
                    if (-not $hasBitrate -and -not $qualityArg) { $qualityArg = '24' }
                }
                'nvenc-hevc' {
                    $encoder = 'nvenc_h265_10bit'
                    if (-not $hasBitrate -and -not $qualityArg) { $qualityArg = '30' }
                }
                'av1' {
                    $encoder = 'svt_av1_10bit'

                    if (-not $hasBitrate) {
                        $qualityArg = if ($hasQuality) {
                            "$([int] (Get-Clamped ([Math]::Truncate($Quality)) 0 63))"
                        } else {
                            '30'
                        }
                    }

                    $presetArg = if ($hasPreset) {
                        "$([int] (Get-Clamped ([Math]::Truncate([double] $Preset)) -1 13))"
                    } else {
                        '8'
                    }
                }
                'nvenc-av1' {
                    $encoder = 'nvenc_av1_10bit'

                    if (-not $hasBitrate) {
                        $qualityArg = if ($hasQuality) {
                            "$([int] (Get-Clamped ([Math]::Truncate($Quality)) 0 63))"
                        } else {
                            '37'
                        }
                    }
                }
                default {
                    # 'none' emits no encoder options, and deliberately hands
                    # back the unclamped quality it was given.
                    $qualityArg = if ($hasQuality) { Format-Quality $Quality } else { $null }
                }
            }

            if ($encoder) { $options.AddRange([string[]] @('--encoder', $encoder)) }
        }

        if ($presetArg)  { $options.AddRange([string[]] @('--encoder-preset', $presetArg)) }
        if ($bitrateArg) { $options.AddRange([string[]] @('--vb', $bitrateArg)) }
        if ($qualityArg) { $options.AddRange([string[]] @('--quality', $qualityArg)) }

        if (-not (Test-Extra 'rate', 'vfr', 'cfr', 'pfr')) {
            # Interlaced NTSC MPEG-2 is the one input that must not be given a
            # variable frame rate ceiling; everything else gets 60.
            $frameRate = if ($video.PSObject.Properties.Name -contains 'avg_frame_rate') {
                "$($video.avg_frame_rate)"
            } else {
                ''
            }

            if ("$($video.codec_name)" -eq 'mpeg2video' -and $frameRate -eq '30000/1001') {
                $options.AddRange([string[]] @('--rate', '29.97', '--cfr'))
            } else {
                $options.AddRange([string[]] @('--rate', '60'))
            }
        }

        if (-not (Test-Extra 'crop', 'crop-mode')) {
            $options.AddRange([string[]] @('--crop-mode', 'conservative'))
        }

        $options.ToArray()
    }

    function Get-AudioOption {
        param([object] $MediaInfo)

        if (Test-Extra 'audio', 'all-audio', 'first-audio') { return @() }

        # Track 1 is always selected, then whatever -AddAudio asks for.
        $selections = @(Select-MediaStream $MediaInfo audio -Track 1)
        foreach ($selector in $AddAudio) {
            $selections += @(Select-Requested $MediaInfo audio $selector)
        }

        $tracks = @(Get-UniqueStream $selections)
        if (-not $tracks) { return @() }

        $trackList   = [System.Collections.Generic.List[string]]::new()
        $encoderList = [System.Collections.Generic.List[string]]::new()
        $bitrateList = [System.Collections.Generic.List[string]]::new()
        $mixdownList = [System.Collections.Generic.List[string]]::new()
        $nameList    = [System.Collections.Generic.List[string]]::new()

        $namesWanted = $tracks.Count -ne 1 -and -not (Test-Extra 'aname')

        foreach ($track in $tracks) {
            $trackList.Add("$($track.Index)")

            if (-not (Test-Extra 'aencoder')) {
                $channels = [int] $track.Stream.channels
                $codecName = "$($track.Stream.codec_name)"

                $encoder = ''
                $trackBitrate = ''
                $mixdown = ''

                switch ($resolvedAudioMode) {
                    'aac' {
                        # Already-AAC surround passes through untouched, and so
                        # does AC-3 surround when AC-3 surround was asked for.
                        if (($codecName -eq 'aac' -and $channels -le 6) -or
                                ($Ac3Surround -and $codecName -eq 'ac3' -and $channels -gt 2)) {
                            $encoder = 'copy'
                        } else {
                            $encoder = $AacEncoder

                            switch ($channels) {
                                1 { $trackBitrate = '80';  $mixdown = 'mono' }
                                2 { $trackBitrate = '128'; $mixdown = 'stereo' }
                                default {
                                    if ($Ac3Surround) {
                                        $encoder = 'ac3'
                                        $trackBitrate = '448'
                                    } else {
                                        $trackBitrate = '384'
                                    }
                                    $mixdown = '5point1'
                                }
                            }
                        }
                    }
                    'opus' {
                        if ($codecName -eq 'opus') {
                            $encoder = 'copy'
                        } else {
                            $encoder = 'opus'

                            switch ($channels) {
                                1 { $trackBitrate = '64';  $mixdown = 'mono' }
                                2 { $trackBitrate = '96';  $mixdown = 'stereo' }
                                default { $trackBitrate = '320'; $mixdown = '5point1' }
                            }
                        }
                    }
                    'eac3' {
                        if ($codecName -match 'ac3$' -or ($codecName -eq 'aac' -and $channels -le 6)) {
                            $encoder = 'copy'
                        } else {
                            $encoder = 'eac3'

                            switch ($channels) {
                                1 { $trackBitrate = '96';  $mixdown = 'mono' }
                                2 { $trackBitrate = '192'; $mixdown = 'stereo' }
                                default { $trackBitrate = '448'; $mixdown = '5point1' }
                            }
                        }
                    }
                    default {
                        # 'none' leaves every slot blank, which joins to an
                        # empty string and so emits no option at all.
                    }
                }

                $encoderList.Add($encoder)
                $bitrateList.Add($trackBitrate)
                $mixdownList.Add($mixdown)
            }

            if ($namesWanted) {
                # The first track in the SOURCE is left unnamed.
                $nameList.Add($(if ($track.Index -eq 1) {
                    ''
                } else {
                    Get-CommaSafe (Get-StreamTag $track.Stream 'title')
                }))
            }
        }

        $options = [System.Collections.Generic.List[string]]::new()
        $options.AddRange([string[]] @('--audio', ($trackList -join ',')))

        if (-not (Test-Extra 'aencoder')) {
            $encoderArg = $encoderList -join ','
            if ($encoderArg) { $options.AddRange([string[]] @('--aencoder', $encoderArg)) }

            $bitrateArg = $bitrateList -join ','
            if ($bitrateArg -and -not (Test-Extra 'ab')) {
                $options.AddRange([string[]] @('--ab', $bitrateArg))
            }

            $mixdownArg = $mixdownList -join ','
            if ($mixdownArg -and -not (Test-Extra 'mixdown')) {
                $options.AddRange([string[]] @('--mixdown', $mixdownArg))
            }
        }

        if ($namesWanted) {
            $options.AddRange([string[]] @('--aname', ($nameList -join ',')))
        }

        $options.ToArray()
    }

    function Get-SubtitleOption {
        param([object] $MediaInfo)

        if (Test-Extra 'subtitle', 'all-subtitles', 'first-subtitle') { return @() }

        $options = [System.Collections.Generic.List[string]]::new()

        # -AddSubtitle takes precedence over -BurnSubtitle, in either order.
        # The Ruby original achieved this by clearing the burn request as it
        # parsed, which depended on argument position.
        $burnWanted = -not $AddSubtitle -and $BurnSubtitle -ne 'none'

        if ($burnWanted) {
            $subtitle = if ($BurnSubtitle) {
                @(Select-MediaStream $MediaInfo subtitle -Track ([int] $BurnSubtitle))
            } else {
                @(Select-MediaStream $MediaInfo subtitle -Forced)
            }

            if (-not $subtitle) { return @() }
            $subtitle = $subtitle[0]

            $options.AddRange([string[]] @('--subtitle', "$($subtitle.Index)"))

            # Bitmap subtitles can only be burned in; text ones are carried as
            # a track and flagged to display by default.
            if ("$($subtitle.Stream.codec_name)" -in 'hdmv_pgs_subtitle', 'dvd_subtitle') {
                $options.Add('--subtitle-burned')
            } else {
                $options.Add('--subtitle-default')
            }
        }

        if ($AddSubtitle) {
            # A forced track is always carried, and always first.
            $selections = @(Select-MediaStream $MediaInfo subtitle -Forced)

            foreach ($selector in $AddSubtitle) {
                $selections += @(Select-Requested $MediaInfo subtitle $selector)
            }

            $tracks = @(Get-UniqueStream $selections)
            if (-not $tracks) { return @() }

            $trackList = [System.Collections.Generic.List[string]]::new()
            $nameList  = [System.Collections.Generic.List[string]]::new()
            $default = $null

            $position = 0
            foreach ($track in $tracks) {
                $position++
                $trackList.Add("$($track.Index)")

                if ($null -eq $default -and (Get-StreamDisposition $track.Stream 'forced') -eq 1) {
                    # HandBrakeCLI documents --subtitle-default as "an index
                    # into the subtitle list specified with '--subtitle'", so
                    # this is the POSITION in that list, not the track number.
                    #
                    # The Ruby original passed the absolute track number. On a
                    # disc whose forced subtitle is not track 1 that names the
                    # wrong track, or an index past the end of the list.
                    $default = $position
                }

                if (-not (Test-Extra 'subname')) {
                    $nameList.Add((Get-CommaSafe (Get-StreamTag $track.Stream 'title')))
                }
            }

            $options.Clear()
            $options.AddRange([string[]] @('--subtitle', ($trackList -join ',')))

            if ($null -ne $default) {
                $options.AddRange([string[]] @('--subtitle-default', "$default"))
            }

            if (-not (Test-Extra 'subname')) {
                $options.AddRange([string[]] @('--subname', ($nameList -join ',')))
            }
        }

        $options.ToArray()
    }
}

process {
    foreach ($item in $Path) {
        $started = [datetime]::UtcNow

        # --scan asks HandBrake to report on the file rather than transcode
        # it, so everything this script would normally generate is skipped.
        if (Test-Extra 'scan') {
            $scanArguments = [System.Collections.Generic.List[string]]::new()
            $scanArguments.AddRange([string[]] @('--input', $item))

            foreach ($entry in $extraOptions.GetEnumerator()) {
                $scanArguments.Add("--$($entry.Key)")
                if ($null -ne $entry.Value) { $scanArguments.Add($entry.Value) }
            }

            Invoke-NativeTool 'HandBrakeCLI' $scanArguments.ToArray()
            continue
        }

        $extension = '.mkv'

        # NOT $format. PowerShell variable names are case-insensitive, so that
        # spelling IS the $Format parameter - and its [ValidateSet] stays
        # attached to the variable, rejecting every assignment that is not
        # mkv, mp4 or webm. Writing "av_mp4" there breaks -Extra format=av_mp4
        # outright.
        if ($extraOptions.Contains('format')) {
            $containerName = $extraOptions['format']
            if ($null -ne $containerName) {
                if ($containerName -notin 'av_mkv', 'av_mp4', 'av_webm') {
                    throw "unsupported HandBrakeCLI format: $containerName"
                }
                $extension = '.' + ($containerName -replace '^av_', '')
            }
        }

        $output = [System.IO.Path]::GetFileNameWithoutExtension($item) + $extension
        $mediaInfo = Get-MediaInfo $item

        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.AddRange([string[]] @('--input', $item, '--output', $output))
        $arguments.AddRange([string[]] @(Get-VideoOption $mediaInfo))
        $arguments.AddRange([string[]] @(Get-AudioOption $mediaInfo))
        $arguments.AddRange([string[]] @(Get-SubtitleOption $mediaInfo))

        # MP4 output gets its index moved to the front unless told otherwise.
        # HandBrake's spelling of faststart is --optimize.
        if ($extension -eq '.mp4' -and -not $NoFaststart -and
                -not (Test-Extra 'optimize', 'no-optimize')) {
            $arguments.Add('--optimize')
        }

        # Encoder tuning this script generates, which a user's own --encopts
        # is appended to rather than replacing.
        $encoderOptions = $null

        if (-not (Test-Extra 'encoder')) {
            switch ($Mode) {
                'h264' {
                    $encoderOptions = "vbv-maxrate=$($script:VbvSize):vbv-bufsize=$($script:VbvSize)"
                }
                'nvenc-hevc' {
                    $encoderOptions = 'spatial_aq=1:rc-lookahead=20'
                    if (-not $NoBframeRefs) { $encoderOptions += ':b_ref_mode=2' }
                }
                'nvenc-av1' {
                    # Note the hyphen: this encoder spells it spatial-aq while
                    # the HEVC one spells it spatial_aq.
                    $encoderOptions = 'spatial-aq=1:rc-lookahead=20'
                    if (-not $NoBframeRefs) { $encoderOptions += ':b_ref_mode=2' }
                }
            }
        }

        foreach ($entry in $extraOptions.GetEnumerator()) {
            $arguments.Add("--$($entry.Key)")

            if ($entry.Key -eq 'encopts') {
                if ($null -eq $entry.Value) {
                    throw "invalid HandBrakeCLI option usage: $($entry.Key)"
                }

                $arguments.Add($(if ($null -eq $encoderOptions) {
                    $entry.Value
                } else {
                    "$encoderOptions`:$($entry.Value)"
                }))

                $encoderOptions = $null
            } elseif ($null -ne $entry.Value) {
                $arguments.Add($entry.Value)
            }
        }

        if ($null -ne $encoderOptions) {
            $arguments.AddRange([string[]] @('--encopts', $encoderOptions))
        }

        $handbrakeArguments = $arguments.ToArray()
        $commandLine = Format-CommandLine (@('HandBrakeCLI') + $handbrakeArguments)

        if ($DryRun) {
            $commandLine
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($commandLine, 'Run')) { continue }

        if (Test-Path -LiteralPath $output) {
            throw "output file already exists: $output"
        }

        Write-Verbose 'Command line:'
        Write-Verbose $commandLine
        Write-Verbose 'Transcoding...'

        Invoke-NativeTool 'HandBrakeCLI' $handbrakeArguments

        Write-Verbose ("Elapsed time: " +
            (Format-Elapsed ([int] ([datetime]::UtcNow - $started).TotalSeconds)))
    }
}
