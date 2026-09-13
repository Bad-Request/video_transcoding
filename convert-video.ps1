#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Convert a media file between Matroska and MP4 without transcoding.

.DESCRIPTION
    Matroska input becomes MP4; anything else becomes Matroska. Every video
    and audio track is copied as-is, so this is a remux rather than a
    re-encode and takes seconds rather than hours.

    Subtitles are the exception, because MP4 supports far fewer formats than
    Matroska does. DVD bitmap subtitles are copied, SubRip text subtitles are
    converted to MP4 timed text, and anything else is dropped with a warning.

.PARAMETER Path
    One or more media files. Accepts pipeline input, so this works:

        Get-ChildItem *.mkv | ./convert-video.ps1

.PARAMETER NoFaststart
    Leave the MP4 index where ffmpeg puts it by default, at the end of the
    file, instead of moving it to the front.

    Moving it is the default because a file whose index is at the front can
    start playing before it has fully downloaded. The cost is that ffmpeg
    makes a second pass over the finished file to do it, which on a large
    remux means rewriting every byte again. Use this switch when you are
    converting a big archive locally and nothing will ever stream it.

    Has no effect when the output is Matroska, which has no such index.

.PARAMETER DryRun
    Print the ffmpeg command that would run, and stop. Equivalent to -WhatIf.

.PARAMETER Version
    Print version information and exit.

.EXAMPLE
    ./convert-video.ps1 'C:\Rips\Movie.mkv'
    Produces Movie.mp4 in the current directory.

.EXAMPLE
    ./convert-video.ps1 'C:\Rips\Movie.mkv' -WhatIf
    Show the ffmpeg command without running it.

.NOTES
    Requires ffmpeg and ffprobe.
#>
[CmdletBinding(DefaultParameterSetName = 'Convert', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Convert', Mandatory, Position = 0,
               ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]] $Path,

    [Parameter(ParameterSetName = 'Convert')]
    [switch] $NoFaststart,

    [Parameter(ParameterSetName = 'Convert')]
    [switch] $DryRun,

    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch] $Version
)

begin {
    Set-StrictMode -Version 3.0
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'VideoTranscoding.psd1')

    if ($Version) {
        Get-VersionText 'convert-video.ps1'
        exit 0
    }

    Test-Prerequisite 'ffmpeg', 'ffprobe'
}

process {
    foreach ($item in $Path) {
        $started = [datetime]::UtcNow
        $mediaInfo = Get-MediaInfo $item

        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.AddRange([string[]] @('-c:v', 'copy', '-c:a', 'copy'))

        if ($mediaInfo.format.format_name -match 'matroska') {
            $extension = '.mp4'

            # Two separate counters, and the distinction is the whole point.
            #
            # inputSubtitle numbers the subtitle tracks coming in, and is what
            # a warning should name. outputSubtitle numbers the ones that
            # actually get mapped, and is what ffmpeg's -c:s:N refers to.
            #
            # The Ruby original used one counter for both, advancing it even
            # for tracks it dropped. Any file with an unsupported subtitle
            # ahead of a supported one therefore got a -c:s:N pointing at the
            # wrong output stream, or at no stream at all.
            $inputSubtitle = 0
            $outputSubtitle = 0

            foreach ($stream in $mediaInfo.streams) {
                $mapStream = $false
                $codecName = $null

                switch ($stream.codec_type) {
                    { $_ -in 'video', 'audio' } {
                        $mapStream = $true
                    }
                    'subtitle' {
                        $inputSubtitle++

                        switch ($stream.codec_name) {
                            'dvd_subtitle' { $mapStream = $true; $codecName = 'copy' }
                            'subrip'       { $mapStream = $true; $codecName = 'mov_text' }
                            default {
                                Write-Warning "Ignoring subtitle track #$inputSubtitle ($($stream.codec_name))"
                            }
                        }
                    }
                }

                if ($mapStream) {
                    $arguments.AddRange([string[]] @('-map', "0:$($stream.index)"))
                }

                if ($codecName) {
                    $arguments.AddRange([string[]] @("-c:s:$outputSubtitle", $codecName))
                    $outputSubtitle++
                }
            }

            # disable_chpl suppresses the Nero chapter atom, which some
            # players choke on. faststart moves the index to the front.
            # The leading + adds to the flag set rather than replacing it.
            # -NoFaststart emits the bare flag rather than '+disable_chpl' so
            # that it reproduces the previous behaviour exactly. The two are
            # equivalent to ffmpeg, but byte-identical output lets the harness
            # assert that this switch changes one thing and nothing else.
            $movFlags = if ($NoFaststart) { 'disable_chpl' } else { '+faststart+disable_chpl' }
            $arguments.AddRange([string[]] @('-movflags', $movFlags))
        } else {
            # Matroska carries essentially any subtitle format, so nothing
            # needs converting or dropping, and there is no index to move.
            $extension = '.mkv'
            $arguments.AddRange([string[]] @('-c:s', 'copy'))
        }

        $output = [System.IO.Path]::GetFileNameWithoutExtension($item) + $extension

        $ffmpegArguments = @(
            '-loglevel', ($DebugPreference -ne 'SilentlyContinue' ? 'verbose' : 'error')
            '-stats'
            '-i', $item
        ) + $arguments + @($output)

        $commandLine = Format-CommandLine (@('ffmpeg') + $ffmpegArguments)

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
        Write-Verbose 'Converting...'

        Invoke-NativeTool 'ffmpeg' $ffmpegArguments

        Write-Verbose ("Elapsed time: " +
            (Format-Elapsed ([int] ([datetime]::UtcNow - $started).TotalSeconds)))
    }
}
