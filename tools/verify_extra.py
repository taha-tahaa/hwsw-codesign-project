#!/usr/bin/env python3
"""Correctness beyond the single input the benchmark ships.

tools/verify.py answers "does the optimized code agree with the baseline on the
one file pyperformance feeds it?".  That is the gate, and it is not enough on
its own: both implementations could be wrong together, and one input exercises
one path.  This script answers the two harder questions.

  pyflate   Does the optimized decoder agree with libbz2 - an INDEPENDENT
            oracle we did not write - on streams the benchmark never produces?
            Empty, one byte, runs (the RLE path), highly repetitive, English
            text, incompressible random data, and a 900 KB MULTI-BLOCK file,
            each at compression levels 1 and 9: 16 streams in all.

  raytrace  Is the image bit-identical at resolutions other than the
            benchmark's 100x100?  A loop-invariant hoist or a changed
            nearest-hit tie-break can be invisible at one size and wrong at
            another, so seven sizes are rendered by both implementations and
            compared byte for byte.

Exits non-zero on any mismatch, so tools/regress.sh and script_*.sh can fail
loudly.  Runtime is a few seconds per benchmark; the 900 KB stream dominates.

Usage:  python tools/verify_extra.py [pyflate|raytrace|all]
"""

import bz2
import hashlib
import importlib.util
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 20260920          # fixed, so a failure is reproducible


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def pyflate_cases():
    rnd = random.Random(SEED)
    return [
        ("empty", b""),
        ("one byte", b"A"),
        ("1 KB of zeros", b"\x00" * 1024),
        ("runs (RLE path)", b"".join(bytes([i % 251]) * (i % 9 + 1) for i in range(4000))),
        ("highly repetitive", b"abcabcabc" * 5000),
        ("english text", b"the quick brown fox jumps over the lazy dog. " * 700),
        ("64 KB random", bytes(rnd.randrange(256) for _ in range(65536))),
        ("900 KB multi-block", bytes(rnd.randrange(256) for _ in range(900_000))),
    ]


def check_pyflate():
    d = os.path.join(ROOT, "benchmarks", "pyflate")
    opt = load("pyflate_optimized", os.path.join(d, "pyflate_optimized.py"))

    print("pyflate: optimized decoder vs libbz2 (independent oracle)")
    print("  %-22s %-6s %9s  %s" % ("input", "level", "bytes", "result"))
    ok = True
    for name, payload in pyflate_cases():
        for level in (1, 9):
            stream = bz2.compress(payload, compresslevel=level)
            try:
                out = opt.decompress(stream)
            except Exception as exc:                        # noqa: BLE001
                print("  %-22s %-6d %9d  RAISED %s: %s"
                      % (name, level, len(payload), type(exc).__name__, exc))
                ok = False
                continue
            good = out == payload
            ok &= good
            if good:
                print("  %-22s %-6d %9d  ok" % (name, level, len(payload)))
            else:
                print("  %-22s %-6d %9d  MISMATCH: %d bytes back, md5 %s vs %s"
                      % (name, level, len(payload), len(out),
                         hashlib.md5(out).hexdigest()[:8],
                         hashlib.md5(payload).hexdigest()[:8]))
    return ok


def render_baseline(base, width, height):
    """The benchmark's own scene, transcribed verbatim from bench_raytrace()."""
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
    return c.bytes.tobytes()


def check_raytrace():
    d = os.path.join(ROOT, "benchmarks", "raytrace")
    base = load("raytrace_baseline", os.path.join(d, "raytrace_baseline.py"))
    opt = load("raytrace_optimized", os.path.join(d, "raytrace_optimized.py"))

    print("raytrace: optimized image vs baseline image, seven resolutions")
    print("  %-12s %9s  %-34s %s" % ("size", "bytes", "md5", "result"))
    ok = True
    for w, h in [(2, 2), (3, 7), (16, 16), (50, 50), (100, 100), (101, 37), (128, 96)]:
        a = render_baseline(base, w, h)
        b = opt.render_once(w, h).bytes.tobytes()
        good = a == b
        ok &= good
        if good:
            print("  %-12s %9d  %-34s bit-identical"
                  % ("%dx%d" % (w, h), len(a), hashlib.md5(a).hexdigest()))
        else:
            diffs = sum(1 for i in range(min(len(a), len(b))) if a[i] != b[i])
            print("  %-12s %9d  %-34s MISMATCH: %d bytes differ"
                  % ("%dx%d" % (w, h), len(a), hashlib.md5(a).hexdigest(), diffs))
    return ok


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    results = []
    if which in ("all", "pyflate"):
        results.append(check_pyflate())
    if which in ("all", "raytrace"):
        if results:
            print()
        results.append(check_raytrace())
    print()
    if all(results) and results:
        print("EXTENDED CORRECTNESS CHECKS PASSED")
        sys.exit(0)
    print("EXTENDED CORRECTNESS CHECKS FAILED")
    sys.exit(1)
