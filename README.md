# HW/SW Co-design (00460882) — Final Project

Benchmark optimization, profiling, and hardware acceleration for two
`pyperformance` benchmarks.

| Benchmark | Baseline | Optimized | Speedup | Output |
|---|---|---|---|---|
| `pyflate`  (pure-Python bzip2 decoder) | 482 ms ± 13 ms | 230 ms ± 18 ms | **2.10×** | byte-identical (MD5) |
| `raytrace` (pure-Python ray tracer)    | 314 ms ± 9 ms  | 133 ms ± 7 ms  | **2.37×** | bit-identical image |

The project requires ≥ 7% on two benchmarks. These are 52% and 58% reductions.

> **Where these numbers come from.** They were measured on the development
> machine (CPython 3.12.1, pyperf 2.10.0, x86-64). The submission numbers must
> be regenerated inside the course QEMU guest (Ubuntu 22.04 / CPython 3.10) —
> `./script_pyflate.sh` and `./script_raytrace.sh` reproduce every table in the
> reports. Absolute times will differ; the bottleneck ranking should not.

## Why these two benchmarks

They were chosen for **contrast**, and that contrast is the spine of both
reports:

| | `pyflate` | `raytrace` |
|---|---|---|
| Bound by | integer / control flow / irregular memory | floating point / allocation |
| Hot kernel | `find_next_symbol()`, `bwt_reverse()` | `Sphere.intersectionTime()` |
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
  pyflate/
    pyflate_baseline.py     unmodified pyperformance source
    pyflate_optimized.py    optimized decoder (byte-identical output)
    data/interpreter.tar.bz2
  raytrace/
    raytrace_baseline.py    unmodified pyperformance source
    raytrace_optimized.py   optimized renderer (bit-identical image)

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
    sqrt_model.py             sqrt accuracy measurement

tools/
  verify.py                 correctness gate (MD5 / framebuffer comparison)
  ablate.py                 per-optimization attribution by ablation
  cprofile_report.py        Python-level hot-function ranking

results/                    perf logs, flame graphs, pyperf JSON, profiles
```

## Running it

On the course VM (**inside the QEMU guest**, not on the naranja host):

```bash
./script_pyflate.sh all
```

```bash
./script_raytrace.sh all
```

Or one stage at a time — `setup`, `verify`, `bench`, `profile`, `hw`.

`setup` installs dependencies and then **checks the two environment hazards**
that would otherwise silently corrupt the results:

- **PMU counters inside QEMU.** Hardware events (`cycles`, `cache-misses`) are
  often unavailable in a KVM guest. The script detects this and tells you to
  run the cache/IPC analysis on the naranja host instead, keeping guest and
  host numbers labelled separately.
- **`perf` cannot see Python function names on CPython 3.10.** The `-X perf`
  trampoline only exists in 3.12+, so `perf` attributes samples to
  `_PyEval_EvalFrameDefault` rather than to `find_next_symbol`. The scripts
  therefore always emit `cProfile` output for Python-level attribution and use
  `perf` for the microarchitectural *why* — which is the flame-graph-plus-
  counters methodology from the lectures anyway.

## Correctness is a gate, not a footnote

Timing is never reported without passing `tools/verify.py` first.

```bash
python tools/verify.py
```

- **pyflate** — all 399,360 decompressed bytes compared against the baseline,
  plus the benchmark's own MD5 (`afa004a630fe072901b1d9628b960974`).
- **raytrace** — the full 30,000-byte RGB framebuffer compared byte for byte.
  Every optimized floating-point expression preserves the baseline's operand
  order and grouping, so no result differs even in the last ulp.

## Hardware verification without silicon

Two independent checks, since there is no board:

```bash
python hw/pyflate_decoder/golden_model.py
```

Reimplements `huffman_decoder.v`'s decision function — parallel compare across
all 20 code lengths, priority-encode the shortest match — bit for bit in
Python, then decodes the real benchmark file through it. All **148,271** symbols
in the workload decode correctly and the output MD5 matches, so the parallel
formulation is equivalent to the serial canonical loop.

```bash
python hw/raytrace_mac/sqrt_model.py
```

Measures the truncating 24-stage square root against `math.sqrt` over 6,008
samples: **1.16 ulp** worst case, versus **0.69 ulp** for a 25-stage rounding
variant. That is why the report states the raytrace accelerator is *not*
bit-exact while the pyflate one is.

Then the RTL itself, under `iverilog` (installed by `setup`):

```bash
./script_pyflate.sh hw
```

```bash
./script_raytrace.sh hw
```

## Headline findings

**`pyflate` — the obvious diagnosis was wrong.** `find_next_symbol()` scans a
sorted table linearly, so the natural conclusion is "the scan is too deep". The
profile says otherwise: 148,271 calls to `find_next_symbol` produced only
341,601 `snoopbits` calls, a ratio of **2.3**, not ~250 — move-to-front keeps
the hot symbols at short codes, so the scan almost always exits immediately.
The real cost was that decoding one symbol took roughly **seven Python function
calls**. The fix was to remove calls, not iterations: canonical `limit/base/perm`
decoding with the bit cursor inlined into locals, cutting **3.19M calls to
583K**.

**`raytrace` — the biggest win was a three-line bug fix.** `_lightIsVisible()`
constructed the same shadow ray — `sqrt` included — once per object, inside the
loop, though it depends on nothing in it. Hoisting it is worth **46%**.
Meanwhile eliminating ~200,000 allocations per frame, the thing one instinctively
reaches for, was worth only **10%**; 500,000 `mustBeVector()` type assertions
cost far more than the arithmetic they guarded.

Both findings came from ablation (`tools/ablate.py`), which reverts one
optimization at a time from the finished build. Marginal costs deliberately do
**not** sum to the total — the optimizations interact — so the tables are
presented as a ranking, not a decomposition.

## Branches

Work is split per benchmark, as the two tracks are independent:

- `bench/pyflate` — decoder optimization and the dataflow accelerator
- `bench/raytrace` — renderer optimization and the systolic accelerator
- `main` — integration, shared tooling, reports
