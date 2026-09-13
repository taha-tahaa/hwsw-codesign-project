# HW/SW Co-design (00460882) — Final Project

Benchmark optimization, profiling, and hardware acceleration for two
`pyperformance` benchmarks.

| Benchmark | Baseline | Optimized | Speedup | Output |
|---|---|---|---|---|
| `pyflate`  (pure-Python bzip2 decoder) | 733 ms ± 7 ms | 309 ms ± 2 ms | **2.38×** | byte-identical (MD5) |
| `raytrace` (pure-Python ray tracer)    | 554 ms ± 5 ms | 217 ms ± 1 ms | **2.55×** | bit-identical image |

The project requires ≥ 7% on two benchmarks. These are 58% and 61% reductions.

**Measured on the course machine**, not a laptop: `naranja7.cslcs.technion.ac.il`
(the server assigned to `ece882-031` — `/scratch/ece882-031` exists there and not
on `naranja10`), 2× Xeon E5-2630 v3, Ubuntu 24.04.4, kernel 6.8, CPython 3.12.3,
pyperf 2.10.0, perf 6.8.12, Icarus Verilog 12.0. Pinned with `taskset -c 8` at
load average 0.16, so the error bars are 1–2%. Full record in
[results_naranja7/environment.txt](results_naranja7/environment.txt).

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
    bzip2_accel_top.v         CSR/DMA integration
    tb_huffman_decoder.v      self-checking testbench
    golden_model.py           RTL logic in Python, run against the real data
  raytrace_mac/             SYSTOLIC accelerator
    fp32_units.v              pipelined binary32 multiplier and adder
    ray_sphere_array.v        sqrt + intersection PE + weight-stationary array
    tb_ray_sphere.v           self-checking testbench
    gen_fp_vectors.py         generates a 400-vector randomized testbench
    sqrt_model.py             sqrt accuracy measurement

tools/
  verify.py                 correctness gate (MD5 / framebuffer comparison)
  ablate.py                 per-optimization attribution by ablation
  profile_target.py         single in-process workload run, for perf record
  flame_top.py              ranks Python functions from folded perf stacks
  cprofile_report.py        call-count ranking

results_naranja7/           flame graphs, perf stat, pyperf JSON, RTL logs
```

## Running it

```bash
./script_pyflate.sh all
```

```bash
./script_raytrace.sh all
```

Or one stage at a time — `setup`, `verify`, `bench`, `profile`, `hw`.

### Two traps in the brief's suggested `perf` command

The brief suggests `perf record -F 999 -g -- python3-dbg -m pyperformance run`.
Both halves of that misfire, and the scripts work around both:

1. **`pyperformance`/`pyperf` fork a worker and re-exec** a *different*
   interpreter, so `perf` samples process machinery rather than the benchmark.
   [tools/profile_target.py](tools/profile_target.py) runs the workload
   in-process instead.
2. **Python function names need CPython's `-X perf` trampoline**, which exists
   only in **3.12+**. naranja7 runs 3.12.3 so the flame graphs here carry
   `py::` frames; the course **QEMU guest (Ubuntu 22.04) ships CPython 3.10**,
   where `perf` shows only `_PyEval_EvalFrameDefault`. The scripts detect the
   version and always emit `cProfile` as a fallback.

A related trap worth knowing: the trampoline writes `/tmp/perf-<pid>.map` and
`perf script` needs that file to resolve `py::` frames. Anything that clears
`/tmp` between record and script silently turns the graph into interpreter
soup. Record and collapse in one pass.

### PMU counters

`perf_event_paranoid = -1` on naranja7, so hardware counters work fully and the
reports carry real cycles/IPC/cache/branch data. Inside the QEMU guest they are
frequently unavailable — `setup` detects that and tells you to move the
cache/IPC analysis to the host, keeping guest and host numbers labelled apart.

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

| Check | Result |
|---|---|
| `tb_huffman_decoder` | PASS — 8 symbols, symbol **and** retired bit count |
| `bzip2_accel_top` elaboration | OK (top + decoder + window + MTF/BWT) |
| `tb_ray_sphere` | PASS — all bit-exact, incl. the worked `t = 8.0` case |
| `tb_fp_random` (400 vectors) | PASS — add and mul bit-exact vs binary32 |
| `golden_model.py` | PASS — all **148,271** real symbols, MD5 matches |
| `sqrt_model.py` | 1.16 ulp truncating / 0.69 ulp rounding, 6,008 samples |

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
it doesn't depend on. Worth **49%**. Meanwhile killing ~200K allocations per
frame, the instinctive fix, was worth only **7%**.

**The hardware counters prove the mechanism.** In both benchmarks IPC barely
moved (2.73→2.85 and 2.44→2.52) while instructions retired fell 2.31× and
2.57×, against speedups of 2.38× and 2.55×. The machine didn't get smarter; it
was asked to do far less.

**Two profilers disagreed, and the sampling one was right.** cProfile ranks
`move_to_front` around 8%; perf puts it at **19.28%**, second overall.
Instrumentation charges per *call*, sampling charges per *cycle* — and
`move_to_front` is a function that is simply slow inside.

**A rate is not a metric.** raytrace's cache-miss *rate* rose 1.20% → 1.40%
while absolute misses fell 2.65×, because 3.08× fewer references remain and the
survivors are the genuinely cold ones. Same trap the course's own perf tutorial
sets with row- vs column-major traversal.

## Branches

- `bench/pyflate` — decoder optimization and the dataflow accelerator
- `bench/raytrace` — renderer optimization and the systolic accelerator
- `main` — integration, shared tooling, reports
