NOT THE SUBMITTED RESULT - host cross-check only
================================================

These numbers were measured on the naranja7 HOST, outside the QEMU guest.

The course rule is that all work happens inside the provided QEMU image and
nowhere else. An earlier revision of this project measured on the host, which
violated that rule. Everything was re-measured inside the guest; those are the
submitted numbers and they live in ../results_qemu/.

This directory is kept for one reason: the speedup ratios turn out to be
largely platform-independent, and that is worth knowing.

                     host (naranja7)        guest (QEMU)      submitted
    pyflate          733 -> 309 ms          1115 -> 445 ms    guest
                     2.38x                  2.51x
    raytrace         554 -> 217 ms           809 -> 282 ms    guest
                     2.55x                  2.87x

The guest is slower in absolute terms (CPython 3.10 versus 3.12, and
virtualization overhead) and the speedups are LARGER there, because the
baseline's call-heavy code suffers more on the older interpreter - so removing
calls helps more.

Two things the host could do that the guest cannot, which is why the earlier
revision preferred it - and why preferring it was still the wrong call:

  * CPython 3.12 supports the -X perf trampoline, so perf resolves Python
    function names directly. In the guest (3.10) that is impossible, and
    py-spy does the job instead.
  * perf hardware SAMPLING works on the host. In the guest only COUNTING
    works, so flame graphs there use -e cpu-clock.

Neither difference changes any conclusion in the reports.
