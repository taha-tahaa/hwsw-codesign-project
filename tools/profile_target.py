#!/usr/bin/env python3
"""A single, clean workload run for `perf record` to sample.

Why this exists instead of profiling the pyperf module directly: `pyperf`
(and `pyperformance`) fork a worker process and re-exec the interpreter, so
`perf record` on the parent samples process machinery rather than the
benchmark, and the worker may not even be the interpreter you meant to profile.
This runs the workload in THIS process, so every sample belongs to the code
under study.

Pair it with CPython's perf trampoline to get Python function names in the
flame graph (CPython 3.12+ only):

    python3 -X perf tools/profile_target.py pyflate baseline 5

On CPython 3.10 - which is what the course QEMU guest ships - `-X perf` does
not exist and perf will attribute samples to interpreter internals instead
(_PyEval_EvalFrameDefault, PyObject_Vectorcall).  Use tools/cprofile_report.py
for Python-level attribution there.

Usage:  profile_target.py <pyflate|raytrace> <baseline|optimized> [iterations]
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def make_pyflate(variant):
    import io
    d = os.path.join(ROOT, "benchmarks", "pyflate")
    with open(os.path.join(d, "data", "interpreter.tar.bz2"), "rb") as fp:
        data = fp.read()
    mod = load("pyflate_" + variant,
               os.path.join(d, "pyflate_%s.py" % variant))
    if variant == "baseline":
        def run():
            field = mod.RBitfield(io.BytesIO(data))
            field.readbits(16)
            return mod.bzip2_main(field)
    else:
        def run():
            return mod.decompress(data)
    return run


def make_raytrace(variant, width=100, height=100):
    d = os.path.join(ROOT, "benchmarks", "raytrace")
    mod = load("raytrace_" + variant,
               os.path.join(d, "raytrace_%s.py" % variant))
    if variant == "baseline":
        def run():
            c = mod.Canvas(width, height)
            s = mod.Scene()
            s.addLight(mod.Point(30, 30, 10))
            s.addLight(mod.Point(-10, 100, 30))
            s.lookAt(mod.Point(0, 3, 0))
            s.addObject(mod.Sphere(mod.Point(1, 3, -10), 2),
                        mod.SimpleSurface(baseColour=(1, 1, 0)))
            for y in range(6):
                s.addObject(mod.Sphere(mod.Point(-3 - y * 0.4, 2.3, -5), 0.4),
                            mod.SimpleSurface(
                                baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
            s.addObject(mod.Halfspace(mod.Point(0, 0, 0), mod.Vector.UP),
                        mod.CheckerboardSurface())
            s.render(c)
            return c
    else:
        def run():
            return mod.render_once(width, height)
    return run


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    bench, variant = sys.argv[1], sys.argv[2]
    iters = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    if bench == "pyflate":
        run = make_pyflate(variant)
    elif bench == "raytrace":
        run = make_raytrace(variant)
    else:
        sys.exit("unknown benchmark: %s" % bench)

    for _ in range(iters):
        run()


if __name__ == "__main__":
    main()
