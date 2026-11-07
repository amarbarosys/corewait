# corewait design

corewait is two programs joined by four text files. A bash script talks to the profilers and the devices.
A Mojo analyzer reads the files and knows nothing about devices, so CI runs it on committed recordings.

## Layout

```
corewait            bash: device table, record, pick, merge, stat, bw, build; hands show/diff/budget on
src/corewait.mojo   analyzer: show, diff, budget (built to build/corewait-an on first use)
probes/             cwprobe.mojo (4 kernels) + kgen_shim.c (no Mojo runtime on a phone)
fixtures/           committed recordings; fixtures/golden/ holds the frozen tables
check.sh            CPU-only gate on those fixtures
```

## Data flow

1. `record` runs the program under `perf record` (`simpleperf record` on phones) with four event roles:
   `cycles`, `mem`, `fe`, `br`. Each role has its own period.
2. The raw samples become `samples.tsv`: event, library, address, count in raw events.
3. A second run under `perf stat` gives the whole-run counters in `stat.tsv`: cycles, instructions, slots,
   frontend, backend, retiring. The `run:` line of `show` comes from here, not from the samples.
4. `llvm-objdump` output is cut to the functions that hold samples: `objdump.txt`.
5. The analyzer joins `samples.tsv` to `objdump.txt` by address. Each instruction row gets a cause.

## Cause rule

A sample lands a few instructions after the one that stalled. The cycles and memory events of a row move
back to the nearest preceding load, and branch-miss events to the nearest preceding branch, up to K rows
(`--k`, default 4; `--k 0` turns it off). Then, first match wins: `mem`, `branch`, `dep`, `fe`, `busy`. An
event counts for a row only with 10 samples and at least half as large a share of the event as of the
cycles. A row below that gets no cause from the event.

## Memory model

- `objdump.txt` is read in 8 MB chunks and an instruction line is cut to 4096 bytes. A Mojo kernel's branch
  row names the whole mangled symbol of its target, so one line can be 1.4 MB.
- `diff` aligns the rows of same-named functions by longest common subsequence. Up to 40M cells
  (`CW_ALIGN_CELLS`) it fills the full table. Above that it uses Hirschberg's divide and conquer, with
  memory linear in the rows. `check.sh` forces both paths on the same pairs and requires equal output.
- Gate figures: 1M sample rows in `show` take 0.12 s and 42 MB. A 7000 x 7000 row `diff` with 1.4 MB symbol
  lines takes 0.28 s and 18 MB.

## Choices

- **Text files as the interface.** A recording can be copied, diffed, committed and read by hand. The
  analyzer runs on one machine while the device is on another.
- **Registers masked in `diff`.** A rebuild often renames registers. Masking them keeps the rows aligned, so
  a delta shows a change in the code.
- **One period per event role.** `CW_DIV` shortens all periods for a short kernel; `merge` adds runs.
- **User-space events only (`:u`).** Kernel samples and system-wide counters need root on the phones, so each
  command profiles a program it starts, or a `--pid` it is given.
- **One runner per phone.** `record` and `bw` hold a lock file for the whole command.

## Rejected

- **Reading `objdump.txt` whole.** A 1.1 GB file made `diff` take 36 s and 5.7 GB, and then refuse.
  Chunked reading and the line cap give 4.5 s and 59 MB.
- **A cause from the sampled row alone.** A sample lands after the load, so the load row looks innocent.
  The skid rule moves the cycles back to the load.
