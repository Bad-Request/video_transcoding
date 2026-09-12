# Golden-file harness

The tools in this project are pure functions in disguise: ffprobe JSON plus
options in, one argument vector out. This harness pins that function down, so
the PowerShell port can be verified without running a single encode.

## Running it

    ./test/Compare-Golden.ps1 -Implementation powershell

Narrow to a group while working on one:

    ./test/Compare-Golden.ps1 -Implementation powershell -Name 'audio-*'

Re-check against the reference implementation (needs Ruby on `PATH`):

    ./test/Compare-Golden.ps1 -Implementation ruby

## How it works

Fake `ffprobe`, `ffmpeg` and `HandBrakeCLI` go on `PATH` ahead of the real
ones, so a run touches no media, decodes nothing, and produces identical
output on every machine. Each case runs in its own temporary working
directory, because the tools refuse to overwrite an existing output file.

What gets recorded is the **argv** the tool handed to the native binary — one
argument per line, captured by the shim — plus anything it printed to stdout.

Deliberately *not* the escaped command line that `--dry-run` prints. Ruby
escapes differently on Windows than on POSIX (`escape_string` branches on
`RUBY_PLATFORM`), and the port changes the quoting style on purpose, so
goldening that string would compare presentation rather than behaviour and
would diverge on every single case.

## Layout

| Path | What it is |
| --- | --- |
| `cases.psd1` | The sweep matrix: tool, fixture and arguments per case |
| `fixtures/*.json` | Captured ffprobe output, one per source type |
| `golden/parity/` | Expected argv — must match the Ruby original exactly |
| `golden/divergent/` | Expected argv where the port deliberately differs |
| `shims/` | Fake ffprobe, ffmpeg and HandBrakeCLI |
| `New-Fixture.ps1` | Regenerates the fixtures |
| `Compare-Golden.ps1` | The harness |

## Parity and divergence

Most cases must produce byte-identical argv from both implementations. Cases
marked `Diverges` in `cases.psd1` are ones where the port deliberately fixes a
defect or changes a default; their goldens live in `golden/divergent/` so
neither answer can quietly overwrite the other.

`--no-faststart` must reproduce the parity golden byte-for-byte. That is a
free check that the flag is wired to exactly one thing.

## Regenerating fixtures

    ./test/New-Fixture.ps1

Fixtures are genuine `ffprobe` output captured from tiny synthetic media built
with ffmpeg. The one exception is bitmap subtitles: ffmpeg has no PGS encoder
and refuses to transcode text subtitles to bitmap ones, so those streams are
captured as text and rewritten via `Edit-FixtureSubtitle`. That function is
the only place any fixture field is not straight from ffprobe.

## Two traps worth knowing about

Both cost real time during this harness's construction.

**PowerShell mangles `-c:v`.** `$args` splits it into `-c` and `v`, because
PowerShell reads `-name:value` as a parameter with a colon-delimited value —
and ffmpeg options are exactly that shape. The Windows shim therefore reads
`[Environment]::GetCommandLineArgs()` rather than `$args`, so .NET splits the
command line with the same rules the real tool would have seen. A `param()`
block causes a related problem: it binds ffmpeg's `-loglevel` as a script
parameter. The shim declares no parameters at all.

**`-f` binds tighter than the comma operator.** `"{0} {1}" -f $a, $b` formats
with `$a` alone and then fails for want of a second argument. Wrap the
arguments: `-f @($a, $b)`. The same trap applies inside method calls —
`[regex]::Escape($x -replace '\\', '/')` is parsed as `Escape($x -replace
'\\', '/')` with two arguments.
