#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# script_pyflate.sh - full pipeline for the pyflate benchmark
#
# HW/SW Co-design (00460882) final project.
# Run INSIDE the QEMU guest (Ubuntu 22.04), not on the naranja host.
#
#   ./script_pyflate.sh              # everything
#   ./script_pyflate.sh setup        # dependencies only
#   ./script_pyflate.sh verify       # correctness gate only
#   ./script_pyflate.sh bench        # baseline + optimized + comparison
#   ./script_pyflate.sh profile      # perf record + flame graph
#   ./script_pyflate.sh hw           # simulate the accelerator RTL
# ---------------------------------------------------------------------------
set -euo pipefail

BENCH=pyflate
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="$ROOT/results"
VENV="$ROOT/.venv"
# Prefer the project venv; fall back to the system interpreter when there is no
# venv. On the CSL hosts python3-venv is not installed and there is no sudo, so
# pyperf lives in ~/.local via `pip install --user --break-system-packages`.
if [ -x "$VENV/bin/python" ]; then PY="$VENV/bin/python"; else PY="python3"; fi
SRC="$ROOT/benchmarks/$BENCH"

mkdir -p "$RESULTS"

# ---------------------------------------------------------------------------
setup() {
    echo "== dependencies =="
    sudo apt-get update -qq
    # python3-dbg gives perf the CPython symbols the project brief asks for.
    sudo apt-get install -y -qq \
        python3-venv python3-dev python3-dbg \
        linux-tools-common "linux-tools-$(uname -r)" \
        git iverilog || true

    [ -d "$VENV" ] || python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip pyperf

    # FlameGraph fallback: `perf script report flamegraph` needs a d3 template
    # that is not always packaged, so keep Brendan Gregg's scripts around too.
    [ -d "$ROOT/tools/FlameGraph" ] || \
        git clone --depth 1 https://github.com/brendangregg/FlameGraph \
            "$ROOT/tools/FlameGraph" 2>/dev/null || \
        echo "  (FlameGraph clone skipped - no network; perf's built-in will be used)"

    echo "== environment sanity =="
    echo -n "  python3      : "; python3 --version
    echo -n "  python3-dbg  : "; (python3-dbg --version 2>&1) || echo "MISSING"
    echo -n "  perf         : "; (perf --version 2>&1) || echo "MISSING"

    # RISK 1 from the plan: hardware PMU counters are frequently unavailable
    # inside a KVM guest.  Detect it now rather than after a week of numbers.
    echo -n "  PMU counters : "
    if perf stat -e cycles true 2>&1 | grep -q "not supported"; then
        echo "NOT AVAILABLE in this guest"
        echo "     -> sampling will fall back to the cpu-clock software event."
        echo "     -> run cache-miss / IPC analysis on the naranja HOST instead,"
        echo "        and label host vs guest numbers separately in the report."
    else
        echo "available"
    fi

    # RISK 2: CPython's perf trampoline (-X perf) only exists in 3.12+.
    echo -n "  -X perf      : "
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)'; then
        echo "supported - flame graphs will carry Python function names"
    else
        echo "NOT supported on $(python3 --version 2>&1) (needs 3.12+)"
        echo "     -> perf will show CPython interpreter frames, not Python names."
        echo "     -> use py-spy or cProfile for Python-level attribution."
    fi
}

# ---------------------------------------------------------------------------
verify() {
    echo "== correctness gate =="
    # Non-negotiable: the optimized decoder must be byte-identical.
    "$PY" "$ROOT/tools/verify.py" $BENCH
}

# ---------------------------------------------------------------------------
bench() {
    echo "== baseline =="
    taskset -c 0 "$PY" "$SRC/${BENCH}_baseline.py" \
        -o "$RESULTS/${BENCH}_baseline.json" --rigorous

    echo "== optimized =="
    taskset -c 0 "$PY" "$SRC/${BENCH}_optimized.py" \
        -o "$RESULTS/${BENCH}_optimized.json" --rigorous

    echo "== comparison (pyperf reports significance, not a single run) =="
    "$PY" -m pyperf compare_to \
        "$RESULTS/${BENCH}_baseline.json" \
        "$RESULTS/${BENCH}_optimized.json" --table \
        | tee "$RESULTS/${BENCH}_compare.txt"

    echo "== per-optimization attribution (ablation) =="
    "$PY" "$ROOT/tools/ablate.py" $BENCH 7 \
        | tee "$RESULTS/${BENCH}_ablation.txt"
}

# ---------------------------------------------------------------------------
profile() {
    echo "== perf stat =="
    # Hardware events first; on a host with a real PMU (naranja7 runs with
    # perf_event_paranoid = -1) these give the CPI-stack view from lecture 4.
    # Software events are always collected too, so a missing PMU inside the
    # QEMU guest still yields usable data.
    for v in baseline optimized; do
        perf stat -e task-clock,context-switches,page-faults \
            -- "$PY" "$ROOT/tools/profile_target.py" $BENCH "$v" 5 \
            2> "$RESULTS/${BENCH}_stat_${v}.txt" || true

        perf stat -e cycles,instructions,cache-references,cache-misses,branch-instructions,branch-misses \
            -- "$PY" "$ROOT/tools/profile_target.py" $BENCH "$v" 5 \
            2> "$RESULTS/${BENCH}_stat_hw_${v}.txt" || \
            echo "  (hardware counters unavailable for $v - see setup output)"
    done

    echo "== perf record + flame graph =="
    # pyperf/pyperformance fork a worker and re-exec the interpreter, so
    # recording them samples process machinery rather than the benchmark.
    # tools/profile_target.py runs the workload in-process instead.
    # -X perf adds CPython's perf trampoline so the flame graph carries Python
    # function names; it exists only on 3.12+, hence the guard.
    XPERF=""
    if "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)'; then
        XPERF="-X perf"
    fi
    for v in baseline optimized; do
        perf record -F 999 -g \
            -o "$RESULTS/${BENCH}_${v}.data" \
            -- "$PY" $XPERF "$ROOT/tools/profile_target.py" $BENCH "$v" 5 || true

        perf report -i "$RESULTS/${BENCH}_${v}.data" --stdio \
            > "$RESULTS/report_perf_${BENCH}_${v}.txt" 2>/dev/null || true

        if [ -x "$ROOT/tools/FlameGraph/stackcollapse-perf.pl" ]; then
            perf script -i "$RESULTS/${BENCH}_${v}.data" \
                | "$ROOT/tools/FlameGraph/stackcollapse-perf.pl" \
                | "$ROOT/tools/FlameGraph/flamegraph.pl" \
                    --title "$BENCH $v" \
                > "$RESULTS/flamegraph_${BENCH}_${v}.svg"
        else
            ( cd "$RESULTS" && perf script -i "${BENCH}_${v}.data" \
                report flamegraph -o "flamegraph_${BENCH}_${v}.html" ) || true
        fi
    done

    echo "== Python-level attribution (works regardless of perf symbolization) =="
    "$PY" "$ROOT/tools/cprofile_report.py" $BENCH "$RESULTS"
}

# ---------------------------------------------------------------------------
hw() {
    echo "== accelerator: golden model (no simulator needed) =="
    "$PY" "$ROOT/hw/pyflate_decoder/golden_model.py"

    # iverilog may live in ~/.local when installed without root (no sudo on the
    # CSL hosts): apt-get download iverilog && dpkg -x iverilog_*.deb <dir>
    IVR="$HOME/.local/iverilog-root"
    IVFLAGS=""
    if [ -x "$IVR/usr/bin/iverilog" ]; then
        export PATH="$IVR/usr/bin:$PATH"
        IVL="$(find "$IVR/usr/lib" -maxdepth 3 -type d -name ivl 2>/dev/null | head -1)"
        [ -n "$IVL" ] && IVFLAGS="-B $IVL"
    fi

    if ! command -v iverilog >/dev/null 2>&1; then
        echo "  iverilog not installed - see the comment above, or run setup"
        return 0
    fi
    VV="vvp"; [ -n "${IVL:-}" ] && VV="vvp -M $IVL"

    echo "== tb_huffman_decoder =="
    ( cd "$ROOT/hw/pyflate_decoder" &&       iverilog $IVFLAGS -g2012 -o /tmp/tb_huff tb_huffman_decoder.v huffman_decoder.v )       && $VV /tmp/tb_huff

    echo "== tb_bit_window =="
    ( cd "$ROOT/hw/pyflate_decoder" &&       iverilog $IVFLAGS -g2012 -o /tmp/tb_win tb_bit_window.v bit_window.v )       && $VV /tmp/tb_win

    echo "== bzip2_accel_top elaboration =="
    ( cd "$ROOT/hw/pyflate_decoder" &&       iverilog $IVFLAGS -g2012 -o /tmp/elab_bzip2         bzip2_accel_top.v huffman_decoder.v bit_window.v mtf_bwt_engine.v       && echo "  bzip2_accel_top elaborates cleanly" )
}

# ---------------------------------------------------------------------------
case "${1:-all}" in
    setup)   setup ;;
    verify)  verify ;;
    bench)   bench ;;
    profile) profile ;;
    hw)      hw ;;
    all)     setup; verify; bench; profile; hw ;;
    *)       echo "usage: $0 [setup|verify|bench|profile|hw|all]"; exit 1 ;;
esac

echo
echo "artifacts in $RESULTS"
