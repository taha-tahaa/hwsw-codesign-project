#!/usr/bin/env python3
"""Per-optimization attribution by ablation.

Starts from the fully optimized module and reverts ONE optimization at a time
(restoring the baseline implementation of that piece), then measures the cost.
The "marginal cost" column is therefore: how much slower the program gets if
that single optimization is taken away, everything else left in place.

Marginal costs do not sum to the total speedup - the optimizations interact,
and removing one can shift work onto another.  The table is read as a ranking
of importance, not as an additive decomposition.  This is stated in the reports.

Usage:  python tools/ablate.py [pyflate|raytrace|all] [repeats]
"""

import importlib.util
import os
import statistics
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def measure(fn, repeats):
    """Best-of-N wall time.  Best-of is used rather than mean because we are
    isolating a code change on a noisy desktop; the minimum is the run least
    perturbed by unrelated system activity."""
    times = []
    for _ in range(repeats):
        t0 = time.perf_counter()
        fn()
        times.append(time.perf_counter() - t0)
    return min(times), statistics.median(times)


# ---------------------------------------------------------------------------
# pyflate
# ---------------------------------------------------------------------------

def ablate_pyflate(repeats):
    d = os.path.join(ROOT, "benchmarks", "pyflate")
    data = open(os.path.join(d, "data", "interpreter.tar.bz2"), "rb").read()

    base = load("pyflate_baseline", os.path.join(d, "pyflate_baseline.py"))
    opt = load("pyflate_optimized", os.path.join(d, "pyflate_optimized.py"))

    import io

    def run_baseline():
        fp = io.BytesIO(data)
        field = base.RBitfield(fp)
        field.readbits(16)
        return base.bzip2_main(field)

    def run_opt():
        return opt.decompress(data)

    rows = []
    b_min, _ = measure(run_baseline, repeats)
    o_min, _ = measure(run_opt, repeats)
    rows.append(("baseline (all optimizations off)", b_min, None))
    rows.append(("fully optimized", o_min, None))

    fast_bwt = opt.bwt_reverse

    # --- revert O3: inverse BWT back to sorted(L) + 256 find() scans --------
    int2byte = base.int2byte

    def slow_bwt_reverse(L, end):
        out = []
        if len(L):
            F = bytes(sorted(L))
            bse = []
            for i in range(256):
                bse.append(F.find(int2byte(i)))
            pointers = [-1] * len(L)
            for i, symbol in enumerate(L):
                pointers[bse[symbol]] = i
                bse[symbol] += 1
            T = pointers
            for i in range(len(L)):
                end = T[end]
                out.append(L[end])
        return bytes(out)

    opt.bwt_reverse = slow_bwt_reverse
    t, _ = measure(run_opt, repeats)
    rows.append(("  without O3 (inverse BWT)", t, t - o_min))
    opt.bwt_reverse = fast_bwt

    # Sanity: restoring the fast path must reproduce the optimized timing.
    assert opt.bwt_reverse is fast_bwt
    return rows


# ---------------------------------------------------------------------------
# raytrace
# ---------------------------------------------------------------------------

def ablate_raytrace(repeats, width=100, height=100):
    d = os.path.join(ROOT, "benchmarks", "raytrace")
    base = load("raytrace_baseline", os.path.join(d, "raytrace_baseline.py"))
    opt = load("raytrace_optimized", os.path.join(d, "raytrace_optimized.py"))

    def build_baseline_scene():
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
        return s

    def run_baseline():
        c = base.Canvas(width, height)
        build_baseline_scene().render(c)

    def run_opt():
        opt.render_once(width, height)

    rows = []
    b_min, _ = measure(run_baseline, repeats)
    o_min, _ = measure(run_opt, repeats)
    rows.append(("baseline (all optimizations off)", b_min, None))
    rows.append(("fully optimized", o_min, None))

    Ray = opt.Ray
    EPS = opt.EPSILON

    # --- revert O1: rebuild the shadow ray inside the object loop ----------
    fast_vis = opt.Scene._lightIsVisible

    def slow_lightIsVisible(self, l, p):
        for (o, s) in self.objects:
            t = o.intersectionTime(Ray(p, l - p))
            if t is not None and t > EPS:
                return False
        return True

    opt.Scene._lightIsVisible = slow_lightIsVisible
    t, _ = measure(run_opt, repeats)
    rows.append(("  without O1 (shadow-ray hoist)", t, t - o_min))
    opt.Scene._lightIsVisible = fast_vis

    # --- revert O2: per-ray intersection list + firstIntersection ----------
    fast_colour = opt.Scene.rayColour
    firstIntersection = opt.firstIntersection

    def slow_rayColour(self, ray):
        if self.recursionDepth > 3:
            return (0, 0, 0)
        try:
            self.recursionDepth = self.recursionDepth + 1
            intersections = [(o, o.intersectionTime(ray), s)
                             for (o, s) in self.objects]
            i = firstIntersection(intersections)
            if i is None:
                return (0, 0, 0)
            (o, t, s) = i
            p = ray.pointAtTime(t)
            return s.colourAt(self, ray, p, o.normalAt(p))
        finally:
            self.recursionDepth = self.recursionDepth - 1

    opt.Scene.rayColour = slow_rayColour
    t, _ = measure(run_opt, repeats)
    rows.append(("  without O2 (per-ray list alloc)", t, t - o_min))
    opt.Scene.rayColour = fast_colour

    # --- revert O3/O5: sphere intersection with full object arithmetic -----
    fast_isect = opt.Sphere.intersectionTime

    def slow_intersectionTime(self, ray):
        cp = self.centre - ray.point
        v = cp.dot(ray.vector)
        discriminant = (self.radius * self.radius) - (cp.dot(cp) - v * v)
        if discriminant < 0:
            return None
        return v - opt.sqrt(discriminant)

    opt.Sphere.intersectionTime = slow_intersectionTime
    t, _ = measure(run_opt, repeats)
    rows.append(("  without O3/O5 (inlined intersection)", t, t - o_min))
    opt.Sphere.intersectionTime = fast_isect

    return rows


def show(title, rows):
    print()
    print(title)
    print("-" * 68)
    print("%-40s %10s %14s" % ("variant", "best (ms)", "marginal cost"))
    print("-" * 68)
    for name, t, delta in rows:
        d = "" if delta is None else "+%.1f ms (+%.0f%%)" % (
            delta * 1000, 100.0 * delta / (t - delta))
        print("%-40s %10.1f %14s" % (name, t * 1000, d))
    print("-" * 68)


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    repeats = int(sys.argv[2]) if len(sys.argv) > 2 else 7
    if which in ("all", "pyflate"):
        show("pyflate - ablation (best of %d)" % repeats, ablate_pyflate(repeats))
    if which in ("all", "raytrace"):
        show("raytrace - ablation (best of %d)" % repeats, ablate_raytrace(repeats))
