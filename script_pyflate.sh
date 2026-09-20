#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# script_pyflate.sh - full pipeline for the pyflate benchmark
#
# HW/SW Co-design (00460882) final project.
#
# RUN THIS INSIDE THE COURSE QEMU GUEST.  The course rule is that all work
# happens in the provided image and nowhere else.  Boot it from /scratch on
# your assigned naranja host:
#
#   cd /scratch/$USER
#   qemu-img create -f qcow2 -b jammy-server-cloudimg-amd64-disk-kvm.img \
#                   -F qcow2 work.qcow2      # overlay: never write the original
#   qemu-system-x86_64 -m 4096 -smp 8 -cpu host,pmu=on -accel kvm \
#       -nographic -nic user,model=virtio-net-pci \
#       -drive file=work.qcow2,format=qcow2
#   # login root / ubuntu
#
# pmu=on matters: without it the guest has NO vPMU and perf answers
# <not supported> for every hardware event.
#
#   ./script_pyflate.sh              # everything
#   ./script_pyflate.sh setup        # dependencies + what perf can do here
#   ./script_pyflate.sh verify       # correctness gate
#   ./script_pyflate.sh bench        # baseline + optimized + comparison + ablation
#   ./script_pyflate.sh profile      # perf stat, flame graphs, attribution
#   ./script_pyflate.sh hw           # golden model + RTL simulation
# ---------------------------------------------------------------------------
set -uo pipefail

BENCH=pyflate
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="$ROOT/results_qemu"
PYBIN=python3
SRC="$ROOT/benchmarks/$BENCH"
CPU=2                     # pin to one vcpu

mkdir -p "$RESULTS"

# The guest runs as root, so no sudo is needed.  Use it only if not root.
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

in_guest() { [ "$(systemd-detect-virt 2>/dev/null)" = "kvm" ]; }

# ---------------------------------------------------------------------------
setup() {
    if ! in_guest; then
        echo "!! systemd-detect-virt does not report kvm."
        echo "!! The course requires all work inside the provided QEMU image."
        echo "!! See the header of this script for how to boot it."
        echo
    fi
    echo "== dependencies =="
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq python3-pip python3-dbg iverilog git curl || true
    $PYBIN -m pip install --quiet pyperf py-spy || true

    [ -d "$ROOT/tools/FlameGraph" ] || \
        git clone --depth 1 -q https://github.com/brendangregg/FlameGraph \
            "$ROOT/tools/FlameGraph" 2>/dev/null || true

    echo "== environment =="
    echo -n "  virtualization : "; (systemd-detect-virt 2>/dev/null || echo unknown)
    echo -n "  distro         : "; (. /etc/os-release; echo "$PRETTY_NAME")
    echo -n "  kernel         : "; uname -r
    echo -n "  python3        : "; $PYBIN --version
    echo -n "  pyperf         : "; $PYBIN -c 'import pyperf;print(".".join(map(str,pyperf.VERSION)))' 2>/dev/null || echo MISSING
    echo -n "  perf           : "; (perf --version 2>&1 | head -1) || echo MISSING
    echo -n "  iverilog       : "; (iverilog -V 2>&1 | head -1) || echo MISSING
    echo -n "  py-spy         : "; (py-spy --version 2>&1) || echo MISSING

    echo "== what perf can and cannot do in this guest =="
    echo -n "  hardware COUNTING      : "
    if perf stat -e cycles true 2>&1 | grep -q "not supported"; then
        echo "NO   -> was qemu started with -cpu host,pmu=on ?"
    else
        echo "yes  (cycles counts)"
    fi
    echo -n "  hardware SAMPLING      : "
    perf record -F 999 -g -o /tmp/_probe.data -- true >/dev/null 2>&1
    if perf report -i /tmp/_probe.data --stdio 2>&1 | grep -q "no samples"; then
        echo "NO   -> flame graphs use -e cpu-clock instead"
    else
        echo "yes"
    fi
    rm -f /tmp/_probe.data
    echo -n "  python names in perf   : "
    if $PYBIN -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)'; then
        echo "yes  (-X perf, CPython 3.12+)"
    else
        echo "NO on $($PYBIN --version 2>&1)  -> py-spy / cProfile give those"
    fi
}

# ---------------------------------------------------------------------------
verify() {
    echo "== correctness gate =="
    "$PYBIN" "$ROOT/tools/verify.py" $BENCH

    # The gate above compares against the baseline on the one input the
    # benchmark ships.  This compares against libbz2 - an oracle we did not
    # write - on inputs the benchmark never produces.
    echo "== extended correctness (independent oracle) =="
    "$PYBIN" "$ROOT/tools/verify_extra.py" $BENCH
}

# ---------------------------------------------------------------------------
bench() {
    for v in baseline optimized; do
        echo "== $v =="
        taskset -c $CPU "$PYBIN" "$SRC/${BENCH}_${v}.py" \
            -o "$RESULTS/${BENCH}_${v}.json" --rigorous 2>&1 | tail -1
    done

    echo "== comparison =="
    "$PYBIN" -m pyperf compare_to \
        "$RESULTS/${BENCH}_baseline.json" \
        "$RESULTS/${BENCH}_optimized.json" --table \
        | tee "$RESULTS/${BENCH}_compare.txt"
    "$PYBIN" -m pyperf compare_to \
        "$RESULTS/${BENCH}_baseline.json" \
        "$RESULTS/${BENCH}_optimized.json" -v \
        | tee -a "$RESULTS/${BENCH}_compare.txt"

    echo "== per-optimization attribution (ablation) =="
    taskset -c $CPU "$PYBIN" "$ROOT/tools/ablate.py" $BENCH 5 \
        | tee "$RESULTS/${BENCH}_ablation.txt"
}

# ---------------------------------------------------------------------------
profile() {
    echo "== perf stat, events in GROUPS OF TWO =="
    # The guest vPMU has fewer usable counters than the host: asking for six
    # events in one run makes one read exactly 0, which looks like
    # "unsupported" but is really counter multiplexing.
    : > "$RESULTS/perfstat_${BENCH}.txt"
    for v in baseline optimized; do
        echo "--- $BENCH $v ---" | tee -a "$RESULTS/perfstat_${BENCH}.txt"
        for grp in "cycles,instructions" \
                   "cache-references,cache-misses" \
                   "branch-instructions,branch-misses"; do
            taskset -c $CPU perf stat -e "$grp" \
                -- "$PYBIN" "$ROOT/tools/profile_target.py" $BENCH "$v" 3 2>&1 \
              | grep -E "cycles|instructions|cache-|branch-|insn per|elapsed" \
              | sed 's/^/    /' | tee -a "$RESULTS/perfstat_${BENCH}.txt"
        done
    done

    echo "== perf flame graphs (cpu-clock) =="
    # Sampling a HARDWARE event captures 0 samples in this guest even though
    # perf stat counts the same event.  cpu-clock is timer-based and works.
    FG="$ROOT/tools/FlameGraph"
    for v in baseline optimized; do
        taskset -c $CPU perf record -e cpu-clock -F 999 -g \
            -o "$RESULTS/${BENCH}_${v}.data" \
            -- "$PYBIN" "$ROOT/tools/profile_target.py" $BENCH "$v" 3 >/dev/null 2>&1
        if [ -x "$FG/stackcollapse-perf.pl" ]; then
            perf script -i "$RESULTS/${BENCH}_${v}.data" 2>/dev/null \
              | "$FG/stackcollapse-perf.pl" > "$RESULTS/collapsed_${BENCH}_${v}.txt"
            "$FG/flamegraph.pl" --title "$BENCH $v (QEMU guest, perf cpu-clock)" \
              "$RESULTS/collapsed_${BENCH}_${v}.txt" \
              > "$RESULTS/flamegraph_perf_${BENCH}_${v}.svg"
            echo "  flamegraph_perf_${BENCH}_${v}.svg"
        fi
    done

    echo "== py-spy flame graphs (PYTHON-level, no -X perf needed) =="
    if command -v py-spy >/dev/null 2>&1; then
        for v in baseline optimized; do
            py-spy record --rate 999 --nonblocking --format flamegraph \
                -o "$RESULTS/flamegraph_pyspy_${BENCH}_${v}.svg" \
                -- "$PYBIN" "$ROOT/tools/profile_target.py" $BENCH "$v" 3 >/dev/null 2>&1
            py-spy record --rate 999 --nonblocking --format raw \
                -o "$RESULTS/pyspy_${BENCH}_${v}.folded" \
                -- "$PYBIN" "$ROOT/tools/profile_target.py" $BENCH "$v" 3 >/dev/null 2>&1
            echo "  flamegraph_pyspy_${BENCH}_${v}.svg"
        done
    else
        echo "  py-spy not installed - run setup"
    fi

    echo "== cProfile call counts =="
    "$PYBIN" "$ROOT/tools/cprofile_report.py" $BENCH "$RESULTS"
}

# ---------------------------------------------------------------------------
hw() {
    echo "== golden model =="
    "$PYBIN" "$ROOT/hw/pyflate_decoder/golden_model.py"

    if ! command -v iverilog >/dev/null 2>&1; then
        echo "  iverilog not installed - run setup"
        return 0
    fi
    echo "== RTL simulation =="
    cd "$ROOT/hw/pyflate_decoder"
    iverilog -g2012 -o /tmp/tb_huff tb_huffman_decoder.v huffman_decoder.v && vvp /tmp/tb_huff
    iverilog -g2012 -o /tmp/tb_win  tb_bit_window.v bit_window.v && vvp /tmp/tb_win
    iverilog -g2012 -o /tmp/tb_mtf  tb_mtf_unit.v mtf_bwt_engine.v && vvp /tmp/tb_mtf
    iverilog -g2012 -o /tmp/tb_run  tb_run_expander.v rle_stages.v mtf_bwt_engine.v && vvp /tmp/tb_run
    iverilog -g2012 -o /tmp/tb_rle  tb_rle_final.v rle_stages.v && vvp /tmp/tb_rle
    iverilog -g2012 -o /tmp/tb_bib  tb_bwt_index_builder.v bwt_index_builder.v && vvp /tmp/tb_bib
    iverilog -g2012 -o /tmp/tb_rev  tb_bwt_reverse.v mtf_bwt_engine.v && vvp /tmp/tb_rev

    # End to end: the whole accelerator decompressing one block.  Vectors are
    # generated by running the bzip2 encoder in Python, so the testbench and
    # the software decoder agree by construction.
    "$PYBIN" gen_top_vectors.py > /tmp/tb_top_block.v
    iverilog -g2012 -o /tmp/tb_top /tmp/tb_top_block.v bzip2_accel_top.v \
        huffman_decoder.v bit_window.v mtf_bwt_engine.v bwt_index_builder.v \
        rle_stages.v && vvp /tmp/tb_top
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
