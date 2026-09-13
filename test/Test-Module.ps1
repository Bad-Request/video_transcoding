#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Unit tests for VideoTranscoding.psm1.

.DESCRIPTION
    Covers the shared plumbing: command-line rendering, elapsed-time
    formatting, stream selection and media scanning.

    There are no argument-parsing tests, because there is no argument parser.
    The entry scripts declare real param() blocks and let PowerShell bind
    them, so type conversion, ValidateSet and missing-argument errors are the
    engine's job rather than ours.

    Run with no arguments. Exits non-zero if anything fails.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'VideoTranscoding.psd1') -Force

$script:Pass = 0
$script:Fail = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

function Test-Case {
    param([string] $Name, [scriptblock] $Body)

    try {
        & $Body
        $script:Pass++
    } catch {
        $script:Fail++
        $script:Failures.Add("$Name`n      $($_.Exception.Message)")
        Write-Host ("  {0,-52} FAILED" -f $Name) -ForegroundColor Red
        return
    }
    Write-Host ("  {0,-52} ok" -f $Name) -ForegroundColor DarkGreen
}

function Assert-Equal {
    param([object] $Expected, [object] $Actual, [string] $Because = '')

    $e = if ($Expected -is [array]) { '[' + ($Expected -join ', ') + ']' } else { "$Expected" }
    $a = if ($Actual -is [array]) { '[' + ($Actual -join ', ') + ']' } else { "$Actual" }

    if ($e -cne $a) {
        throw "expected <$e> but got <$a>$(if ($Because) { " ($Because)" })"
    }
}

function Assert-Throws {
    param([scriptblock] $Body, [string] $Matching)

    try {
        & $Body
    } catch {
        if ($_.Exception.Message -notlike $Matching) {
            throw "expected an error like <$Matching> but got <$($_.Exception.Message)>"
        }
        return
    }
    throw "expected an error like <$Matching> but nothing was thrown"
}

Write-Host "`nFormat-CommandLine" -ForegroundColor Cyan

Test-Case 'plain arguments are left bare' {
    Assert-Equal 'HandBrakeCLI --input a.mkv' (Format-CommandLine @('HandBrakeCLI', '--input', 'a.mkv'))
}

Test-Case 'an argument with spaces is quoted' {
    Assert-Equal "--input 'a b.mkv'" (Format-CommandLine @('--input', 'a b.mkv'))
}

Test-Case 'an empty argument becomes two quotes' {
    Assert-Equal "--subname ''" (Format-CommandLine @('--subname', ''))
}

Test-Case 'a single quote is doubled' {
    Assert-Equal "'Director''s Commentary'" (Format-CommandLine @("Director's Commentary"))
}

Test-Case 'a comma is quoted, because PowerShell builds arrays with it' {
    Assert-Equal "'a,b'" (Format-CommandLine @('a,b'))
}

Test-Case 'encoder options keep their colons unquoted' {
    Assert-Equal 'vbv-maxrate=15000:vbv-bufsize=15000' (Format-CommandLine @('vbv-maxrate=15000:vbv-bufsize=15000'))
}

Test-Case 'the rendered line survives a round trip through PowerShell' {
    $original = @('--input', 'a b.mkv', '--subname', '', '--aname', "Deutsch, mit Komma")
    $line = Format-CommandLine $original
    $roundTripped = [System.Management.Automation.Language.Parser]::ParseInput(
        "x $line", [ref] $null, [ref] $null
    ).EndBlock.Statements[0].PipelineElements[0].CommandElements |
        Select-Object -Skip 1 | ForEach-Object { $_.Value ?? $_.Extent.Text }

    Assert-Equal $original @($roundTripped)
}

Write-Host "`nFormat-Elapsed" -ForegroundColor Cyan

Test-Case 'zero' { Assert-Equal '00:00:00' (Format-Elapsed 0) }
Test-Case 'seconds only' { Assert-Equal '00:00:42' (Format-Elapsed 42) }
Test-Case 'minutes and seconds' { Assert-Equal '00:07:05' (Format-Elapsed 425) }
Test-Case 'hours' { Assert-Equal '02:46:40' (Format-Elapsed 10000) }
Test-Case 'hours do not wrap at 24' { Assert-Equal '30:00:00' (Format-Elapsed 108000) }

Write-Host "`nSelect-MediaStream" -ForegroundColor Cyan

$fixture = Get-Content (Join-Path $PSScriptRoot 'fixtures/multitrack.json') -Raw | ConvertFrom-Json
$subs = Get-Content (Join-Path $PSScriptRoot 'fixtures/forced-late.json') -Raw | ConvertFrom-Json

Test-Case 'by track number, 1-based within the codec type' {
    $r = Select-MediaStream $fixture audio -Track 2
    Assert-Equal 1 @($r).Count
    Assert-Equal 2 $r.Index
    Assert-Equal "Director's Commentary" $r.Stream.tags.title
}

Test-Case 'a track number beyond the end selects nothing' {
    Assert-Equal 0 @(Select-MediaStream $fixture audio -Track 9).Count
}

Test-Case 'by language' {
    $r = Select-MediaStream $fixture audio -Language fra
    Assert-Equal 1 @($r).Count
    Assert-Equal 3 $r.Index
}

Test-Case 'language "all" selects every stream of the type' {
    $r = Select-MediaStream $fixture audio -Language all
    Assert-Equal 4 @($r).Count
    Assert-Equal @(1, 2, 3, 4) @($r.Index)
}

Test-Case 'by title, matched case-insensitively as a regex' {
    $r = Select-MediaStream $fixture audio -Title 'commentary'
    Assert-Equal 1 @($r).Count
    Assert-Equal 2 $r.Index
}

Test-Case 'by title, non-ASCII' {
    $r = Select-MediaStream $fixture audio -Title 'Fran'
    Assert-Equal 3 $r.Index
}

Test-Case 'forced finds the forced subtitle and stops' {
    $r = Select-MediaStream $subs subtitle -Forced
    Assert-Equal 1 @($r).Count
    Assert-Equal 3 $r.Index
    Assert-Equal 'Forced French' $r.Stream.tags.title
}

Test-Case 'no forced subtitle selects nothing' {
    $none = Get-Content (Join-Path $PSScriptRoot 'fixtures/mixed-subtitles.json') -Raw | ConvertFrom-Json
    Assert-Equal 0 @(Select-MediaStream $none subtitle -Forced).Count
}

Test-Case 'video streams are indexed separately from audio' {
    $r = Select-MediaStream $fixture video -Track 1
    Assert-Equal 'h264' $r.Stream.codec_name
}

Write-Host "`nGet-MediaInfo" -ForegroundColor Cyan

Test-Case 'a missing file is a scanning failure' {
    $env:VT_FIXTURES = Join-Path $PSScriptRoot 'fixtures'
    $previous = $env:PATH
    $env:PATH = (Join-Path $PSScriptRoot 'shims') + [System.IO.Path]::PathSeparator + $env:PATH
    try {
        Assert-Throws { Get-MediaInfo 'media/does-not-exist.mkv' } 'scanning media failed: *'
    } finally {
        $env:PATH = $previous
    }
}

Test-Case 'a fixture scans into streams' {
    $env:VT_FIXTURES = Join-Path $PSScriptRoot 'fixtures'
    $previous = $env:PATH
    $env:PATH = (Join-Path $PSScriptRoot 'shims') + [System.IO.Path]::PathSeparator + $env:PATH
    try {
        $info = Get-MediaInfo 'media/multitrack.mkv'
        Assert-Equal 5 @($info.streams).Count
    } finally {
        $env:PATH = $previous
    }
}

Write-Host "`nTest-Prerequisite" -ForegroundColor Cyan

Test-Case 'a missing program is named in the error' {
    Assert-Throws { Test-Prerequisite 'definitely-not-a-real-program' } '*definitely-not-a-real-program*'
}

Test-Case 'programs that exist pass' {
    Test-Prerequisite 'ffprobe', 'ffmpeg', 'HandBrakeCLI'
}

Write-Host "`nComment-based help" -ForegroundColor Cyan

# This is a regression guard, and the regression it guards against is silent.
#
# A script whose help block is not separated from its `#!/usr/bin/env pwsh`
# shebang by a blank line gets NO comment-based help at all: PowerShell reads
# the two as one contiguous comment attached to nothing. Get-Help still
# succeeds - it just returns auto-generated syntax instead of the
# documentation, so nothing looks broken until someone reads it.
$scriptRoot = Split-Path $PSScriptRoot -Parent

foreach ($scriptName in 'transcode-video.ps1', 'detect-crop.ps1', 'convert-video.ps1') {
    $scriptPath = Join-Path $scriptRoot $scriptName

    Test-Case "$scriptName has a real synopsis, not generated syntax" {
        $synopsis = (Get-Help $scriptPath).Synopsis

        # The generated fallback is the syntax line, which always starts with
        # the script's own filename.
        if ($synopsis -like "$scriptName*") {
            throw "comment-based help was not found; Get-Help fell back to syntax: $synopsis"
        }
        if (-not $synopsis.Trim()) { throw 'synopsis is empty' }
    }

    Test-Case "$scriptName renders every -Full section" {
        $rendered = Get-Help $scriptPath -Full | Out-String

        foreach ($section in 'SYNOPSIS', 'SYNTAX', 'DESCRIPTION', 'PARAMETERS',
                             'INPUTS', 'OUTPUTS', 'NOTES', 'RELATED LINKS') {
            if ($rendered -notmatch "(?m)^\s*$section\s*$") {
                throw "missing section: $section"
            }
        }
    }

    Test-Case "$scriptName documents every parameter it declares" {
        $declared = (Get-Command $scriptPath).Parameters.Keys |
            Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                           $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters }

        $documented = @((Get-Help $scriptPath -Full).parameters.parameter.name)

        $undocumented = $declared | Where-Object { $_ -notin $documented }
        if ($undocumented) {
            throw "undocumented parameter(s): $($undocumented -join ', ')"
        }
    }

    Test-Case "$scriptName has worked examples" {
        $examples = @((Get-Help $scriptPath -Full).examples.example)
        if ($examples.Count -lt 2) {
            throw "expected at least 2 examples, found $($examples.Count)"
        }
    }
}

Write-Host ''
Write-Host "$script:Pass passed, $script:Fail failed."

if ($script:Failures.Count) {
    Write-Host ''
    Write-Host 'Failures:' -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  $failure" }
}

exit $(if ($script:Fail) { 1 } else { 0 })
