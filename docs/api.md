# corewait CLI reference

corewait is a command line tool, not a library. This page lists every subcommand and flag. `./corewait`
(a bash script) takes the first word and runs it. `show`, `diff` and `budget` go on to the Mojo analyzer
(`build/corewait-an`), which the script builds with `pixi run mojo build src/corewait.mojo` when it is
missing or older than its source.

```
corewait record DEV OUT [--dso LIB|auto] [--no-stat] [--pid PID] -- [K=V ...] BINARY [ARGS...]
corewait pick OUT LIB|auto
corewait show OUT [BINARY] [--top N] [--causes] [--fn SYMBOL] [--k K] [--bytes B --bw GBPS]
corewait diff OUT_A OUT_B [BIN_A BIN_B] [--top N] [--k K]
corewait budget OUT FILE [--k K]
corewait merge OUT DIR...
corewait stat DEV OUT
corewait bw DEV
corewait build DEV
corewait attached DEV
```

`DEV` is one of `desktop laptop xiaomi flip oneplus` (table in `docs/DEVICES.md`). `OUT` is a recording
directory. Running `./corewait` with no command, or with an unknown one, prints
`FAIL usage: corewait record|pick|show|diff|budget|merge|stat|bw|build|attached ...` and exits 1.

## Requirements

- `pixi` (installs Mojo, see `pixi.toml`), `gawk`, `sha256sum`, `taskset`, `flock`.
- `llvm-objdump` and `llvm-readelf` (`objdump` is the fallback for some stripped libraries).
- `perf` for `desktop` and `laptop`; `ssh` and `scp` for `laptop`.
- `adb` for the phones. Phone binaries need `simpleperf` on the phone and the Android NDK `clang`
  (the path is set in `build()` at the top of `corewait`).
- If a `gpu-wait` command is on `PATH`, the Mojo builds queue behind it. Without it they run directly.

## Exit codes (all subcommands)

- `0`: done.
- `1`: any failure. The message is one line, `FAIL <step>: <reason>`. The script prints it on stderr, the
  analyzer on stdout. `budget` also exits 1 when a rule is breached.
- `attached` only: `3` means the device is configured but does not answer.

Steps that appear in `FAIL` lines: `usage device build record input samples show budget lock pin dso pick
objdump bw`.

## record

`corewait record DEV OUT [--dso LIB|auto] [--no-stat] [--pid PID] -- [K=V ...] BINARY [ARGS...]`

Runs `BINARY` under the device profiler and writes the recording into `OUT`. `BINARY` is a host ELF with
symbols; for a phone or the laptop it is copied to the device first. A bare name is looked up on `PATH`.
`K=V` words before `BINARY` go into the program's environment (the form `-- env K=V BINARY` also works).
The program runs twice: once sampled, once under `stat` for the whole-run counters.

| Flag | Meaning |
|---|---|
| `--dso LIB` | Report one loaded library of the process, for a host program such as `python`. `auto` takes the one with the most cycles. A `BINARY` that is not an ELF file (a script) implies `auto`. |
| `--no-stat` | Skip the second run (the whole-run counter pass). |
| `--pid PID` | Sample a running process for as long as `BINARY` runs (for example `sleep 60`). Implies `--dso auto --no-stat`. |

`--dso`, `--pid` and a script `BINARY` need a `perf` device (`desktop`, `laptop`). A phone takes a lock
(`$CW_LOCK_DIR/phone-SERIAL.lock`) for the whole command, and the program is pinned to the first CPU mask
that `taskset` accepts on that device.

Output files in `OUT`: `samples.tsv`, `stat.tsv`, `objdump.txt` (only the functions that hold samples),
`meta.txt` (device, binary, sha256, command, host path, date), `run.txt` (program output), `stat.raw`,
and on `perf` devices `perf.data` and `dsos.tsv` (libraries ranked by cycles). Phones also write
`report.txt`. Formats: `docs/DEVICES.md` and the header of `corewait`.

## pick

`corewait pick OUT LIB|auto`

Points `OUT` at another library of `OUT/perf.data`, with no new run. Needs a recording made on a `perf`
device. A failed pick keeps the old `samples.tsv`. Rewrites `samples.tsv`, `objdump.txt` and `meta.txt`.

## show

`corewait show OUT [BINARY] [--top N] [--causes] [--fn SYMBOL] [--k K] [--bytes B --bw GBPS]`

Prints the `run:` line from `stat.tsv`, the hot functions (`fn` lines), then one row per instruction:
`addr cyc% cycles mem fe br cause instruction`. `BINARY` rebuilds a missing `objdump.txt`.

| Flag | Default | Meaning |
|---|---|---|
| `--top N` | 20 | Number of instruction rows. |
| `--causes` | off | Print the cause table (`mem fe dep branch busy`, cycles and share) and no rows. |
| `--fn SYMBOL` | all | Keep functions whose name contains `SYMBOL`. Fails if none has samples. |
| `--k K` | 4 | Skid distance in rows. `0` turns the skid rule off. |
| `--bytes B` `--bw GBPS` | off | Together: add a `sol:` line, achieved GB/s over the device bandwidth from `corewait bw`. Needs `time_us` in `stat.tsv`. |

Output files: none (stdout).

## diff

`corewait diff OUT_A OUT_B [BIN_A BIN_B] [--top N] [--k K]`

Prints `diff: cycles A -> B (percent), rows changed N`, then the rows with the largest cycle change
(`addr A`, `addr B`, cycles of each, delta, cause in B, text). Rows of functions with the same name are
aligned by longest common subsequence on the instruction text with register names masked. A row with `-`
as its address on one side is gone or new. `--top` defaults to 20. `CW_ALIGN_CELLS` (default 40000000)
sets the table size above which the alignment runs in linear memory. Output files: none.

## budget

`corewait budget OUT FILE [--k K]`

`FILE` has one rule per line: `fn cause max-percent`. `fn` is a substring of a function name, `cause` is
`mem fe dep branch busy`, and a line that starts with `#` is a comment. For each rule the command prints
`ok` or `FAIL budget:` with the measured share. Exit 1 if any rule is breached, or if a rule is bad (wrong
field count, unknown cause, bad number, no samples in the function, no rules). Output files: none.

## merge

`corewait merge OUT DIR...`

Adds the samples and counters of repeated recordings of one binary into `OUT`. Use it for a kernel that
runs under about 0.5 s, with `CW_DIV` set while recording. Writes `samples.tsv`, `stat.tsv`, `meta.txt`
(with a `merged` count) and `objdump.txt`.

## stat

`corewait stat DEV OUT`

Writes `OUT/stat.tsv` again from `OUT/stat.raw`. An event the CPU did not count is left out, and no share
is derived from it.

## bw

`corewait bw DEV`

Runs 1, 2, 4 and all-thread concurrent `stream` probes and prints one line:
`bw DEV GB/s 1t=N 2t=N 4t=N <threads>t=N`. Needs `build/cwprobe-DEV`, so run `corewait build DEV` first
(`FAIL bw` otherwise). Takes the phone lock. Output files: none.

## build

`corewait build DEV`

Cross-compiles `probes/cwprobe.mojo` for the device and links it with `probes/kgen_shim.c`, so it needs no
Mojo runtime on the device. Writes `build/cwprobe-DEV` and the logs `build/cwprobe-DEV.log` and
`build/cwprobe-DEV.link.log`. The probe runs `chase`, `stream`, `fmachain` or `branchy` (`cwprobe KERNEL
[--n MB] [--go FILE]`).

## attached

`corewait attached DEV`

Exit 0 when the device answers, 3 when it is configured but not reachable (a wifi phone that dropped off).
`desktop` always answers. Prints nothing.

## Environment variables

| Variable | Used by | Meaning |
|---|---|---|
| `CW_DEVICES` | all | Config file with the variables below. Default `$HOME/.config/corewait/devices.env`. |
| `CW_LAPTOP_SSH` | `laptop` | `user@host` of the laptop. |
| `CW_XIAOMI_ADB`, `CW_FLIP_ADB`, `CW_ONEPLUS_ADB` | phones | adb serial or `ip:port`. |
| `CW_XIAOMI_LOCK` | `xiaomi` | Lock serial, when other tools share the phone. |
| `CW_LOCK_DIR` | phones | Folder of the phone lock files. Default `$HOME/.cache/corewait`. |
| `CW_DIV` | `record`, `stat` | Divides every sampling period, for short kernels. |
| `CW_ALIGN_CELLS` | `diff` | Table size at which `diff` switches to linear memory. |

A device that needs a variable and has none fails at once with `set CW_...`.

## Gates in the repo

- `check.sh`: CPU-only gate (`pixi run check`). `CW_NO_RECORD=1` skips the probe build and the record on
  this machine (it needs `perf` counters). `FREEZE=1` rewrites `fixtures/golden/`.
- `check-live.sh DEV [freeze]`: records the four probes on a device and checks each top cause and `bw`
  against the stream probe. `freeze` copies the recordings to `fixtures/DEV-PROBE/`.
