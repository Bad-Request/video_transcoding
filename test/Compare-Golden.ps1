#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Run the sweep matrix against an implementation and compare the emitted
    command lines to the golden files.

.DESCRIPTION
    The scripts in this project are pure functions in disguise: ffprobe JSON
    plus options in, one argument vector out. This harness pins that function
    down so the PowerShell port can be verified without running a single
    encode.

    Fake ffprobe, ffmpeg and HandBrakeCLI are placed ahead of the real ones on
    PATH, so a run touches no media and produces identical output on every
    machine.

    What is recorded is the ARGV the tool under test hands to HandBrakeCLI or
    ffmpeg - one argument per line, captured by the shim - plus anything the
    tool printed to stdout. Deliberately not the escaped command line that
    --dry-run prints: Ruby escapes differently on Windows than on POSIX
    (escape_string branches on RUBY_PLATFORM), and the port changes the
    quoting style on purpose, so goldening that string would compare
    presentation rather than behaviour and would diverge on every case.

    Each case runs in its own temporary working directory, because the tools
    refuse to overwrite an existing output file and the ffmpeg shim creates
    one.

    Cases marked `Diverges` in cases.psd1 are expected to differ between the
    two implementations - the port deliberately fixes a defect or changes a
    default there. Their goldens live in golden/divergent; everything else
    lives in golden/parity.

.PARAMETER Implementation
    Which implementation to run: `ruby` (the reference implementation in
    legacy/) or `powershell` (the port).

.PARAMETER Update
    Write the emitted output to the golden files instead of comparing.
    Use this once, against `ruby`, to establish the baseline.

.PARAMETER Name
    Run only cases whose name matches this wildcard pattern.

.PARAMETER RubyCommand
    How to invoke Ruby. Defaults to `ruby` on PATH. Point this at a portable
    or containerised interpreter if Ruby is not installed system-wide.

.EXAMPLE
    ./test/Compare-Golden.ps1 -Implementation ruby -Update
    Establish the baseline from the reference implementation.

.EXAMPLE
    ./test/Compare-Golden.ps1 -Implementation powershell
    Check the port against it.

.EXAMPLE
    ./test/Compare-Golden.ps1 -Implementation powershell -Name 'audio-*'
    Check one group while working on it.
#>
[CmdletBinding()]
param(
    [ValidateSet('ruby', 'powershell')]
    [string] $Implementation = 'powershell',

    [switch] $Update,

    [string] $Name = '*',

    [string] $RubyCommand = 'ruby'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Goldens are compared byte-for-byte and carry non-ASCII track titles; never
# let the host's codepage decide how a child process's output is decoded.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$TestRoot = $PSScriptRoot
$RepoRoot = Split-Path $TestRoot -Parent

$cases = Import-PowerShellDataFile (Join-Path $TestRoot 'cases.psd1')

# Shims first, so the tools under test reach the fakes rather than the real
# binaries. VT_FIXTURES tells the ffprobe shim where to look.
$env:PATH = (Join-Path $TestRoot 'shims') + [System.IO.Path]::PathSeparator + $env:PATH
$env:VT_FIXTURES = Join-Path $TestRoot 'fixtures'

function Get-ToolInvocation {
    <#
        Maps a tool name to the command that runs it under the chosen
        implementation.
    #>
    param([string] $Tool)

    if ($Implementation -eq 'ruby') {
        $script = Join-Path $RepoRoot "legacy/$Tool.rb"
        if (-not (Test-Path -LiteralPath $script)) {
            throw "reference implementation not found: $script"
        }
        return @{ Command = $RubyCommand; Leading = @($script) }
    }

    $script = Join-Path $RepoRoot "$Tool.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        throw "port not found: $script (not written yet?)"
    }
    return @{ Command = 'pwsh'; Leading = @('-NoProfile', '-NonInteractive', '-File', $script) }
}

function ConvertTo-StableArgv {
    <#
        Replaces machine- and run-specific paths with placeholders so the
        record is reproducible.

        detect-crop passes HandBrakeCLI a Tempfile path, which carries a
        timestamp, a pid and a random suffix and is therefore different on
        every single run. What matters for the golden is that a temporary
        output path was passed at all, not what it was called.
    #>
    param([string] $Argv)

    if (-not $Argv) { return $Argv }

    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')

    # Compare with both separators and case-insensitively: Ruby normalises
    # Windows paths to forward slashes, and the temp path's case is not
    # guaranteed to match what the OS reports.
    # The inner -replace must be parenthesised, or its comma is read as a
    # method argument separator and Escape() is called with two arguments.
    $patterns = @(
        [regex]::Escape($temp)
        [regex]::Escape(($temp -replace '\\', '/'))
    ) | Sort-Object -Unique

    $lines = $Argv -split "`n" | ForEach-Object {
        $line = $_
        foreach ($pattern in $patterns) {
            if ($line -imatch "^$pattern[\\/]") { return '<TEMPFILE>' }
        }
        $line
    }

    return ($lines -join "`n")
}

function Invoke-Case {
    <#
        Runs one case in an isolated working directory and returns a
        normalised record of what it did: the argv it handed to the native
        tool, and anything it printed to stdout.
    #>
    param([string] $CaseName, [hashtable] $Case)

    $invocation = Get-ToolInvocation -Tool $Case.Tool

    $arguments = @($invocation.Leading) + $Case.Arguments

    # A relative, forward-slashed input path. It never has to exist - the
    # ffprobe shim resolves the fixture from its basename - and keeping it
    # relative means the recorded argv is identical whether Ruby ran on
    # Windows, on Linux, or under WSL against /mnt/d.
    $arguments += "media/$($Case.Fixture).mkv"

    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "vt-case-$(New-Guid)"
    $null = New-Item -ItemType Directory -Path $sandbox -Force

    $argvLog = Join-Path $sandbox '_argv.log'
    $stderrFile = Join-Path $sandbox '_stderr.log'

    $previousLog = $env:VT_ARGV_LOG
    $env:VT_ARGV_LOG = $argvLog

    try {
        Push-Location $sandbox
        try {
            $stdout = & $invocation.Command @arguments 2>$stderrFile
            $exit = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        if ($exit -ne 0) {
            $stderr = (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue) ?? ''
            throw "case '$CaseName' exited $exit`n$($stderr.Trim())"
        }

        $argv = if (Test-Path -LiteralPath $argvLog) {
            [System.IO.File]::ReadAllText($argvLog,
                [System.Text.UTF8Encoding]::new($false)).TrimEnd("`r", "`n")
        } else {
            ''
        }

        $argv = ConvertTo-StableArgv -Argv $argv

        $out = (($stdout -join "`n") -replace "`r`n", "`n").TrimEnd()

        # Two clearly separated sections so a failing diff says which half
        # moved: the arguments the native tool received, and what the script
        # itself printed.
        $record = "# argv`n$($argv -replace "`r`n", "`n")"
        if ($out) { $record += "`n`n# stdout`n$out" }

        return $record.TrimEnd()
    } finally {
        $env:VT_ARGV_LOG = $previousLog
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Format-Difference {
    <#
        A line-oriented diff. Argument vectors are one argument per line, so
        showing the first differing lines in place tells you exactly which
        option moved - far more useful than dumping both records in full.
    #>
    param([string] $Expected, [string] $Actual)

    $expectedLines = $Expected -split "`n"
    $actualLines = $Actual -split "`n"
    $count = [Math]::Max($expectedLines.Count, $actualLines.Count)

    $lines = [System.Collections.Generic.List[string]]::new()
    $shown = 0

    for ($i = 0; $i -lt $count; $i++) {
        $e = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { $null }
        $a = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { $null }

        if ($e -ceq $a) { continue }

        if ($shown -ge 12) {
            $lines.Add('      ... further differences suppressed')
            break
        }

        # The array must be parenthesised: `-f` binds tighter than the comma
        # operator here, so `-f $i, $e` would format with $i alone and then
        # fail for want of a second argument.
        if ($null -ne $e) { $lines.Add("      -[{0,3}] {1}" -f @($i, $e)) }
        if ($null -ne $a) { $lines.Add("      +[{0,3}] {1}" -f @($i, $a)) }
        $shown++
    }

    return ($lines -join "`n")
}

function Get-GoldenPath {
    param([string] $CaseName, [hashtable] $Case)

    # A divergent case has two possible right answers: the reference
    # implementation's, and the port's. Keep them in separate trees so
    # neither can quietly overwrite the other.
    $set = if ($Case.ContainsKey('Diverges') -and $Implementation -eq 'powershell') {
        'divergent'
    } else {
        'parity'
    }

    Join-Path $TestRoot "golden/$set/$CaseName.txt"
}

$selected = $cases.GetEnumerator() |
    Where-Object { $_.Key -like $Name } |
    Sort-Object Key

if (-not $selected) {
    throw "no cases match '$Name'"
}

Write-Host ("{0} {1} case(s) against the {2} implementation" -f
    $(if ($Update) { 'Recording' } else { 'Checking' }), @($selected).Count, $Implementation)
Write-Host ''

$pass = 0
$fail = 0
$wrote = 0
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $selected) {
    $caseName = $entry.Key
    $case = $entry.Value
    $goldenPath = Get-GoldenPath -CaseName $caseName -Case $case

    try {
        $actual = Invoke-Case -CaseName $caseName -Case $case
    } catch {
        $fail++
        $failures.Add("${caseName}: $($_.Exception.Message)")
        Write-Host ("  {0,-34} ERROR" -f $caseName) -ForegroundColor Red
        continue
    }

    if ($Update) {
        $null = New-Item -ItemType Directory -Path (Split-Path $goldenPath -Parent) -Force
        [System.IO.File]::WriteAllText($goldenPath, $actual + "`n",
            [System.Text.UTF8Encoding]::new($false))
        $wrote++
        Write-Host ("  {0,-34} recorded" -f $caseName) -ForegroundColor DarkGray
        continue
    }

    if (-not (Test-Path -LiteralPath $goldenPath)) {
        $fail++
        $failures.Add("${caseName}: no golden at $goldenPath - run with -Update against ruby first")
        Write-Host ("  {0,-34} MISSING GOLDEN" -f $caseName) -ForegroundColor Yellow
        continue
    }

    $expected = ([System.IO.File]::ReadAllText($goldenPath) -replace "`r`n", "`n").TrimEnd()

    if ($actual -ceq $expected) {
        $pass++
        Write-Host ("  {0,-34} ok" -f $caseName) -ForegroundColor DarkGreen
    } else {
        $fail++
        $failures.Add(("{0}`n{1}" -f $caseName, (Format-Difference -Expected $expected -Actual $actual)))
        Write-Host ("  {0,-34} FAILED" -f $caseName) -ForegroundColor Red
    }
}

Write-Host ''

if ($Update) {
    Write-Host "Recorded $wrote golden file(s)." -ForegroundColor Green
    if ($fail) { Write-Host "$fail case(s) errored." -ForegroundColor Red }
} else {
    Write-Host "$pass passed, $fail failed."
}

if ($failures.Count) {
    Write-Host ''
    Write-Host 'Failures:' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  $failure" }
}

exit $(if ($fail) { 1 } else { 0 })
