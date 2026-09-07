#!/usr/bin/env python3
"""Correctness gate: the optimized code must produce identical output.

pyflate  - MD5 of the decompressed stream must equal the benchmark's own
           expected digest, and must equal the baseline's output byte for byte.
raytrace - the full RGB framebuffer must match the baseline byte for byte.

Exits non-zero on any mismatch so script_*.sh can fail loudly.
"""

import hashlib
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYFLATE_MD5 = "afa004a630fe072901b1d9628b960974"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def check_pyflate():
    d = os.path.join(ROOT, "benchmarks", "pyflate")
    base = load("pyflate_baseline", os.path.join(d, "pyflate_baseline.py"))
    opt = load("pyflate_optimized", os.path.join(d, "pyflate_optimized.py"))

    data_path = os.path.join(d, "data", "interpreter.tar.bz2")
    with open(data_path, "rb") as fp:
        raw = fp.read()

    import io
    fp = io.BytesIO(raw)
    field = base.RBitfield(fp)
    field.readbits(16)
    base_out = base.bzip2_main(field)

    opt_out = opt.decompress(raw)

    base_md5 = hashlib.md5(base_out).hexdigest()
    opt_md5 = hashlib.md5(opt_out).hexdigest()

    ok = True
    print("pyflate")
    print("  baseline  : %d bytes, md5 %s" % (len(base_out), base_md5))
    print("  optimized : %d bytes, md5 %s" % (len(opt_out), opt_md5))
    print("  expected  : %s" % PYFLATE_MD5)
    if base_md5 != PYFLATE_MD5:
        print("  FAIL: baseline does not match the benchmark's expected digest")
        ok = False
    if opt_out != base_out:
        print("  FAIL: optimized output differs from baseline")
        # Locate the first difference to make debugging possible.
        n = min(len(base_out), len(opt_out))
        for i in range(n):
            if base_out[i] != opt_out[i]:
                print("        first difference at byte %d: %r vs %r"
                      % (i, base_out[i], opt_out[i]))
                break
        else:
            print("        identical prefix, lengths differ: %d vs %d"
                  % (len(base_out), len(opt_out)))
        ok = False
    if ok:
        print("  PASS: byte-identical")
    return ok


def check_raytrace(width=100, height=100):
    d = os.path.join(ROOT, "benchmarks", "raytrace")
    base = load("raytrace_baseline", os.path.join(d, "raytrace_baseline.py"))
    opt = load("raytrace_optimized", os.path.join(d, "raytrace_optimized.py"))

    # Baseline scene setup, transcribed verbatim from bench_raytrace().
    bc = base.Canvas(width, height)
    bs = base.Scene()
    bs.addLight(base.Point(30, 30, 10))
    bs.addLight(base.Point(-10, 100, 30))
    bs.lookAt(base.Point(0, 3, 0))
    bs.addObject(base.Sphere(base.Point(1, 3, -10), 2),
                 base.SimpleSurface(baseColour=(1, 1, 0)))
    for y in range(6):
        bs.addObject(base.Sphere(base.Point(-3 - y * 0.4, 2.3, -5), 0.4),
                     base.SimpleSurface(baseColour=(y / 6.0, 1 - y / 6.0, 0.5)))
    bs.addObject(base.Halfspace(base.Point(0, 0, 0), base.Vector.UP),
                 base.CheckerboardSurface())
    bs.render(bc)

    oc = opt.render_once(width, height)

    a = bc.bytes.tobytes()
    b = oc.bytes.tobytes()

    print("raytrace (%dx%d)" % (width, height))
    print("  baseline  : %d bytes, md5 %s" % (len(a), hashlib.md5(a).hexdigest()))
    print("  optimized : %d bytes, md5 %s" % (len(b), hashlib.md5(b).hexdigest()))
    if a != b:
        diffs = sum(1 for i in range(min(len(a), len(b))) if a[i] != b[i])
        print("  FAIL: framebuffers differ in %d of %d bytes" % (diffs, len(a)))
        for i in range(min(len(a), len(b))):
            if a[i] != b[i]:
                print("        first difference at byte %d: %d vs %d"
                      % (i, a[i], b[i]))
                break
        return False
    print("  PASS: bit-identical image")
    return True


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    results = []
    if which in ("all", "pyflate"):
        results.append(check_pyflate())
    if which in ("all", "raytrace"):
        results.append(check_raytrace())
    print()
    if all(results) and results:
        print("ALL CORRECTNESS CHECKS PASSED")
        sys.exit(0)
    print("CORRECTNESS CHECKS FAILED")
    sys.exit(1)
