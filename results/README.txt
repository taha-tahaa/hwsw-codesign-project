Measurement artifacts.

Everything in this directory was produced on the DEVELOPMENT machine
(CPython 3.12.1, pyperf 2.10.0, Windows 11, x86-64), not on the course VM.

They are committed as evidence for the numbers quoted in report_pyflate.txt and
report_raytrace.txt, and so the analysis can be checked without re-running
anything.

For the submission, regenerate them inside the QEMU guest:

    ./script_pyflate.sh all
    ./script_raytrace.sh all

which additionally produces the perf logs and flame graphs that cannot be made
on Windows (perf is Linux-only).

  *_baseline.json / *_optimized.json   pyperf raw results; compare with
                                       `python -m pyperf compare_to a.json b.json --table`
  cprofile_*.txt                       Python-level hot-function ranking
