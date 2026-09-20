// ---------------------------------------------------------------------------
// huffman_decoder.v - single-cycle canonical Huffman symbol decoder (bzip2)
//
// HW/SW Co-design (00460882) project - accelerator for the pyflate benchmark.
//
// WHY THIS BLOCK EXISTS
// ---------------------
// Profiling pyflate showed HuffmanTable.find_next_symbol() dominating the
// runtime: it walks a (bits, code)-sorted symbol table in software, re-peeking
// the bitstream every time the code length changes.  Even after rewriting it in
// Python as a canonical limit/base decoder, decoding one symbol still costs a
// short serial loop - one iteration per additional code-length step.
//
// In hardware that entire search collapses into ONE cycle: all MAX_LEN
// candidate lengths are compared against their limits in parallel and a
// priority encoder picks the shortest match.  Huffman codes are prefix-free, so
// the shortest matching length is by construction the correct one.
//
// DESIGN PATTERN
// --------------
// This is a DATAFLOW block, not a systolic array.  The number of bits consumed
// per symbol is data-dependent (1..MAX_LEN), so a fixed-cadence systolic array
// with no control circuitry would mis-align the stream ("garbage in, garbage
// out").  Every interface therefore carries valid/ready handshakes.
//
// THROUGHPUT
// ----------
// 1 symbol/cycle sustained while the bit window holds >= MAX_LEN valid bits.
// The critical path is: window mux -> MAX_LEN parallel magnitude comparators
// -> priority encoder -> subtract -> perm RAM read.
// ---------------------------------------------------------------------------

`default_nettype none

module huffman_decoder #(
    parameter integer MAX_LEN    = 20,  // bzip2: code lengths are 1..20
    parameter integer SYM_BITS   = 9,   // alphabet <= 258 symbols
    parameter integer ALPHA_SIZE = 258
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // ---- Table load interface (driven by the CSR block on table switch) ----
    // limit[l] and base[l] are signed: a length with no codes yields -1.
    input  wire                     tbl_we,
    input  wire [4:0]               tbl_len_addr,   // 1..MAX_LEN
    input  wire signed [MAX_LEN+1:0] tbl_limit_din,
    input  wire signed [MAX_LEN+1:0] tbl_base_din,
    input  wire                     tbl_len_valid,  // this length has codes

    input  wire                     perm_we,
    input  wire [SYM_BITS-1:0]      perm_addr,
    input  wire [SYM_BITS-1:0]      perm_din,

    input  wire [4:0]               min_len,        // smallest code length

    // ---- Bit window (MSB-first).  window[MAX_LEN-1] is the next bit. -------
    input  wire [MAX_LEN-1:0]       window,
    input  wire                     window_valid,   // >= MAX_LEN bits present

    // ---- Decoded symbol stream --------------------------------------------
    output wire [SYM_BITS-1:0]      sym,
    output wire [4:0]               sym_len,        // bits to retire
    output wire                     sym_valid,
    input  wire                     sym_ready,

    // No code length accepts the window: a corrupt stream or a bad table.
    // Drives STATUS.ERR so the driver can fall back to software.
    output wire                     decode_err
);

    // -----------------------------------------------------------------------
    // Table storage.  Small enough to be distributed RAM / registers.
    // -----------------------------------------------------------------------
    reg signed [MAX_LEN+1:0] limit_q [1:MAX_LEN];
    reg signed [MAX_LEN+1:0] base_q  [1:MAX_LEN];
    reg                      lvalid_q[1:MAX_LEN];
    reg        [SYM_BITS-1:0] perm_q [0:ALPHA_SIZE-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i <= MAX_LEN; i = i + 1) begin
                limit_q[i]  <= {(MAX_LEN+2){1'b0}};
                base_q[i]   <= {(MAX_LEN+2){1'b0}};
                lvalid_q[i] <= 1'b0;
            end
        end else if (tbl_we) begin
            limit_q[tbl_len_addr]  <= tbl_limit_din;
            base_q[tbl_len_addr]   <= tbl_base_din;
            lvalid_q[tbl_len_addr] <= tbl_len_valid;
        end
    end

    always @(posedge clk) begin
        if (perm_we)
            perm_q[perm_addr] <= perm_din;
    end

    // -----------------------------------------------------------------------
    // Parallel candidate evaluation.
    //
    // For length L the candidate code is the top L bits of the window:
    //     code_L = window[MAX_LEN-1 : MAX_LEN-L]
    // Canonical decoding accepts L when code_L <= limit[L].  Because the code
    // is prefix-free, the SHORTEST accepting L is the unique correct length,
    // so a priority encoder from min_len upward is exact - no backtracking.
    // -----------------------------------------------------------------------
    wire signed [MAX_LEN+1:0] code_of [1:MAX_LEN];
    wire                      hit     [1:MAX_LEN];

    genvar L;
    generate
        for (L = 1; L <= MAX_LEN; L = L + 1) begin : g_cand
            // Zero-extend the top L bits into the signed comparison width.
            assign code_of[L] = $signed({{(MAX_LEN+2-L){1'b0}},
                                         window[MAX_LEN-1 -: L]});
            assign hit[L] = lvalid_q[L] &&
                            (L >= min_len) &&
                            (code_of[L] <= limit_q[L]);
        end
    endgenerate

    // Priority encoder: lowest L with hit[L].
    reg [4:0] sel_len;
    reg       sel_found;
    always @(*) begin
        sel_len   = 5'd0;
        sel_found = 1'b0;
        for (i = MAX_LEN; i >= 1; i = i - 1) begin
            if (hit[i]) begin
                sel_len   = i[4:0];
                sel_found = 1'b1;
            end
        end
    end

    // Index into the permutation table: idx = code - base[len].
    wire signed [MAX_LEN+1:0] sel_code = code_of[sel_len];
    wire signed [MAX_LEN+1:0] sel_base = base_q[sel_len];
    wire signed [MAX_LEN+1:0] idx_s    = sel_code - sel_base;

    assign sym        = perm_q[idx_s[SYM_BITS-1:0]];
    assign sym_len    = sel_len;
    assign sym_valid  = window_valid & sel_found;
    assign decode_err = window_valid & ~sel_found;

    // sym_ready participates in the handshake driven by the bit_window, which
    // retires sym_len bits only when (sym_valid & sym_ready).
    wire _unused_ok = &{1'b0, sym_ready, 1'b0};

`ifdef FORMAL
    // A well-formed table must always decode: if the window is valid, some
    // length must accept.  Violation means a corrupt stream or a bad table.
    always @(posedge clk)
        if (rst_n && window_valid)
            assert (sel_found);
`endif

endmodule

`default_nettype wire
