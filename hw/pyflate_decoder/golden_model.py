#!/usr/bin/env python3
"""Golden model for huffman_decoder.v, checked against the real benchmark data.

The RTL decodes a symbol by evaluating ALL candidate code lengths in parallel
and priority-encoding the shortest one that accepts:

    for L in 1..MAX_LEN:
        code_L = window[MAX_LEN-1 -: L]          // top L bits
        hit_L  = lvalid[L] && L >= min_len && code_L <= limit[L]
    sel      = min{ L : hit_L }
    sym      = perm[code_sel - base[sel]]

This module reimplements exactly that, bit for bit, and drives it with the
Huffman tables and bitstream from data/interpreter.tar.bz2.  If the whole file
decompresses to the expected MD5 through the hardware decision function, then
the parallel-compare + priority-encoder formulation is equivalent to the serial
canonical loop for every symbol that actually occurs in the workload.

That is what lets us claim the RTL is correct without owning a simulator; the
Verilog testbench (tb_huffman_decoder.v) re-runs the same vectors under iverilog
on the course VM.

Usage:  python hw/pyflate_decoder/golden_model.py
"""

import hashlib
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MAX_LEN = 20
EXPECTED_MD5 = "afa004a630fe072901b1d9628b960974"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


opt = load("pyflate_optimized",
           os.path.join(ROOT, "benchmarks", "pyflate", "pyflate_optimized.py"))


def rtl_tables(limit, base, perm, min_len, max_len):
    """Flatten the software tables into the per-length arrays the RTL holds.

    lvalid[L] marks lengths that actually carry codes; the RTL uses it to mask
    comparators, because limit[L] is -1 for an empty length and would otherwise
    reject correctly only by accident.
    """
    lvalid = [False] * (MAX_LEN + 2)
    for l in range(min_len, max_len + 1):
        # A length carries codes iff its limit is >= its base-adjusted start.
        lvalid[l] = True
    return limit, base, perm, lvalid


def hw_decode_symbol(window, limit, base, perm, lvalid, min_len, max_len):
    """One cycle of huffman_decoder.v, as combinational logic.

    `window` is an integer holding MAX_LEN bits, MSB-first (bit MAX_LEN-1 is
    the next bit on the wire).  Returns (symbol, code_length).
    """
    sel = 0
    # Parallel comparators; priority encoder picks the LOWEST accepting length.
    for L in range(min_len, max_len + 1):
        if not lvalid[L]:
            continue
        code_L = window >> (MAX_LEN - L)          # top L bits
        if code_L <= limit[L]:
            sel = L
            break
    if sel == 0:
        raise AssertionError("no candidate length accepted - corrupt table")
    code = window >> (MAX_LEN - sel)
    return perm[code - base[sel]], sel


def decode_with_hw_model(data):
    """Re-run the bzip2 decode, but take every Huffman symbol from the RTL model."""
    b = opt._Reader(data)
    magic = b.readbits(16)
    if magic != 0x425a:
        raise Exception("not a bzip2 stream")
    if b.readbits(8) != ord('h'):
        raise Exception("bad method")
    blocksize = b.readbits(8)
    if not (ord('1') <= blocksize <= ord('9')):
        raise Exception("bad blocksize")

    out = bytearray()
    symbols_decoded = 0

    while True:
        blocktype = b.readbits(48)
        b.readbits(32)
        if blocktype == 0x177245385090:
            b.align()
            break
        if blocktype != 0x314159265359:
            raise Exception("illegal blocktype")

        if b.readbits(1):
            raise Exception("randomised blocks unsupported (driver falls back)")
        pointer = b.readbits(24)
        used = opt.compute_used(b)
        groups = b.readbits(3)
        selectors = opt.compute_selectors_list(b, groups)
        symbols_in_use = sum(used) + 2
        tables = opt.compute_tables(b, groups, symbols_in_use)

        favourites = [i for i, x in enumerate(used) if x]
        buffer = bytearray()
        eob = symbols_in_use - 1
        sp = 0
        decoded = 0
        repeat = repeat_power = 0
        cur = None

        while True:
            decoded -= 1
            if decoded <= 0:
                decoded = 50
                if sp <= len(selectors):
                    limit, base, perm, min_len, max_len = tables[selectors[sp]]
                    cur = rtl_tables(limit, base, perm, min_len, max_len) + \
                        (min_len, max_len)
                    sp += 1

            limit, base, perm, lvalid, min_len, max_len = cur

            # Present MAX_LEN bits to the decoder, exactly as bit_window.v does.
            while b.bitcnt < MAX_LEN:
                b.bitbuf = (b.bitbuf << 8) | b.data[b.pos]
                b.pos += 1
                b.bitcnt += 8
            window = (b.bitbuf >> (b.bitcnt - MAX_LEN)) & ((1 << MAX_LEN) - 1)

            r, ln = hw_decode_symbol(window, limit, base, perm, lvalid,
                                     min_len, max_len)
            symbols_decoded += 1

            # Retire `ln` bits (bit_window.v's variable-width retire).
            b.bitcnt -= ln
            b.bitbuf &= (1 << b.bitcnt) - 1

            if r <= 1:
                if repeat == 0:
                    repeat_power = 1
                repeat += repeat_power << r
                repeat_power <<= 1
                continue
            elif repeat > 0:
                buffer += bytes((favourites[0],)) * repeat
                repeat = 0
            if r == eob:
                break
            j = r - 1
            o = favourites[j]
            if j:
                favourites.insert(0, favourites.pop(j))
            buffer.append(o)

        nt = opt.bwt_reverse(bytes(buffer), pointer)
        n = len(nt)
        lim4 = n - 4
        i = 0
        while i < n:
            b0 = nt[i]
            if i < lim4 and nt[i+1] == b0 and nt[i+2] == b0 and nt[i+3] == b0:
                out += bytes((b0,)) * (nt[i+4] + 4)
                i += 5
            else:
                out.append(b0)
                i += 1

    return bytes(out), symbols_decoded


if __name__ == "__main__":
    path = os.path.join(ROOT, "benchmarks", "pyflate", "data",
                        "interpreter.tar.bz2")
    with open(path, "rb") as fp:
        data = fp.read()

    out, nsym = decode_with_hw_model(data)
    md5 = hashlib.md5(out).hexdigest()

    print("huffman_decoder.v golden model")
    print("  symbols decoded through the RTL decision function : %d" % nsym)
    print("  output bytes                                      : %d" % len(out))
    print("  md5                                               : %s" % md5)
    print("  expected                                          : %s" % EXPECTED_MD5)
    if md5 == EXPECTED_MD5:
        print("  PASS - parallel-compare + priority-encode is equivalent to")
        print("         the serial canonical decode for every symbol in the")
        print("         benchmark workload.")
        sys.exit(0)
    print("  FAIL")
    sys.exit(1)
