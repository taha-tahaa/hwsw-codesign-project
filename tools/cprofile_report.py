#!/usr/bin/env python3
"""Python-level hot-function attribution for both benchmarks.

Why this exists alongside perf: on Ubuntu 22.04 the guest runs CPython 3.10,
which predates the `-X perf` trampoline (3.12+).  perf therefore attributes
samples to interpreter internals - _PyEval_EvalFrameDefault and friends - not
to find_next_symbol() or intersectionTime().  cProfile closes that gap.

Read together they are exactly the lecture-4 methodology:
  flame graph / perf  ->  WHERE the machine is spending cycles
  cProfile            ->  WHICH Python function is responsible
  perf counters       ->  WHY (cache misses, IPC, branch misses)

cProfile inflates call-heavy code (its own per-call overhead), so the absolute
times here are NOT the benchmark result - pyperf provides those.  Use this for
ranking functions, not for reporting speedups.

Usage:  python tools/cprofile_report.py [pyflate|raytrace|all] [outdir]
"""

import cProfile
import importlib.util
import io
import os
import pstats
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def profile_to(fn, out_path, top=15):
    pr = cProfile.Profile()
    pr.enable()
    fn()
    pr.disable()
    buf = io.StringIO()
    pstats.Stats(pr, stream=buf).sort_stats("tottime").print_stats(top)
    with open(out_path, "w") as fp:
        fp.write(buf.getvalue())
    return buf.getvalue()


def runners_pyflate():
    import io as _io
    d = os.path.join(ROOT, "benchmarks", "pyflate")
    with open(os.path.join(d, "data", "interpreter.tar.bz2"), "rb") as fp:
        data = fp.read()

    base = load("pyflate_baseline", os.path.join(d, "pyflate_baseline.py"))
    opt = load("pyflate_optimized", os.path.join(d, "pyflate_optimized.py"))

    def run_baseline():
        field = base.RBitfield(_io.BytesIO(data))
        field.readbits(16)
        return base.bzip2_main(field)

    def run_optimized():
        return opt.decompress(data)

    return {"baseline": run_baseline, "optimized": run_optimized}


def runners_raytrace(width=100, height=100):
    d = os.path.join(ROOT, "benchmarks", "raytrace")
    base = load("raytrace_baseline", os.path.join(d, "raytrace_baseline.py"))
    opt = load("raytrace_optimized", os.path.join(d, "raytrace_optimized.py"))

    def run_baseline():
        c = base.Canvas(width, height)
        s = base.Scene()
        s.addLight(base.Point(30, 30, 10))
        s.addLight(base.Point(-10, 100, 30))
        s.lookAt(base.Point(0, 3, 0))
        s.addObject(base.Sphere(base.Point(1, 3, -10), 2),
                    base.SimpleSurface(baseColour=(1, 1, 0)))
        for y in range(6):
            s.addObject(base.Sphere(base.Point(-3 - y * 0.4, 2.3, -5), 0.4),
                        base.SimpleSurface(baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
        s.addObject(base.Halfspace(base.Point(0, 0, 0), base.Vector.UP),
                    base.CheckerboardSurface())
        s.render(c)

    def run_optimized():
        opt.render_once(width, height)

    return {"baseline": run_baseline, "optimized": run_optimized}


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "results")
    os.makedirs(outdir, exist_ok=True)

    targets = []
    if which in ("all", "pyflate"):
        targets.append(("pyflate", runners_pyflate()))
    if which in ("all", "raytrace"):
        targets.append(("raytrace", runners_raytrace()))

    for bench, runners in targets:
        for variant, fn in runners.items():
            path = os.path.join(outdir, "cprofile_%s_%s.txt" % (bench, variant))
            text = profile_to(fn, path)
            print("=== %s / %s ===" % (bench, variant))
            print("\n".join(text.splitlines()[:12]))
            print("  full listing -> %s\n" % path)


if __name__ == "__main__":
    main()
