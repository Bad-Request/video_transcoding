#!/usr/bin/env pwsh
<#
    Windows-side implementation of the test shims.

    The POSIX shims next to this file are plain `sh` scripts; Windows-native
    Ruby resolves commands through PATHEXT and so reaches the `.cmd` wrappers,
    which delegate here. pwsh is used rather than batch because the argv being
    recorded carries UTF-8 track titles, commas and `=` signs, all of which
    batch mangles.

    Behaviour must stay identical to the `sh` versions; the golden files are
    what hold the two honest.
#>
# Deliberately NO param() block, and deliberately NOT $args.
#
# Two separate pieces of PowerShell argument handling corrupt the argv this
# shim exists to record faithfully:
#
#   * a param() block would bind ffmpeg's -loglevel as a script parameter;
#   * $args splits -c:v into "-c" and "v", because PowerShell reads
#     -name:value as a parameter with a colon-delimited value. ffmpeg options
#     such as -c:v, -c:a and -c:s:1 are exactly that shape, so every one of
#     them would be recorded as two arguments instead of one.
#
# Reading the process command line directly bypasses both: .NET splits it
# using the same C runtime rules the real tool would have seen.
Set-StrictMode -Version 3.0

$raw = [Environment]::GetCommandLineArgs()
$fileIndex = [Array]::FindIndex($raw, [Predicate[string]] { param($x) $x -eq '-File' })

if ($fileIndex -lt 0 -or ($fileIndex + 2) -ge $raw.Length) {
    [Console]::Error.WriteLine('shim: could not recover arguments from the command line')
    exit 2
}

# Past "-File" and the script path: the tool name, then the tool's own argv.
$Tool = $raw[$fileIndex + 2]
$rest = if (($fileIndex + 3) -lt $raw.Length) {
    $raw[($fileIndex + 3)..($raw.Length - 1)]
} else {
    @()
}

if ($env:VT_ARGV_LOG -and $Tool -ne 'ffprobe') {
    $text = (($rest | ForEach-Object { "$_" }) -join "`n") + "`n"
    [System.IO.File]::AppendAllText($env:VT_ARGV_LOG, $text,
        [System.Text.UTF8Encoding]::new($false))
}

switch ($Tool) {
    'ffprobe' {
        if ($rest.Count -eq 0) { [Console]::Error.WriteLine('ffprobe shim: no arguments'); exit 1 }
        $inputPath = $rest[-1]
        $name = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
        $fixtures = if ($env:VT_FIXTURES) { $env:VT_FIXTURES }
                    else { Join-Path (Split-Path $PSScriptRoot -Parent) 'fixtures' }
        $fixture = Join-Path $fixtures "$name.json"

        if (-not (Test-Path -LiteralPath $fixture)) {
            [Console]::Error.WriteLine("${inputPath}: No such file or directory")
            exit 1
        }
        # Raw passthrough: the fixture is the contract, so no reformatting.
        [Console]::Out.Write([System.IO.File]::ReadAllText($fixture,
            [System.Text.UTF8Encoding]::new($false)))
        exit 0
    }

    'HandBrakeCLI' {
        $crop = if ($env:VT_CROP) { $env:VT_CROP } else { '140/140/0/0' }
        [Console]::Error.WriteLine('[15:04:05] Scanning title 1 of 1...')
        [Console]::Error.WriteLine("  + size: 1920x1080, pixel aspect: 1/1, display aspect: 1.78, crop ($crop): 23.976 fps")
        [Console]::Error.WriteLine('[15:04:05] scan: done. 1 valid title(s)')
        exit 0
    }

    'ffmpeg' {
        if ($env:VT_FAIL) {
            [Console]::Error.WriteLine('ffmpeg shim: failing on request')
            exit ([int]$env:VT_FAIL)
        }
        if ($rest.Count -gt 0 -and $rest[-1] -notmatch '^-') {
            New-Item -ItemType File -Path $rest[-1] -Force | Out-Null
        }
        exit 0
    }
}
