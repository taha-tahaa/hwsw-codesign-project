#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tools/regress.sh - run every correctness check in the project, in one go.
#
#   ./tools/regress.sh
#
# Eleven checks: four software/model, four pyflate RTL, three raytrace RTL.
# Exits non-zero if any fails, so it can gate a commit.
#
# Needs iverilog. On the CSL hosts there is no sudo, so install it without root:
#   mkdir -p /scratch/$USER/build && cd /scratch/$USER/build
#   apt-get download iverilog && dpkg -x iverilog_*.deb $HOME/.local/iverilog-root
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="${PY:-python3}"
IVR="$HOME/.local/iverilog-root"
if [ -x "$IVR/usr/bin/iverilog" ]; then
    export PATH="$IVR/usr/bin:$PATH"
    IVL="$(find "$IVR/usr/lib" -maxdepth 3 -type d -name ivl 2>/dev/null | head -1)"
    B="-B $IVL"; M="-M $IVL"
else
    IVL=""; B=""; M=""
fi

PASS=0; FAIL=0

run() {   # run <name> <expected-substring> <command...>
    local name="$1" want="$2"; shift 2
    local out
    out=$("$@" 2>&1)
    if echo "$out" | grep -q "$want"; then
        echo "  PASS  $name"; PASS=$((PASS+1))
    else
        echo "  FAIL  $name"
        echo "$out" | tail -8 | sed 's/^/        /'
        FAIL=$((FAIL+1))
    fi
}

echo "===================== SOFTWARE ====================="
run "correctness gate (both benchmarks)" "ALL CORRECTNESS CHECKS PASSED" \
    $PY tools/verify.py
run "extended correctness (libbz2 oracle, 7 resolutions)" "EXTENDED CORRECTNESS CHECKS PASSED" \
    $PY tools/verify_extra.py
run "huffman golden model (148,271 symbols)" "PASS" \
    $PY hw/pyflate_decoder/golden_model.py
run "fp32_sqrt golden model" "ok" \
    $PY hw/raytrace_mac/sqrt_model.py

if ! command -v iverilog >/dev/null 2>&1; then
    echo
    echo "iverilog not found - skipping the seven RTL checks."
    echo "software checks: passed $PASS, failed $FAIL"
    [ $FAIL -eq 0 ] || exit 1
    exit 0
fi

echo "===================== RTL: pyflate ====================="
( cd hw/pyflate_decoder && iverilog $B -g2012 -o /tmp/rg_huff \
    tb_huffman_decoder.v huffman_decoder.v ) 2>/dev/null
run "tb_huffman_decoder" "TB PASS" vvp $M /tmp/rg_huff

( cd hw/pyflate_decoder && iverilog $B -g2012 -o /tmp/rg_win \
    tb_bit_window.v bit_window.v ) 2>/dev/null
run "tb_bit_window" "TB PASS" vvp $M /tmp/rg_win

( cd hw/pyflate_decoder && iverilog $B -g2012 -o /tmp/rg_bib \
    tb_bwt_index_builder.v bwt_index_builder.v ) 2>/dev/null
run "tb_bwt_index_builder (T[] vs software)" "TB PASS" vvp $M /tmp/rg_bib

# rm first: a stale binary from an earlier run would make a failed
# elaboration look like a pass.
rm -f /tmp/rg_top
if ( cd hw/pyflate_decoder && iverilog $B -g2012 -o /tmp/rg_top \
        bzip2_accel_top.v huffman_decoder.v bit_window.v mtf_bwt_engine.v \
        bwt_index_builder.v \
     ) 2>/dev/null && [ -f /tmp/rg_top ]; then
    echo "  PASS  bzip2_accel_top elaborates"; PASS=$((PASS+1))
else
    echo "  FAIL  bzip2_accel_top elaborates"; FAIL=$((FAIL+1))
fi

echo "===================== RTL: raytrace ====================="
( cd hw/raytrace_mac && iverilog $B -g2012 -o /tmp/rg_pe \
    tb_ray_sphere.v ray_sphere_array.v fp32_units.v ) 2>/dev/null
run "tb_ray_sphere (PE)" "TB PASS" vvp $M /tmp/rg_pe

( cd hw/raytrace_mac && iverilog $B -g2012 -o /tmp/rg_arr \
    tb_ray_array.v ray_sphere_array.v fp32_units.v ) 2>/dev/null
run "tb_ray_array (nearest-hit across 8 spheres)" "TB PASS" vvp $M /tmp/rg_arr

$PY hw/raytrace_mac/gen_fp_vectors.py 400 > /tmp/rg_fp.v
( cd hw/raytrace_mac && iverilog $B -g2012 -o /tmp/rg_fp /tmp/rg_fp.v \
    fp32_units.v ) 2>/dev/null
run "tb_fp_random (400 randomized vectors)" "TB PASS" vvp $M /tmp/rg_fp

echo
echo "===================== SUMMARY ====================="
echo "  passed: $PASS    failed: $FAIL"
if [ $FAIL -eq 0 ]; then echo "  ALL GREEN"; exit 0; fi
echo "  REGRESSIONS PRESENT"; exit 1
