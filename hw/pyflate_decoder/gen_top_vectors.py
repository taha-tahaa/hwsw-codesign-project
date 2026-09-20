#!/usr/bin/env python3
"""Generate tb_top_block.v: an END-TO-END test of bzip2_accel_top.

    python3 gen_top_vectors.py > /tmp/tb_top_block.v
    iverilog -g2012 -o /tmp/tb_top /tmp/tb_top_block.v bzip2_accel_top.v \
        huffman_decoder.v bit_window.v mtf_bwt_engine.v bwt_index_builder.v \
        rle_stages.v
    vvp /tmp/tb_top

Until now every block of the pyflate accelerator was verified on its own and
the assembled top level was only checked for elaboration - it had never
decompressed anything.  This closes that gap on a small block.

WHAT IT BUILDS
--------------
Everything is derived here, in Python, from one source string, by running the
bzip2 ENCODE pipeline and then checking that the software DECODE pipeline gets
the string back.  Only then is the testbench emitted, so the vectors cannot
disagree with the software:

    S  ->  BWT  ->  MTF  ->  RUNA/RUNB  ->  canonical Huffman  ->  bit stream
                                                                      |
    S  <-  RLE1 <- inverse BWT <- MTF <- run expand <- Huffman decode <+

The testbench then drives the accelerator exactly as the driver would:
program the Huffman tables, the permutation, the end-of-block symbol and the
initial MTF alphabet through the CSR port, write the origin pointer, pulse
CTRL.START, stream the compressed words in, and compare the bytes that come
out against S.  The sink stalls on a fixed pattern, so the valid/ready path is
exercised rather than assumed.

S is chosen with no run of four identical bytes, so bzip2's outer RLE is the
identity here and the expected output is S itself.  rle_final still sees the
stream and must pass it through unchanged - a stage that mangles ordinary data
would fail this test too.
"""

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "benchmarks", "pyflate", "pyflate_optimized.py")

spec = importlib.util.spec_from_file_location("pyflate_optimized", SRC)
pyf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pyf)

S = b"banana_bandana!"
CODE_LENGTHS = [2, 2, 3, 3, 4, 4, 4, 4]      # complete code over 8 symbols


# --------------------------------------------------------------------------
# encode side
# --------------------------------------------------------------------------
def bwt_forward(data):
    rot = sorted(data[i:] + data[:i] for i in range(len(data)))
    return bytes(r[-1] for r in rot), rot.index(data)


def mtf_run_encode(L):
    """L -> bzip2 symbol stream (RUNA=0, RUNB=1, literals = index+1, EOB)."""
    alphabet = sorted(set(L))
    order = list(alphabet)
    syms = []
    zeros = 0

    def flush():
        # Bijective base 2: n = sum (r_i + 1) * 2^i
        nonlocal zeros
        n = zeros
        while n > 0:
            n -= 1
            syms.append(n & 1)          # 0 = RUNA, 1 = RUNB
            n >>= 1
        zeros = 0

    for b in L:
        j = order.index(b)
        order.insert(0, order.pop(j))
        if j == 0:
            zeros += 1
        else:
            flush()
            syms.append(j + 1)
    flush()
    syms.append(len(alphabet) + 1)      # EOB = symbols_in_use - 1
    return alphabet, syms


def canonical_codes(lengths):
    """Codes exactly as the baseline's populate_huffman_symbols() assigns."""
    codes = {}
    code = 0
    prev = min(lengths)
    for sym in sorted(range(len(lengths)), key=lambda s: (lengths[s], s)):
        code <<= lengths[sym] - prev
        prev = lengths[sym]
        codes[sym] = (code, lengths[sym])
        code += 1
    return codes


def pack_bits(bits):
    words = []
    for i in range(0, len(bits), 32):
        chunk = bits[i:i + 32]
        chunk = chunk + [0] * (32 - len(chunk))
        w = 0
        for b in chunk:
            w = (w << 1) | b
        words.append(w)
    return words


# --------------------------------------------------------------------------
# decode side: the same decisions the RTL makes, in Python
# --------------------------------------------------------------------------
def rtl_decode(bits, limit, base, perm, min_len, max_len, eob):
    """Parallel-compare + priority-encode, the huffman_decoder algorithm."""
    out = []
    pos = 0
    while True:
        zn = min_len
        zvec = 0
        for _ in range(zn):
            zvec = (zvec << 1) | bits[pos]
            pos += 1
        while zvec > limit[zn]:
            zvec = (zvec << 1) | bits[pos]
            pos += 1
            zn += 1
            if zn > max_len:
                raise SystemExit("gen_top_vectors: no code length accepts")
        sym = perm[zvec - base[zn]]
        out.append(sym)
        if sym == eob:
            return out


def mtf_run_decode(syms, alphabet, eob):
    order = list(alphabet)
    out = bytearray()
    repeat = power = 0
    for r in syms:
        if r <= 1:
            if repeat == 0:
                power = 1
            repeat += power << r
            power <<= 1
            continue
        if repeat:
            out += bytes([order[0]]) * repeat
            repeat = 0
        if r == eob:
            break
        j = r - 1
        o = order[j]
        if j:
            order.insert(0, order.pop(j))
        out.append(o)
    return bytes(out)


def rle1_decode(nt):
    """bzip2's outer RLE, the same pass the software decoder runs last."""
    out = bytearray()
    n = len(nt)
    i = 0
    while i < n:
        b0 = nt[i]
        if i < n - 4 and nt[i + 1] == b0 and nt[i + 2] == b0 and nt[i + 3] == b0:
            out += bytes([b0]) * (nt[i + 4] + 4)
            i += 5
        else:
            out.append(b0)
            i += 1
    return bytes(out)


# --------------------------------------------------------------------------
def main():
    L, orig = bwt_forward(S)
    alphabet, syms = mtf_run_encode(L)
    eob = len(alphabet) + 1
    n_syms = len(alphabet) + 2

    if n_syms != len(CODE_LENGTHS):
        raise SystemExit("gen_top_vectors: %d symbols but %d code lengths"
                         % (n_syms, len(CODE_LENGTHS)))

    codes = canonical_codes(CODE_LENGTHS)
    bits = []
    for s in syms:
        code, ln = codes[s]
        bits.extend((code >> (ln - 1 - k)) & 1 for k in range(ln))

    limit, base, perm, min_len, max_len = pyf.build_decode_tables(CODE_LENGTHS)

    # Self-check: decode our own stream with the RTL's algorithm and run the
    # whole software back end.  If this does not reproduce S, the testbench is
    # wrong and must not be emitted.
    padded = bits + [0] * 64
    got_syms = rtl_decode(padded, limit, base, perm, min_len, max_len, eob)
    if got_syms != syms:
        raise SystemExit("gen_top_vectors: decode(encode(x)) != x at symbol level")
    L2 = mtf_run_decode(got_syms, alphabet, eob)
    if L2 != L:
        raise SystemExit("gen_top_vectors: MTF/run round trip failed")
    if rle1_decode(pyf.bwt_reverse(L2, orig)) != S:
        raise SystemExit("gen_top_vectors: full software round trip failed")

    words = pack_bits(bits + [0] * 64)      # padding keeps the window full
    mask22 = (1 << 22) - 1

    w = sys.stdout.write
    w("// ---------------------------------------------------------------------------\n")
    w("// tb_top_block.v - GENERATED by gen_top_vectors.py.  Do not edit.\n")
    w("//\n")
    w("// End-to-end test of bzip2_accel_top: program the CSRs the way the driver\n")
    w("// would, stream one compressed block in, compare the decompressed bytes.\n")
    w("//\n")
    w("//   source string : %r\n" % S)
    w("//   BWT L column  : %r  (origin pointer %d)\n" % (L, orig))
    w("//   alphabet      : %s\n" % " ".join("%02x" % b for b in alphabet))
    w("//   symbols       : %s\n" % " ".join(str(s) for s in syms))
    w("//   code lengths  : %s\n" % " ".join(str(x) for x in CODE_LENGTHS))
    w("//   bit stream    : %d bits in %d words\n" % (len(bits), len(words)))
    w("// ---------------------------------------------------------------------------\n\n")
    w("`timescale 1ns/1ps\n`default_nettype none\n\n")
    w("module tb_top_block;\n\n")
    w("    localparam integer NW   = %d;\n" % len(words))
    w("    localparam integer NOUT = %d;\n\n" % len(S))
    w("    reg clk = 1'b0;\n    reg rst_n = 1'b0;\n    always #5 clk = ~clk;\n\n")
    w("    reg         csr_we = 1'b0;\n    reg  [7:0]  csr_addr = 8'd0;\n")
    w("    reg  [31:0] csr_wdata = 32'd0;\n    wire [31:0] csr_rdata;\n")
    w("    reg  [31:0] in_data = 32'd0;\n    reg         in_valid = 1'b0;\n")
    w("    wire        in_ready;\n    reg         in_last = 1'b0;\n")
    w("    wire [7:0]  out_data;\n    wire        out_valid;\n")
    w("    reg         out_ready = 1'b1;\n    wire        irq;\n\n")
    w("    reg [31:0] words [0:NW-1];\n    reg [7:0]  expected [0:NOUT-1];\n")
    w("    reg [7:0]  got [0:255];\n")
    w("    integer    gi = 0, errors = 0, k, guard;\n")
    w("    reg        saw_stall = 1'b0;\n\n")
    w("    bzip2_accel_top #(.BLOCK_MAX(1024)) dut (\n")
    w("        .clk(clk), .rst_n(rst_n),\n")
    w("        .csr_we(csr_we), .csr_addr(csr_addr), .csr_wdata(csr_wdata),\n")
    w("        .csr_rdata(csr_rdata),\n")
    w("        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),\n")
    w("        .in_last(in_last),\n")
    w("        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),\n")
    w("        .irq(irq));\n\n")
    w("    // Reproducible stall pattern on the output sink.\n")
    w("    reg [1:0] pat = 2'd0;\n")
    w("    always @(posedge clk) begin\n")
    w("        pat <= pat + 2'd1;\n")
    w("        out_ready <= (pat != 2'd2);\n")
    w("        if (rst_n && !out_ready) saw_stall <= 1'b1;\n")
    w("    end\n\n")
    w("    always @(posedge clk)\n")
    w("        if (rst_n && out_valid && out_ready) begin\n")
    w("            got[gi] <= out_data;\n            gi <= gi + 1;\n        end\n\n")
    w("    task csr_write(input [7:0] a, input [31:0] d);\n")
    w("        begin\n            @(negedge clk);\n")
    w("            csr_we = 1'b1; csr_addr = a; csr_wdata = d;\n")
    w("            @(negedge clk);\n            csr_we = 1'b0;\n        end\n")
    w("    endtask\n\n")
    w("    // Feeding is bounded: once the end-of-block symbol is decoded the\n")
    w("    // decoder stops accepting, so the window stops draining and the\n")
    w("    // trailing padding words are never consumed.  That is correct\n")
    w("    // behaviour, not a stall to wait on.\n")
    w("    task push(input [31:0] d, input last);\n")
    w("        integer waited;\n")
    w("        begin\n            @(negedge clk);\n")
    w("            in_data = d; in_valid = 1'b1; in_last = last;\n")
    w("            waited = 0;\n")
    w("            while (in_ready !== 1'b1 && waited < 400) begin\n")
    w("                @(negedge clk);\n                waited = waited + 1;\n")
    w("            end\n")
    w("            @(negedge clk);\n            in_valid = 1'b0; in_last = 1'b0;\n")
    w("        end\n    endtask\n\n")
    w("    initial begin\n")
    for i, word in enumerate(words):
        w("        words[%d] = 32'h%08x;\n" % (i, word))
    for i, b in enumerate(S):
        w("        expected[%d] = 8'h%02x;\n" % (i, b))
    w("\n        repeat (3) @(negedge clk);\n        rst_n = 1'b1;\n")
    w("        @(negedge clk);\n\n")
    w("        // ---- program the accelerator, as the driver would ----------\n")
    w("        csr_write(8'h20, 32'd%d);        // MIN_LEN\n" % min_len)
    for l in range(1, 21):
        has = (l >= min_len and l <= max_len and
               any(x == l for x in CODE_LENGTHS))
        lim = limit[l] & mask22 if l < len(limit) else 0
        bas = base[l] & mask22 if l < len(base) else 0
        w("        csr_write(8'h24, 32'h%08x);  // TBL_CTRL len=%d valid=%d\n"
          % ((1 << 8 if has else 0) | l, l, 1 if has else 0))
        w("        csr_write(8'h28, 32'h%08x);  // TBL_LIMIT\n" % lim)
        w("        csr_write(8'h2C, 32'h%08x);  // TBL_BASE (commits)\n" % bas)
    for i, sym in enumerate(perm):
        w("        csr_write(8'h30, 32'h%08x);  // PERM[%d] = %d\n"
          % ((1 << 31) | (sym << 16) | i, i, sym))
    w("        csr_write(8'h34, 32'd%d);        // EOB_SYM\n" % eob)
    for i, b in enumerate(alphabet):
        w("        csr_write(8'h3C, 32'h%08x);  // MTF[%d] = 0x%02x\n"
          % ((1 << 31) | (b << 16) | i, i, b))
    w("        csr_write(8'h18, 32'd%d);        // ORIG_PTR\n" % orig)
    w("        csr_write(8'h1C, 32'd64);        // BLOCK_LEN (declared capacity)\n")
    w("        csr_write(8'h38, 32'd0);         // BLK_FLAGS: not randomised\n")
    w("        csr_write(8'h00, 32'd1);         // CTRL.START\n\n")
    w("        for (k = 0; k < NW; k = k + 1)\n")
    w("            push(words[k], (k == NW-1) ? 1'b1 : 1'b0);\n\n")
    w("        guard = 0;\n")
    w("        while (irq !== 1'b1 && guard < 20000) begin\n")
    w("            @(negedge clk);\n            guard = guard + 1;\n        end\n")
    w("        repeat (20) @(negedge clk);\n\n")
    w("        if (irq !== 1'b1) begin\n")
    w("            $display(\"  FAIL: irq never asserted (guard %0d)\", guard);\n")
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   irq asserted, block complete\");\n\n")
    w("        if (gi != NOUT) begin\n")
    w("            $display(\"  FAIL: %0d bytes out, expected %0d\", gi, NOUT);\n")
    w("            errors = errors + 1;\n        end else begin\n")
    w("            for (k = 0; k < NOUT; k = k + 1)\n")
    w("                if (got[k] !== expected[k]) begin\n")
    w("                    $display(\"  FAIL byte %0d: got 0x%02x want 0x%02x\",\n")
    w("                             k, got[k], expected[k]);\n")
    w("                    errors = errors + 1;\n                end\n")
    w("            if (errors == 0)\n")
    w("                $display(\"  ok   %0d bytes decompressed correctly\", NOUT);\n")
    w("        end\n\n")
    w("        @(negedge clk); csr_addr = 8'h04; @(negedge clk);\n")
    w("        if (csr_rdata[2] !== 1'b0 || csr_rdata[3] !== 1'b0) begin\n")
    w("            $display(\"  FAIL: STATUS reports ERR/UNSUPPORTED (0x%08x)\", csr_rdata);\n")
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   STATUS: done, no error, supported\");\n\n")
    w("        @(negedge clk); csr_addr = 8'h40; @(negedge clk);\n")
    w("        if (csr_rdata !== 32'd%d) begin\n" % len(L))
    w("            $display(\"  FAIL: DEC_LEN = %%0d, expected %d\", csr_rdata);\n"
      % len(L))
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   DEC_LEN = %0d (decoded block length)\", csr_rdata);\n\n")
    w("        @(negedge clk); csr_addr = 8'h14; @(negedge clk);\n")
    w("        if (csr_rdata !== 32'd%d) begin\n" % len(S))
    w("            $display(\"  FAIL: DST_LEN = %%0d, expected %d\", csr_rdata);\n" % len(S))
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   DST_LEN = %0d (bytes written out)\", csr_rdata);\n\n")
    w("        if (!saw_stall) begin\n")
    w("            $display(\"  FAIL: the sink never stalled\");\n")
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   correct through a stalling output sink\");\n\n")
    w("        // ---- Rule 3: refuse what the hardware cannot do -------------\n")
    w("        // A randomised block, and a block larger than the on-chip index\n")
    w("        // memory, must be REPORTED so the driver can fall back to the\n")
    w("        // software decoder - not attempted and got wrong.\n")
    w("        csr_write(8'h00, 32'd2);         // CTRL.ABORT\n")
    w("        csr_write(8'h38, 32'd1);         // BLK_FLAGS.RANDOMISED\n")
    w("        csr_write(8'h00, 32'd1);         // CTRL.START\n")
    w("        repeat (4) @(negedge clk);\n")
    w("        csr_addr = 8'h04; @(negedge clk);\n")
    w("        if (csr_rdata[3] !== 1'b1 || csr_rdata[0] !== 1'b0) begin\n")
    w("            $display(\"  FAIL: randomised block not refused (STATUS 0x%08x)\", csr_rdata);\n")
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   randomised block refused: UNSUPPORTED, not BUSY\");\n\n")
    w("        csr_write(8'h00, 32'd2);         // CTRL.ABORT\n")
    w("        csr_write(8'h38, 32'd0);         // not randomised\n")
    w("        csr_write(8'h1C, 32'd4096);      // bigger than BLOCK_MAX = 1024\n")
    w("        csr_write(8'h00, 32'd1);         // CTRL.START\n")
    w("        repeat (4) @(negedge clk);\n")
    w("        csr_addr = 8'h04; @(negedge clk);\n")
    w("        if (csr_rdata[3] !== 1'b1 || csr_rdata[0] !== 1'b0) begin\n")
    w("            $display(\"  FAIL: oversized block not refused (STATUS 0x%08x)\", csr_rdata);\n")
    w("            errors = errors + 1;\n        end else\n")
    w("            $display(\"  ok   block larger than the index SRAM refused\");\n\n")
    w("        $display(\"\");\n")
    w("        if (errors == 0)\n")
    w("            $display(\"TB PASS: bzip2_accel_top decompressed a whole block\");\n")
    w("        else\n")
    w("            $display(\"TB FAIL: %0d error(s)\", errors);\n")
    w("        $finish;\n    end\n\n")
    w("    initial begin\n        #400000;\n")
    w("        $display(\"TB FAIL: timeout\");\n        $finish;\n    end\n\n")
    w("endmodule\n\n`default_nettype wire\n")


if __name__ == "__main__":
    main()
