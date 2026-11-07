---
name: corewait
description: Find why CPU code is slow, per instruction, on a desktop, a laptop or an Android phone. Record hardware counters with corewait, read the cause of each hot row (mem, branch, dep, fe, busy), change the code, prove the gain with diff and lock it with budget. Use when asked which instruction stalls, why a Mojo or C kernel is slow on a CPU or on ARM, to check a CPU optimisation before and after, or to gate a kernel's stall mix in CI.
---

# corewait

A cycle count says the kernel is slow. corewait says which instruction waits, and on what.

## When to use

- A CPU kernel (Mojo, C, Rust) is slower than its roofline and the reason is unknown.
- A CPU change must be proved row by row before it is claimed.
- A phone (ARM) behaves differently from x86 and the stall must be seen.
- A kernel needs a CI gate: "this function may spend at most N % on mem".

Not for GPU kernels, not for "which function is hot" alone (`perf report` is enough), not for runs under
about 40 ms without `CW_DIV` and `merge`: too few samples.

## Install from a clone

```
git clone https://github.com/amarbarosys/corewait && cd corewait
pixi install                                       # Mojo for the analyzer, built on first use
./corewait show fixtures/desktop-chase --causes    # works with no device: committed recording
ln -s "$PWD/skills/corewait" "$HOME/.claude/skills/corewait"   # or a project's .claude/skills/
```

Needs `perf`, `llvm-objdump`, `gawk` (full list: `docs/api.md`). Phones also need `adb`; the laptop `ssh`.
Devices: `desktop laptop xiaomi flip oneplus`; set `CW_LAPTOP_SSH` and `CW_*_ADB` for the remote ones.

## The 5 commands

```
./corewait record desktop OUT -- [K=V ...] ./binary [ARGS]   # samples.tsv, stat.tsv, objdump.txt, meta.txt in OUT
./corewait show OUT --causes                                  # cause mix of the whole recording
./corewait show OUT --fn SYMBOL --top 20                      # rows of one function (substring match)
./corewait diff OUT_OLD OUT_NEW --top 20                      # header: cycles A -> B (percent); rows aligned by text
./corewait budget OUT budget.txt                              # lines "fn cause max-percent"; exit 1 on a breach
```

Loop: record, `show --causes`, narrow with `--fn`, act on the top cause of the hot function, record
again, `diff`, then write a budget file for CI.

| cause | the core waits on | first moves |
|---|---|---|
| `mem` | a load that misses the caches | pack hot fields, prefetch, tile to L2, fewer passes. With `--bytes B --bw GBPS`: near 100 % of `bw` means memory-bound, stop tuning compute |
| `branch` | a mispredicted branch | branchless select or min/max, sort or partition the input, hoist the test |
| `dep` | a register written 1-3 rows earlier | more accumulators, reassociate, interleave independent work |
| `fe` | instruction fetch or decode | smaller hot loop, fewer inlined cold paths. On ARM an `fe` row next to a mispredict is the branch's refetch |
| `busy` | nothing: the core works | fewer instructions: vectorise, strength-reduce |

## Gotchas

- **Skid.** A sample lands a few instructions after the stall. corewait moves a row's cycles back to the
  nearest load (branch), up to `--k 4` rows. A hot `mov` after a load is the load's cost.
- **Noise floor.** An event counts on a row only with at least 10 samples. `busy` on a 1 % row means too
  few samples, not "fine". Under about 3 % delta, record twice and `merge`.
- **Short kernel.** `CW_DIV=20 ./corewait record ...` in a loop, then `./corewait merge OUT OUT1 OUT2 ...`.
- **`dep` on `add rax, 1`** is by design: the row reads its own result. Zero idioms are not dependences.
- **`run:` line** comes from the whole-run `stat` pass, not from the samples. `--no-stat` skips that pass.
- **Python or a library.** `record desktop OUT --dso auto --no-stat -- python job.py` reports the hottest library.
  Read `OUT/dsos.tsv`, then `./corewait pick OUT LIB`. A BLAS or OpenMP pool spins when idle and tops
  the list: set `OPENBLAS_NUM_THREADS=1` or `OMP_WAIT_POLICY=passive` as `K=V`. `--pid PID -- sleep 60`
  samples a running server.
- **Phones.** The binary must be built for the phone. `./corewait build DEV` builds the probe only.
  `record` and `bw` lock the phone, so two runs never overlap.
- **Receipt.** A claim names the device, the OUT path, the `diff` header line and the commit measured.
- **Check the tool first** on a new device: `./check-live.sh DEV` records four probes with a known cause each.
- `FAIL input: no objdump.txt in OUT` means OUT is not a recording: record again.
  `FAIL show: no samples in the selected functions` means a wrong `--fn` or a too short run.

## Gate

```
CW_NO_RECORD=1 pixi run check      # CPU only: builds the analyzer, runs the frozen fixtures; ends with ALL OK
```

Docs: `docs/api.md` (every command and flag), `docs/design.md`, `docs/DEVICES.md`.
