#!/usr/bin/env pwsh

# The blank line above is load-bearing. Without it PowerShell reads the
# shebang and the help block below as one contiguous comment attached to
# nothing, and Get-Help silently falls back to auto-generated syntax.

<#
.SYNOPSIS
    Detect the unused outside area of video tracks.

.DESCRIPTION
    Prints TOP:BOTTOM:LEFT:RIGHT crop values, which can be passed straight to
    transcode-video's -Extra crop=... option.

    Detection works by asking HandBrakeCLI to encode the first second of the
    file and reading the crop it reports while scanning. Nothing is kept: the
    encode goes to a temporary file that is deleted afterwards.

.PARAMETER Path
    One or more media files. Accepts pipeline input, so this works:

        Get-ChildItem *.mkv | ./detect-crop.ps1

.PARAMETER Mode
    HandBrake's crop algorithm. 'conservative' (the default) errs towards
    leaving a few rows of black in rather than clipping picture; 'auto' is
    more aggressive.

.PARAMETER AsObject
    Emit an object per file, with Top, Bottom, Left and Right as integers,
    instead of the TOP:BOTTOM:LEFT:RIGHT string. Use this when the result
    feeds a script rather than a person.

.PARAMETER Version
    Print version information and exit.

.EXAMPLE
    ./detect-crop.ps1 'C:\Rips\Movie.mkv'

    Prints one line, such as 140:140:0:0 - the TOP:BOTTOM:LEFT:RIGHT values
    to pass to transcode-video as -Extra crop=140:140:0:0.

.EXAMPLE
    ./detect-crop.ps1 'C:\Rips\Movie.mkv' -Mode auto

    Use HandBrake's more aggressive algorithm. The default, conservative,
    would rather leave a few rows of black in than clip picture.

.EXAMPLE
    Get-ChildItem 'C:\Rips\*.mkv' | ./detect-crop.ps1

    Detect a whole directory. With more than one file the output becomes CSV,
    so each crop stays attributable to its file.

.EXAMPLE
    Get-ChildItem 'C:\Rips\*.mkv' | ./detect-crop.ps1 -AsObject |
        Where-Object { $_.Top -gt 0 }

    Find which rips are letterboxed. -AsObject emits Top, Bottom, Left and
    Right as integers rather than a string to be parsed.

.INPUTS
    System.String[]

    File paths, by value or by the FullName property.

.OUTPUTS
    System.String

    TOP:BOTTOM:LEFT:RIGHT for a single file; CSV of crop and path for
    several.

    System.Management.Automation.PSCustomObject

    With -AsObject: Path, Top, Bottom, Left, Right and Crop.

.NOTES
    Requires HandBrakeCLI.
.LINK
    transcode-video.ps1

.LINK
    https://github.com/Bad-Request/video_transcoding
#>
[CmdletBinding(DefaultParameterSetName = 'Detect')]
param(
    [Parameter(ParameterSetName = 'Detect', Mandatory, Position = 0,
               ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]] $Path,

    [Parameter(ParameterSetName = 'Detect')]
    [ValidateSet('auto', 'conservative')]
    [string] $Mode = 'conservative',

    [Parameter(ParameterSetName = 'Detect')]
    [switch] $AsObject,

    [Parameter(ParameterSetName = 'Version', Mandatory)]
    [switch] $Version
)

begin {
    Set-StrictMode -Version 3.0
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'VideoTranscoding.psd1')

    if ($Version) {
        Get-VersionText 'detect-crop.ps1'
        exit 0
    }

    Test-Prerequisite 'HandBrakeCLI'

    # Buffered rather than streamed, because the plain-text output format
    # depends on how many files there are in total: a single file prints just
    # its crop, while several print CSV so the values can be told apart.
    $inputs = [System.Collections.Generic.List[string]]::new()
}

process {
    foreach ($item in $Path) { $inputs.Add($item) }
}

end {
    if ($Version) { return }

    foreach ($item in $inputs) {
        $crop = '0:0:0:0'

        # HandBrakeCLI writes its scan output to standard error, so it has to
        # be captured to a file and read back. Merging with 2>&1 would turn
        # each line into an ErrorRecord in the success stream.
        $output = New-TemporaryFile
        $stderr = New-TemporaryFile

        try {
            Invoke-NativeTool 'HandBrakeCLI' @(
                '--input', $item
                '--output', $output.FullName
                '--format', 'av_mkv'
                '--stop-at', 'seconds:1'
                '--crop-mode', $Mode
                '--encoder', 'x265_10bit'
                '--encoder-preset', 'ultrafast'
                '--audio', '0'
            ) -StandardErrorPath $stderr.FullName

            # HandBrake emits invalid byte sequences often enough that the
            # Ruby original guarded every line with valid_encoding?. Decoding
            # as UTF-8 substitutes replacement characters instead of throwing,
            # which has the same effect: the crop line still matches.
            $lines = [System.IO.File]::ReadLines(
                $stderr.FullName, [System.Text.UTF8Encoding]::new($false))

            foreach ($line in $lines) {
                if ($line -match ', crop \((\d+/\d+/\d+/\d+)\): ') {
                    $crop = $Matches[1] -replace '/', ':'
                    break
                }
            }
        } finally {
            Remove-Item $output.FullName, $stderr.FullName -Force -ErrorAction SilentlyContinue
        }

        if ($AsObject) {
            $parts = $crop -split ':'
            [PSCustomObject]@{
                Path   = $item
                Top    = [int] $parts[0]
                Bottom = [int] $parts[1]
                Left   = [int] $parts[2]
                Right  = [int] $parts[3]
                Crop   = $crop
            }
            continue
        }

        if ($inputs.Count -gt 1) {
            # CSV, so a batch of results stays attributable to its file.
            $crop + ',"' + ($item -replace '"', '""') + '"'
        } else {
            $crop
        }
    }
}
