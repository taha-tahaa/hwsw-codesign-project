#!/usr/bin/env python3
"""Golden model for fp32_sqrt in ray_sphere_array.v.

Reimplements the RTL's restoring bit-by-bit square root exactly - same
radicand scaling, same number of stages, same truncation - and measures the
error against math.sqrt() so the accuracy claim in report_raytrace.txt is a
measurement rather than an estimate.

Also quantifies the rounding variant (25 stages + incrementer) so the
accuracy/area trade-off in the report is backed by numbers.

Usage:  python hw/raytrace_mac/sqrt_model.py
"""

import math
import random
import struct
import sys

ULP = 2.0 ** -23


def f2b(f):
    return struct.unpack('>I', struct.pack('>f', f))[0]


def b2f(b):
    return struct.unpack('>f', struct.pack('>I', b))[0]


def hw_sqrt(xf, stages=24, do_round=False):
    """One pass of fp32_sqrt, bit for bit as the RTL computes it."""
    x = f2b(xf)
    ex = (x >> 23) & 0xFF
    mx = x & 0x7FFFFF
    if ex == 0:                       # subnormal / zero -> flushed
        return 0.0
    if ex == 0xFF:
        return float('nan') if mx else float('inf')
    if x >> 31:
        return float('nan')

    E = ex - 127
    odd = E & 1
    extra = 2 * (stages - 24)
    width = 48 + extra
    rad = (0x800000 | mx) << ((24 if odd else 23) + extra)
    exp_out = (E - odd) >> 1

    rem = 0
    root = 0
    for _ in range(stages):
        rem = (rem << 2) | ((rad >> (width - 2)) & 3)
        rad = (rad << 2) & ((1 << width) - 1)
        trial = (root << 2) | 1
        if rem >= trial:
            rem -= trial
            root = (root << 1) | 1
        else:
            root <<= 1

    if do_round:
        guard = root & 1
        root >>= 1
        if guard and (rem != 0 or (root & 1)):
            root += 1
        if root >> 24:
            root >>= 1
            exp_out += 1

    return b2f(((exp_out + 127) << 23) | (root & 0x7FFFFF))


def sweep(stages, do_round, values):
    worst = 0.0
    worst_at = None
    for v in values:
        got = hw_sqrt(v, stages, do_round)
        ref = math.sqrt(v)
        rel = abs(got - ref) / ref
        if rel > worst:
            worst, worst_at = rel, v
    return worst, worst_at


if __name__ == "__main__":
    random.seed(7)
    values = [1.0, 2.0, 4.0, 0.25, 9.0, 3.14159, 1e-8, 1e8]
    values += [random.uniform(1e-6, 1e6) for _ in range(6000)]

    print("fp32_sqrt golden model  (%d samples)" % len(values))
    print()
    for stages, rnd, label in ((24, False, "24 stages, truncating (as built)"),
                               (25, True, "25 stages + round-to-nearest")):
        worst, at = sweep(stages, rnd, values)
        print("  %-34s worst %.4e rel = %.2f ulp  (at x=%g)"
              % (label, worst, worst / ULP, at))
    print()
    print("  Exact cases (must be bit-exact):")
    ok = True
    for v in (1.0, 4.0, 9.0, 16.0, 0.25):
        got = hw_sqrt(v)
        ref = math.sqrt(v)
        flag = "ok" if got == ref else "MISMATCH"
        if got != ref:
            ok = False
        print("    sqrt(%-6g) = %-12r expected %-12r %s" % (v, got, ref, flag))
    sys.exit(0 if ok else 1)
