#!/usr/bin/env python3
"""Rank Python functions by self time from a folded/collapsed perf stack file.

The flame graph SVG is the picture; this is the same data as a table, which is
what actually goes in a report.  It only works when CPython's perf trampoline
was active during recording (python3 -X perf, 3.12+), because that is what puts
`py::<function>:<file>` frames into the stacks.

Produce the input with:

    perf script -i perf.data | FlameGraph/stackcollapse-perf.pl > folded.txt

Then:

    python3 tools/flame_top.py folded.txt [N]

"Self" time is attributed to the DEEPEST py:: frame on each stack, so
interpreter frames (_PyEval_EvalFrameDefault, PyObject_Vectorcall) are folded
into the Python function that caused them - which is the attribution you want
when deciding what to optimize.
"""

import collections
import os
import sys


def load(path):
    total = 0
    self_time = collections.Counter()
    interp_only = 0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line:
            continue
        stack, _, cnt = line.rpartition(" ")
        try:
            count = int(cnt)
        except ValueError:
            continue
        total += count
        py = [f for f in stack.split(";") if f.startswith("py::")]
        if py:
            # deepest Python frame; strip the ":<path>" suffix
            name = py[-1][4:]
            name = name.split(":")[0]
            self_time[name] += count
        else:
            interp_only += count
    return total, self_time, interp_only


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 12

    total, self_time, interp_only = load(path)
    if not total:
        sys.exit("no samples found in %s" % path)

    print("%s  (%d samples)" % (os.path.basename(path), total))
    print("  %-42s %8s" % ("python function", "self"))
    print("  " + "-" * 52)
    for name, count in self_time.most_common(top):
        print("  %-42s %7.2f%%" % (name[:42], 100.0 * count / total))
    if interp_only:
        print("  %-42s %7.2f%%" % ("(no python frame: interpreter/startup)",
                                   100.0 * interp_only / total))


if __name__ == "__main__":
    main()
