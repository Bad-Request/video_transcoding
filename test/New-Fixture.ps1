#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regenerate the ffprobe JSON fixtures used by the golden-file harness.

.DESCRIPTION
    Builds tiny synthetic media files with ffmpeg, then captures genuine
    `ffprobe -print_format json` output from them into test/fixtures.

    Using real ffprobe output rather than hand-written JSON matters: the
    scripts under test read field names, stream ordering and disposition
    objects exactly as ffprobe emits them, and hand-written fixtures drift
    from that silently.

    Bitmap subtitle streams cannot be produced here at all: ffmpeg has no PGS
    encoder, and it refuses to transcode text subtitles to bitmap ones
    ("Subtitle encoding currently only possible from text to text or bitmap
    to bitmap"). Those streams are therefore DERIVED - captured genuinely as
    text subtitles, then rewritten to the bitmap codec in the JSON.

    Every such rewrite goes through Edit-FixtureSubtitle below, so the set of
    fields that are not straight from ffprobe is listed in one place rather
    than hidden inside a JSON blob.

    The generated media is disposable; only the JSON is committed.

.PARAMETER WorkPath
    Scratch directory for the intermediate media files.
    Defaults to a temporary directory that is removed on completion.

.PARAMETER KeepMedia
    Keep the generated media files instead of deleting them. Useful when you
    want to run a real encode against a fixture rather than just its JSON.

.EXAMPLE
    ./test/New-Fixture.ps1
    Regenerate every fixture.
#>
[CmdletBinding()]
param(
    [string] $WorkPath,
    [switch] $KeepMedia
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Fixture JSON is compared byte-for-byte and read by other platforms; never
# let the host's codepage into it.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$FixturePath = Join-Path $PSScriptRoot 'fixtures'
$null = New-Item -ItemType Directory -Path $FixturePath -Force

if (-not $WorkPath) {
    $WorkPath = Join-Path ([System.IO.Path]::GetTempPath()) "vt-fixture-$(New-Guid)"
}
$null = New-Item -ItemType Directory -Path $WorkPath -Force

function Invoke-Ffmpeg {
    param([string[]] $Arguments)

    Write-Verbose "ffmpeg $($Arguments -join ' ')"
    & ffmpeg -hide_banner -loglevel error -y @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed ($LASTEXITCODE): ffmpeg $($Arguments -join ' ')"
    }
}

function Save-Fixture {
    <#
        Captures ffprobe output for a media file and writes it to
        test/fixtures/<Name>.json, pretty-printed so that a fixture change
        shows up as a readable diff rather than one very long line.
    #>
    param(
        [string] $Name,
        [string] $MediaPath
    )

    $json = & ffprobe -loglevel quiet -show_streams -show_format -print_format json $MediaPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed ($LASTEXITCODE) on $MediaPath"
    }

    $parsed = $json -join "`n" | ConvertFrom-Json

    # ffprobe records the absolute path it was given, which here is a
    # throwaway temp directory with a fresh GUID in it. Left alone, every
    # regeneration would rewrite all eight fixtures with nothing but a new
    # scratch path - churn that hides any real change. Normalise it to the
    # name the harness actually passes. Nothing under test reads this field.
    if ($parsed.PSObject.Properties.Name -contains 'format') {
        $parsed.format.filename = "media/$Name" + [System.IO.Path]::GetExtension($MediaPath)
    }

    $text = ($parsed | ConvertTo-Json -Depth 12)
    $target = Join-Path $FixturePath "$Name.json"

    # LF, no BOM, trailing newline - matches the .gitattributes -text rule.
    [System.IO.File]::WriteAllText($target, ($text -replace "`r`n", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))

    $streams = ($text | ConvertFrom-Json).streams
    Write-Host ("  {0,-26} {1} streams" -f $Name, $streams.Count)
}

function Edit-FixtureSubtitle {
    <#
        Rewrites the codec of one subtitle stream in an existing fixture,
        optionally writing the result out under a new name.

        This exists solely because ffmpeg cannot produce bitmap subtitles
        from text ones. Everything else in every fixture is verbatim ffprobe
        output.
    #>
    param(
        [Parameter(Mandatory)] [string] $From,
        [string] $To,
        [Parameter(Mandatory)] [int]    $SubtitleIndex,
        [Parameter(Mandatory)] [ValidateSet('hdmv_pgs_subtitle', 'dvd_subtitle')]
        [string] $Codec
    )

    $longName = @{
        'hdmv_pgs_subtitle' = 'HDMV Presentation Graphic Stream subtitles'
        'dvd_subtitle'      = 'DVD subtitles'
    }[$Codec]

    $fixture = Get-Content (Join-Path $FixturePath "$From.json") -Raw | ConvertFrom-Json

    $nth = 0
    foreach ($stream in $fixture.streams) {
        if ($stream.codec_type -ne 'subtitle') { continue }

        if ($nth -eq $SubtitleIndex) {
            $stream.codec_name      = $Codec
            $stream.codec_long_name = $longName
            break
        }
        $nth++
    }

    if (-not $To) { $To = $From }

    $text = ($fixture | ConvertTo-Json -Depth 12) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText(
        (Join-Path $FixturePath "$To.json"),
        $text + "`n",
        [System.Text.UTF8Encoding]::new($false))

    Write-Host ("  {0,-26} subtitle #{1} -> {2}{3}" -f $To, $SubtitleIndex, $Codec,
        $(if ($To -ne $From) { " (derived from $From)" } else { '' }))
}

Write-Host 'Generating fixtures...'

#region 1080p Blu-ray with a forced subtitle
# Exercises: default h264 path (5000 Kbps tier), 5.1 -> AAC transcode, and
# automatic forced-subtitle detection resolving to --subtitle-default,
# because a TEXT subtitle is included rather than burned.
$media = Join-Path $WorkPath 'bluray-1080p-forced.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=24000/1001:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-f', 'srt',   '-i', (New-Item -ItemType File -Force -Path (Join-Path $WorkPath 'forced.srt') -Value "1`n00:00:00,100 --> 00:00:00,900`nForced line`n`n").FullName
    '-map', '0:v', '-map', '1:a', '-map', '2:s'
    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709'
    '-c:a', 'ac3', '-ac', '6', '-b:a', '448k'
    '-c:s', 'srt'
    '-metadata:s:a:0', 'language=eng'
    '-metadata:s:a:0', 'title=Surround'
    '-metadata:s:s:0', 'language=eng'
    '-disposition:s:0', 'forced'
    $media
)
Save-Fixture -Name 'bluray-1080p-forced' -MediaPath $media
#endregion

#region 4K HDR
# Exercises: the only path that emits --maxWidth/--maxHeight/--loose-anamorphic,
# and the --colorspace bt709 conversion triggered by a non-bt709 source.
$media = Join-Path $WorkPath 'uhd-hdr.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=3840x2160:rate=24:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-map', '0:v', '-map', '1:a'
    '-c:v', 'libx265', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p10le'
    '-color_primaries', 'bt2020', '-color_trc', 'smpte2084', '-colorspace', 'bt2020nc'
    '-c:a', 'eac3', '-ac', '6', '-b:a', '448k'
    '-metadata:s:a:0', 'language=eng'
    $media
)
Save-Fixture -Name 'uhd-hdr' -MediaPath $media
#endregion

#region NTSC DVD
# Exercises: the ONLY path that emits `--rate 29.97 --cfr`, which requires
# codec_name mpeg2video AND avg_frame_rate exactly 30000/1001.
# Also the 1250 Kbps tier.
$media = Join-Path $WorkPath 'dvd-ntsc.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=720x480:rate=30000/1001:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-map', '0:v', '-map', '1:a'
    '-c:v', 'mpeg2video', '-r', '30000/1001', '-pix_fmt', 'yuv420p'
    '-c:a', 'ac3', '-ac', '2', '-b:a', '192k'
    '-metadata:s:a:0', 'language=eng'
    $media
)
Save-Fixture -Name 'dvd-ntsc' -MediaPath $media
#endregion

#region Multi-track disc
# Exercises: --add-audio by track / language / title, --aname list building,
# the gsub(/,/, '","') quoting of a title containing a comma, and non-ASCII
# titles flowing through to the command line.
$media = Join-Path $WorkPath 'multitrack.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=24:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-map', '0:v'
    '-map', '1:a', '-map', '1:a', '-map', '1:a', '-map', '1:a'
    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'
    '-c:a:0', 'ac3',  '-ac:a:0', '6', '-b:a:0', '448k'
    '-c:a:1', 'aac',  '-ac:a:1', '2', '-b:a:1', '128k'
    '-c:a:2', 'ac3',  '-ac:a:2', '6', '-b:a:2', '448k'
    '-c:a:3', 'aac',  '-ac:a:3', '2', '-b:a:3', '128k'
    '-metadata:s:a:0', 'language=eng', '-metadata:s:a:0', 'title=Surround'
    '-metadata:s:a:1', 'language=eng', '-metadata:s:a:1', "title=Director's Commentary"
    '-metadata:s:a:2', 'language=fra', '-metadata:s:a:2', 'title=Français 5.1'
    '-metadata:s:a:3', 'language=deu', '-metadata:s:a:3', 'title=Deutsch, mit Komma'
    $media
)
Save-Fixture -Name 'multitrack' -MediaPath $media
#endregion

#region Mixed subtitles, 720p
# Exercises: the 2500 Kbps tier, and - critically - convert-video's subtitle
# mapping. Stream order is deliberate: an ASS track that convert-video drops
# comes BEFORE a subrip track that it maps, which is precisely the shape that
# triggers the -c:s off-by-N defect.
$srt = (New-Item -ItemType File -Force -Path (Join-Path $WorkPath 'plain.srt') -Value "1`n00:00:00,100 --> 00:00:00,900`nPlain line`n`n").FullName
$media = Join-Path $WorkPath 'mixed-subtitles.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=1280x720:rate=24:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-f', 'srt', '-i', $srt
    '-f', 'srt', '-i', $srt
    '-f', 'srt', '-i', $srt
    '-map', '0:v', '-map', '1:a', '-map', '2:s', '-map', '3:s', '-map', '4:s'
    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'
    '-c:a', 'aac', '-ac', '2', '-b:a', '128k'
    '-c:s:0', 'ass'      # dropped by convert-video
    '-c:s:1', 'srt'      # mapped as mov_text  <- bug lands here
    '-c:s:2', 'srt'      # derived to dvd_subtitle below; mapped as copy
    '-metadata:s:a:0', 'language=eng'
    '-metadata:s:s:0', 'language=eng', '-metadata:s:s:0', 'title=Signs'
    '-metadata:s:s:1', 'language=eng', '-metadata:s:s:1', 'title=Full'
    '-metadata:s:s:2', 'language=fra', '-metadata:s:s:2', 'title=Français'
    $media
)
Save-Fixture -Name 'mixed-subtitles' -MediaPath $media
#endregion

#region Forced subtitle that is not the first subtitle
# Exercises the one question a single-subtitle fixture cannot answer: whether
# --subtitle-default is given an ABSOLUTE track number or an index into the
# list passed to --subtitle. The two are only distinguishable when the forced
# track is not track 1, because get_subtitle_options always places the forced
# track first in the selection.
$srt = (New-Item -ItemType File -Force -Path (Join-Path $WorkPath 'late.srt') -Value "1`n00:00:00,100 --> 00:00:00,900`nLate line`n`n").FullName
$media = Join-Path $WorkPath 'forced-late.mkv'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=24:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-f', 'srt', '-i', $srt
    '-f', 'srt', '-i', $srt
    '-f', 'srt', '-i', $srt
    '-map', '0:v', '-map', '1:a', '-map', '2:s', '-map', '3:s', '-map', '4:s'
    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'
    '-c:a', 'ac3', '-ac', '6', '-b:a', '448k'
    '-c:s', 'srt'
    '-metadata:s:a:0', 'language=eng'
    '-metadata:s:s:0', 'language=eng', '-metadata:s:s:0', 'title=Full'
    '-metadata:s:s:1', 'language=deu', '-metadata:s:s:1', 'title=Deutsch'
    '-metadata:s:s:2', 'language=fra', '-metadata:s:s:2', 'title=Forced French'
    '-disposition:s:2', 'forced'      # the THIRD subtitle is the forced one
    $media
)
Save-Fixture -Name 'forced-late' -MediaPath $media
#endregion

#region MP4 source
# Exercises convert-video's OTHER branch. Every other fixture reports
# format_name "matroska,webm" and so takes the MKV->MP4 path; without an MP4
# source the "other media to Matroska" half of the tool is never reached.
$media = Join-Path $WorkPath 'mp4-source.mp4'
Invoke-Ffmpeg @(
    '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=24:duration=1'
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1:sample_rate=48000'
    '-map', '0:v', '-map', '1:a'
    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'
    '-c:a', 'aac', '-ac', '2', '-b:a', '128k'
    '-metadata:s:a:0', 'language=eng'
    $media
)
Save-Fixture -Name 'mp4-source' -MediaPath $media
#endregion

#region Bitmap subtitle derivations
# The only hand-edited data in the fixture set. See Edit-FixtureSubtitle.
Write-Host 'Deriving bitmap subtitle variants...'

# A forced PGS track is what an actual Blu-ray rip looks like, and it is the
# only thing that reaches transcode-video's --subtitle-burned branch.
Edit-FixtureSubtitle -From 'bluray-1080p-forced' -To 'bluray-1080p-pgs' `
    -SubtitleIndex 0 -Codec 'hdmv_pgs_subtitle'

# convert-video copies dvd_subtitle through to MP4 unchanged; without a real
# one, the -c:s ordinal defect cannot be observed end to end.
Edit-FixtureSubtitle -From 'mixed-subtitles' `
    -SubtitleIndex 2 -Codec 'dvd_subtitle'
#endregion

if ($KeepMedia) {
    Write-Host "`nMedia kept in: $WorkPath"
} else {
    Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nFixtures written to $FixturePath"
