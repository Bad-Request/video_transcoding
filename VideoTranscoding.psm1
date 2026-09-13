#
# VideoTranscoding.psm1
#
# Shared plumbing for the video transcoding tools.
#
# In the Ruby originals this layer was copy-pasted: escape_command,
# escape_string and seconds_to_time were 29 byte-identical lines across two
# scripts, scan_media another 14, and the rescue-and-exit boilerplate was
# identical across all three.
#

Set-StrictMode -Version 3.0

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Native command output is decoded using [Console]::OutputEncoding, which is
# UTF-8 on Linux and macOS but an OEM codepage on a default Windows host.
# Blu-ray track titles are full of non-ASCII (Français, Deutsch) and flow
# straight into --aname, so pin this rather than inherit whatever the host has.
try {
    if ([Console]::OutputEncoding.CodePage -ne 65001) {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    }
} catch {
    # A redirected or absent console cannot have its encoding set. Decoding
    # then follows the default, which is UTF-8 everywhere that matters.
}

# 'Windows' mode falls back to legacy quoting for a handful of executables.
# HandBrakeCLI and ffmpeg are not among them, so this changes no behaviour -
# it removes a platform difference from the things that have to be reasoned
# about when an argument comes out wrong.
$PSNativeCommandArgumentPassing = 'Standard'

$script:ModuleVersion = '0.1.0'

# ---------------------------------------------------------------------------
# Media scanning
# ---------------------------------------------------------------------------

function Get-MediaInfo {
    <#
    .SYNOPSIS
        Scan a media file with ffprobe and return its streams and format.

    .DESCRIPTION
        Replaces the scan_media function that appeared identically in both
        transcode-video.rb and convert-video.rb.

        The two failure modes are kept distinct, as in the original: a
        non-zero exit from ffprobe is a scanning failure, while output that
        will not parse as JSON is missing media information. They mean
        different things when diagnosing a bad rip.

    .PARAMETER Path
        The media file to scan. Passed to ffprobe unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    Write-Verbose "Scanning media: $Path"

    $json = & ffprobe -loglevel quiet -show_streams -show_format -print_format json $Path

    if ($LASTEXITCODE -ne 0) {
        throw "scanning media failed: $Path"
    }

    try {
        $mediaInfo = ($json -join "`n") | ConvertFrom-Json
    } catch {
        throw "media information not found: $Path"
    }

    # An ffprobe run that succeeds on a non-media file still emits valid JSON,
    # just without streams. Everything downstream assumes the property exists.
    if (-not ($mediaInfo.PSObject.Properties.Name -contains 'streams')) {
        throw "media information not found: $Path"
    }

    $mediaInfo
}

function Select-MediaStream {
    <#
    .SYNOPSIS
        Select streams of one codec type by track number, language or title.

    .DESCRIPTION
        Replaces six near-identical loops in transcode-video.rb - three in
        get_audio_options and three in get_subtitle_options - which between
        them accounted for roughly 120 of that file's lines.

        Indexes are 1-based WITHIN the codec type, matching how HandBrakeCLI
        numbers tracks, not ffprobe's absolute stream index.

        Exactly one selector is used per call. That mirrors the original,
        where a selection is a track, a language or a title but never a
        combination.

    .PARAMETER MediaInfo
        The object returned by Get-MediaInfo.

    .PARAMETER CodecType
        'audio', 'subtitle' or 'video'.

    .PARAMETER Track
        1-based index within the codec type. Selects at most one stream.

    .PARAMETER Language
        A three-letter language tag, or 'all' to select every stream of the
        type. 'all' is handled here because the original's argument pattern
        for a language, /^[a-z]{3}$/, matches it.

    .PARAMETER Title
        A regular expression matched case-insensitively against the stream's
        title tag.

    .PARAMETER Forced
        Select only streams flagged forced. Used to find the subtitle that
        should be burned or defaulted.

    .OUTPUTS
        Objects with Index (1-based, within type) and Stream properties, in
        stream order.
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object] $MediaInfo,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('audio', 'subtitle', 'video')]
        [string] $CodecType,

        [Parameter(Mandatory, ParameterSetName = 'Track')]
        [int] $Track,

        [Parameter(Mandatory, ParameterSetName = 'Language')]
        [string] $Language,

        [Parameter(Mandatory, ParameterSetName = 'Title')]
        [string] $Title,

        [Parameter(Mandatory, ParameterSetName = 'Forced')]
        [switch] $Forced
    )

    $index = 0

    foreach ($stream in $MediaInfo.streams) {
        if ($stream.codec_type -ne $CodecType) { continue }

        $index++

        $matched = switch ($PSCmdlet.ParameterSetName) {
            'Track' {
                $index -eq $Track
            }
            'Language' {
                $Language -eq 'all' -or (Get-StreamTag $stream 'language') -eq $Language
            }
            'Title' {
                (Get-StreamTag $stream 'title') -imatch $Title
            }
            'Forced' {
                (Get-StreamDisposition $stream 'forced') -eq 1
            }
            default {
                $true
            }
        }

        if (-not $matched) { continue }

        [PSCustomObject]@{
            Index  = $index
            Stream = $stream
        }

        # A track number and a forced search both resolve to a single stream;
        # the original breaks out of the loop for exactly these two.
        if ($PSCmdlet.ParameterSetName -in 'Track', 'Forced') { break }
    }
}

function Get-StreamTag {
    <#
        The equivalent of Ruby's stream.fetch('tags', {}).fetch(name, '').
        Streams frequently carry no tags object at all, and a missing tag must
        read as an empty string rather than $null so that comparisons and
        regex matches behave.
    #>
    param([object] $Stream, [string] $Name)

    if (-not ($Stream.PSObject.Properties.Name -contains 'tags')) { return '' }
    if ($null -eq $Stream.tags) { return '' }
    if (-not ($Stream.tags.PSObject.Properties.Name -contains $Name)) { return '' }

    "$($Stream.tags.$Name)"
}

function Get-StreamDisposition {
    param([object] $Stream, [string] $Name)

    if (-not ($Stream.PSObject.Properties.Name -contains 'disposition')) { return 0 }
    if ($null -eq $Stream.disposition) { return 0 }
    if (-not ($Stream.disposition.PSObject.Properties.Name -contains $Name)) { return 0 }

    [int] $Stream.disposition.$Name
}

# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

function Format-CommandLine {
    <#
    .SYNOPSIS
        Render an argument vector as a command line that can be pasted back
        into PowerShell.

    .DESCRIPTION
        The Ruby original emitted cmd.exe-style quoting on Windows and POSIX
        shell quoting elsewhere, so on Windows the line it printed for
        --dry-run was not valid in the shell the user was standing in. This
        emits PowerShell quoting on every platform, which is the shell the
        tools now run in.

        Single quotes are used because PowerShell does not expand anything
        inside them, so a title containing $ or ` survives intact.

    .PARAMETER Argument
        The argument vector, including the program name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Argument
    )

    ($Argument | ForEach-Object {
        if ($_ -eq '') {
            "''"
        } elseif ($_ -match "[\s'`"``$;,|&<>(){}\[\]@#]") {
            "'" + ($_ -replace "'", "''") + "'"
        } else {
            $_
        }
    }) -join ' '
}

function Format-Elapsed {
    <#
    .SYNOPSIS
        Render a duration in seconds as HH:MM:SS.

    .PARAMETER Second
        Elapsed whole seconds. Hours are not wrapped at 24.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int] $Second
    )

    '{0:d2}:{1:d2}:{2:d2}' -f @(
        [int] [Math]::Floor($Second / 3600)
        [int] (([Math]::Floor($Second / 60)) % 60)
        [int] ($Second % 60)
    )
}

function Get-VersionText {
    <#
    .SYNOPSIS
        The standard two-line version block, identical in shape across all
        three tools.

    .PARAMETER ToolName
        The tool's own name, as it should appear to the user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $ToolName
    )

    "$ToolName $script:ModuleVersion`nCopyright (c) 2026. MIT licensed."
}

# ---------------------------------------------------------------------------
# Running native tools
# ---------------------------------------------------------------------------

function Test-Prerequisite {
    <#
    .SYNOPSIS
        Check that the external programs a tool needs are on PATH.

    .DESCRIPTION
        The Ruby originals let a missing program surface as a raw
        Errno::ENOENT from deep inside a spawn call. Checking up front means
        the error names the program and the fix.

    .PARAMETER Name
        Program names to look for. Get-Command resolves the .exe on Windows
        and the bare name elsewhere.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]] $Name
    )

    $missing = $Name | Where-Object { -not (Get-Command $_ -CommandType Application -ErrorAction Ignore) }

    if ($missing) {
        throw ("required program not found on PATH: {0}" -f ($missing -join ', '))
    }
}

function Invoke-NativeTool {
    <#
    .SYNOPSIS
        Run an external program with an argument vector, optionally capturing
        its standard error.

    .PARAMETER FilePath
        The program to run.

    .PARAMETER Argument
        Its arguments, as a vector. Never a pre-joined string: building a
        command line by hand is what makes quoting a problem in the first
        place.

    .PARAMETER StandardErrorPath
        Capture standard error to this file instead of letting it through.
        Used by detect-crop, which parses HandBrake's scan output.

        Note that 2>&1 is deliberately not used: it turns stderr into
        ErrorRecords in the success stream, which then have to be picked back
        apart.

    .PARAMETER PassThru
        Return the exit code rather than throwing on a non-zero one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $FilePath,

        [Parameter(Position = 1)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Argument = @(),

        [string] $StandardErrorPath,

        [switch] $PassThru
    )

    Write-Verbose ("Running: " + (Format-CommandLine (@($FilePath) + $Argument)))

    if ($StandardErrorPath) {
        & $FilePath @Argument 2>$StandardErrorPath
    } else {
        & $FilePath @Argument
    }

    $exitCode = $LASTEXITCODE

    if ($PassThru) { return $exitCode }

    if ($exitCode -ne 0) {
        throw "$FilePath failed with exit code $exitCode"
    }
}

Export-ModuleMember -Function @(
    'Get-MediaInfo'
    'Select-MediaStream'
    'Get-StreamTag'
    'Get-StreamDisposition'
    'Format-CommandLine'
    'Format-Elapsed'
    'Invoke-NativeTool'
    'Test-Prerequisite'
    'Get-VersionText'
)
