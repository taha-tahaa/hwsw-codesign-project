# HW/SW Co-design (00460882) — Final Project

Benchmark optimization, profiling, and hardware acceleration for two
`pyperformance` benchmarks.

**All measurements were taken inside the course QEMU guest**, as the course
requires — `systemd-detect-virt` reports `kvm`, Ubuntu 22.04.5, kernel
5.15.0-1080-kvm, CPython 3.10.12, perf 5.15.179, Icarus Verilog 11.0,
pinned with `taskset -c 2`. Full record in
[results_qemu/environment.txt](results_qemu/environment.txt).

| Benchmark | Baseline | Optimized | Runtime cut | Speedup | Significance | Output |
|---|---|---|---|---|---|---|
| `pyflate`  (pure-Python bzip2 decoder) | 1115.1 ms ± 10 | 444.6 ms ± 6 | **60.1%** | **2.51×** | Significant, t = 676.00 | byte-identical (MD5) |
| `raytrace` (pure-Python ray tracer)    | 809.3 ms ± 12 | 282.2 ms ± 14 | **65.1%** | **2.87×** | Significant, t = 315.11 | bit-identical image |

**Requirement check.** Project.pdf instruction 6 asks for ≥ 7% on two or more
benchmarks. Both clear it by roughly 9×, under either reading of "7%
improvement" — as a runtime cut (60.1% / 65.1%) or as a speedup (2.51× / 2.87×,
i.e. 151% / 187% faster, against 1.07× required). `pyperf`'s own t-test rates
both significant.

## Running it — in the guest

Boot the course image from `/scratch/$USER` on your assigned naranja host:

```bash
qemu-img create -f qcow2 -b jammy-server-cloudimg-amd64-disk-kvm.img -F qcow2 work.qcow2
```

```bash
qemu-system-x86_64 -m 4096 -smp 8 -cpu host,pmu=on -accel kvm -nographic -nic user,model=virtio-net-pci -drive file=work.qcow2,format=qcow2
```

Login `root` / `ubuntu`, then inside the guest:

```bash
./script_pyflate.sh all
```

```bash
./script_raytrace.sh all
```

Two details of that QEMU command matter:

- **`pmu=on`** — without it the guest has no virtual PMU and `perf` answers
  `<not supported>` for every hardware event. With it, cycles / instructions /
  cache / branch counters all work, which is the only reason this project has
  real counter data.
- **`work.qcow2`** — a qcow2 *overlay*, so the course image itself is never
  written to.

## What perf can and cannot do inside the guest

Established by testing, not assumed. `./script_*.sh setup` re-checks all three
on your machine and prints the answers.

| | In the guest |
|---|---|
| hardware **counting** (`perf stat`) | **works** — but only with `pmu=on` |
| hardware **sampling** (`perf record -e cycles`) | **captures zero samples** → flame graphs use `-e cpu-clock` |
| six events in one `perf stat` | one silently reads **0** → measure in groups of two |
| Python function names in perf | **impossible** on CPython 3.10 (`-X perf` is 3.12+) → py-spy |
| `stalled-cycles-frontend/backend` | `<not supported>` → no CPI stack in the VM |

The third one was a real trap: the first measurement pass reported
`cycles = 0` and would have been written up as a guest limitation. It is
counter multiplexing.

## Why these two benchmarks

They were chosen for **contrast**, and that contrast is the spine of both
reports:

| | `pyflate` | `raytrace` |
|---|---|---|
| Bound by | integer / control flow / irregular memory | floating point / allocation |
| Hot kernel | `find_next_symbol()`, `move_to_front()`, `bwt_reverse()` | `Sphere.intersectionTime()` |
| Bit rate | **variable**-length Huffman codes | fixed-shape arithmetic |
| Accelerator pattern | **dataflow** (valid/ready handshakes) | **systolic array** (weight-stationary) |

Variable-length codes are precisely what rules out a systolic array for
`pyflate` — an array with no control circuitry mis-aligns on a data-dependent
rate. The fixed-shape intersection kernel is precisely what makes one ideal for
`raytrace`. One benchmark motivates each of the two dominant accelerator
paradigms from the lectures.

## Repository layout

```
report_pyflate.txt          full report: analysis, optimizations, HW proposal
report_raytrace.txt         full report: analysis, optimizations, HW proposal
script_pyflate.sh           setup | verify | bench | profile | hw
script_raytrace.sh          setup | verify | bench | profile | hw
prompt.txt                  AI prompts used, as required by the brief

benchmarks/
  pyflate/    pyflate_baseline.py   pyflate_optimized.py   data/
  raytrace/   raytrace_baseline.py  raytrace_optimized.py

hw/
  pyflate_decoder/          DATAFLOW accelerator
    huffman_decoder.v         20 parallel comparators + priority encoder
    bit_window.v              64-bit window, variable-width retire
    mtf_bwt_engine.v          1-cycle MTF shift + BWT pointer-chase engine
    bwt_index_builder.v       histogram + prefix sum + scatter -> builds T[]
    bzip2_accel_top.v         CSR/DMA integration
    tb_huffman_decoder.v      self-checking testbench
    tb_bit_window.v           variable-width retire + simultaneous refill
    tb_bwt_index_builder.v    T[] vs the software reference
    golden_model.py           RTL logic in Python, run against the real data
  raytrace_mac/             SYSTOLIC accelerator
    fp32_units.v              pipelined binary32 multiplier and adder
    ray_sphere_array.v        sqrt + intersection PE + weight-stationary array
    tb_ray_sphere.v           single-PE testbench
    tb_ray_array.v            nearest-hit across 8 spheres (array level)
    gen_fp_vectors.py         generates a 400-vector randomized testbench
    sqrt_model.py             sqrt accuracy measurement

tools/
  verify.py                 correctness gate (MD5 / framebuffer comparison)
  verify_extra.py           same code vs libbz2 on 16 streams the benchmark
                            never feeds it, plus 7 raytrace resolutions
  regress.sh                all nine correctness + RTL checks, in one go
  ablate.py                 per-optimization attribution by ablation
  profile_target.py         single in-process workload run, for perf record
  flame_top.py              ranks Python functions from folded perf stacks
  cprofile_report.py        call-count ranking

results_qemu/           flame graphs (py-spy + perf), perf stat, pyperf JSON
```

## Running it

```bash
./script_pyflate.sh all
```

```bash
./script_raytrace.sh all
```

Or one stage at a time — `setup`, `verify`, `bench`, `profile`, `hw`.

### A trap in the brief's suggested `perf` command

The brief suggests `perf record -F 999 -g -- python3-dbg -m pyperformance run`.
`pyperformance` builds a virtualenv and **re-execs the benchmark in a child
process** using an interpreter that is not `python3-dbg` unless `--python` is
passed, so `perf` samples process machinery rather than the decoder.
[tools/profile_target.py](tools/profile_target.py) runs the workload in-process
instead, so every sample belongs to the code under study.

## Correctness is a gate, not a footnote

Timing is never reported without passing this first.

```bash
python3 tools/verify.py
```

- **pyflate** — all 399,360 decompressed bytes compared against the baseline,
  plus the benchmark's own MD5 (`afa004a630fe072901b1d9628b960974`).
- **raytrace** — the full 30,000-byte RGB framebuffer compared byte for byte.
  Every optimized floating-point expression preserves the baseline's operand
  order and grouping, so no result differs even in the last ulp.

## Hardware verification — and the bug it caught

The RTL is simulated, not merely written. On the first run
`tb_ray_sphere` **failed**: `2+3` produced 6.5 and `9-4` produced 2.5.
`fp32_add` had two coupled off-by-one errors — the carry path normalized the
leading one to bit 26 while the leading-zero path normalized it to bit 27, and
the mantissa slice matched neither convention. Fixed, then hardened with a
randomized testbench, because three hand-picked vectors are not enough to trust
a floating-point unit.

```bash
./script_pyflate.sh hw
```

```bash
./script_raytrace.sh hw
```

Or run all eleven checks at once:

```bash
./tools/regress.sh
```

| Check | Result |
|---|---|
| correctness gate | PASS — both benchmarks byte/bit-identical |
| extended correctness | PASS — 16 bzip2 streams vs **libbz2**, 7 raytrace resolutions |
| `golden_model.py` | PASS — all **148,271** real symbols, MD5 matches |
| `sqrt_model.py` | 1.16 ulp truncating / 0.69 ulp rounding, 6,008 samples |
| `tb_huffman_decoder` | PASS — 8 symbols, symbol **and** retired bit count |
| `tb_bit_window` | PASS — 12 irregular retires, 1–20 bits, across word boundaries |
| `tb_bwt_index_builder` | PASS — T[] matches the software reference exactly |
| `bzip2_accel_top` elaboration | OK (top + decoder + window + MTF/BWT + T[] builder) |
| `tb_ray_sphere` | PASS — single PE, bit-exact worked `t = 8.0` case |
| `tb_ray_array` | PASS — nearest-hit correct across 8 spheres |
| `tb_fp_random` (400 vectors) | PASS — add and mul bit-exact vs binary32 |

All eleven green **inside the QEMU guest** with Icarus Verilog 11.0.

The golden models exist so the hardware *algorithms* can be checked without a
simulator; the testbenches check the RTL itself.

## Headline findings

**`pyflate` — the obvious diagnosis was wrong.** `find_next_symbol()` scans a
sorted table linearly, so "the scan is too deep" is the natural conclusion. The
profile says otherwise: 148,271 calls produced only 341,601 `snoopbits` calls —
ratio **2.3**, not ~250. Move-to-front keeps hot symbols on short codes, so the
scan almost always exits after two probes. The real cost was ~**seven Python
function calls per symbol**. Fixing call count (3.19M → 583K), not scan depth,
is what produced the speedup.

**`raytrace` — the biggest win was a three-line bug fix.** `_lightIsVisible()`
rebuilt the same shadow ray — `sqrt` included — once per object, inside a loop
it doesn't depend on. Worth **44%**. Meanwhile killing ~200K allocations per
frame, the instinctive fix, was worth only **8%**.

**The hardware counters prove the mechanism.** In both benchmarks cycles fell in
step with the stopwatch (2.51× and 2.91× against speedups of 2.51× and 2.87×)
while IPC moved only 2.60→2.87 and 2.59→2.70. Instructions retired fell 2.27×
and 2.78×. So the speedup decomposes as *mostly fewer instructions*, with a
4–10% efficiency bonus. The machine didn't get smarter; it was asked to do far
less.

**Two profilers disagreed, and the sampling one was right.** cProfile charges
`move_to_front` about 10%; py-spy puts it at **15.69%**, third overall.
Instrumentation charges per *call*, sampling charges per *cycle* — and
`move_to_front` is a function that is simply slow inside, rebuilding a list from
three slices per call.

**A rate is not a metric.** raytrace's cache-miss *rate* rose 1.02% → 2.91%
while absolute misses fell 2.18×, because 6.23× fewer references remain and the
survivors are the genuinely cold ones. Same trap the course's own perf tutorial
sets with row- vs column-major traversal.

**Half the renderer was type checks.** The Vector/Point wrappers — `dot`,
`__sub__`, `__init__`, `scale`, `normalized`, `magnitude` — are **59.74%** of
baseline runtime, and every one of the 509,871 `dot()` calls opens with a
`mustBeVector()` assertion. The guards cost more than the arithmetic they guard.

## Branches

- `bench/pyflate` — decoder optimization and the dataflow accelerator
- `bench/raytrace` — renderer optimization and the systolic accelerator
- `main` — integration, shared tooling, reports
