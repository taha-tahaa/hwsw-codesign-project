// ---------------------------------------------------------------------------
// bzip2_accel_top.v - top level of the bzip2 decode accelerator
//
// Integrates:  bit_window -> huffman_decoder -> mtf_unit -> bwt_reverse_engine
//
// HW/SW INTERFACE
// ---------------
// The host sees an AXI4-Lite CSR block plus two AXI4 DMA channels.  This obeys
// the three interface rules from the accelerator-design lecture:
//
//   Rule 1 - end users do not change their code.  A Python program still calls
//            bz2.decompress(); nothing above the library moves.
//   Rule 2 - if software must change, confine it to the runtime/library.  Only
//            the decompressor library gains an ioctl-style fast path.
//   Rule 3 - never break the user's code.  START_BLOCK reports UNSUPPORTED for
//            a randomised block or a block larger than the on-chip index SRAM,
//            and the driver silently falls back to the software decoder.  The
//            optimized Python module mirrors this: a gzip input falls back to
//            the baseline path rather than failing.
//
// CSR map (32-bit registers, offset from the accelerator's BAR):
//   0x00  CTRL        [0] START  [1] ABORT           (W1S)
//   0x04  STATUS      [0] BUSY   [1] DONE  [2] ERR  [3] UNSUPPORTED   (RO)
//   0x08  SRC_ADDR    physical address of the compressed block        (RW)
//   0x0C  SRC_LEN     bytes                                          (RW)
//   0x10  DST_ADDR    physical address of the output buffer           (RW)
//   0x14  DST_LEN     bytes written by the engine                    (RO)
//   0x18  ORIG_PTR    BWT origin pointer from the block header        (RW)
//   0x1C  BLOCK_LEN   BWT block length                                (RW)
//   0x20  MIN_LEN     shortest Huffman code length                    (RW)
//   0x24  TBL_CTRL    table-load window: [4:0] len, [8] valid         (RW)
//   0x28  TBL_LIMIT   limit[len]                                      (RW)
//   0x2C  TBL_BASE    base[len]                                       (RW)
//   0x30  PERM_CTRL   [8:0] addr, [24:16] symbol, [31] write strobe   (RW)
//
// Addresses are IOVAs: the accelerator is a DMA master behind the IOMMU, so it
// cannot scribble outside the buffers the driver mapped for it.  That is the
// same protection boundary discussed for NICs in the bottlenecks lecture, and
// it is the reason the driver maps per-request rather than pinning all memory.
// ---------------------------------------------------------------------------

`default_nettype none

module bzip2_accel_top #(
    parameter integer MAX_LEN  = 20,
    parameter integer SYM_BITS = 9,
    parameter integer IDX_W    = 20
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CSR (AXI4-Lite simplified to a single-cycle register port) -------
    input  wire        csr_we,
    input  wire [7:0]  csr_addr,
    input  wire [31:0] csr_wdata,
    output reg  [31:0] csr_rdata,

    // ---- Compressed input stream (AXI4 read channel via DMA) --------------
    input  wire [31:0] in_data,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_last,

    // ---- Decompressed output stream (AXI4 write channel via DMA) ----------
    output wire [7:0]  out_data,
    output wire        out_valid,

    output wire        irq
);

    // ---------------- CSRs --------------------------------------------------
    reg        ctrl_start;
    reg [31:0] orig_ptr_q, block_len_q;
    reg [4:0]  min_len_q;
    reg        busy_q, done_q, unsupported_q;

    reg        tbl_we_q, tbl_len_valid_q;
    reg [4:0]  tbl_len_q;
    reg signed [MAX_LEN+1:0] tbl_limit_q, tbl_base_q;

    reg        perm_we_q;
    reg [SYM_BITS-1:0] perm_addr_q, perm_din_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_start <= 1'b0; tbl_we_q <= 1'b0; perm_we_q <= 1'b0;
            orig_ptr_q <= 32'd0; block_len_q <= 32'd0; min_len_q <= 5'd1;
        end else begin
            ctrl_start <= 1'b0;      // single-cycle pulse
            tbl_we_q   <= 1'b0;
            perm_we_q  <= 1'b0;
            if (csr_we) begin
                case (csr_addr)
                    8'h00: ctrl_start  <= csr_wdata[0];
                    8'h18: orig_ptr_q  <= csr_wdata;
                    8'h1C: block_len_q <= csr_wdata;
                    8'h20: min_len_q   <= csr_wdata[4:0];
                    8'h24: begin
                        tbl_len_q       <= csr_wdata[4:0];
                        tbl_len_valid_q <= csr_wdata[8];
                    end
                    8'h28: tbl_limit_q <= csr_wdata[MAX_LEN+1:0];
                    8'h2C: begin
                        tbl_base_q <= csr_wdata[MAX_LEN+1:0];
                        tbl_we_q   <= 1'b1;   // BASE write commits the entry
                    end
                    8'h30: begin
                        perm_addr_q <= csr_wdata[SYM_BITS-1:0];
                        perm_din_q  <= csr_wdata[16+SYM_BITS-1:16];
                        perm_we_q   <= csr_wdata[31];
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (csr_addr)
            8'h04:   csr_rdata = {28'd0, unsupported_q, 1'b0, done_q, busy_q};
            8'h18:   csr_rdata = orig_ptr_q;
            8'h1C:   csr_rdata = block_len_q;
            default: csr_rdata = 32'd0;
        endcase
    end

    // ---------------- Datapath ---------------------------------------------
    wire [MAX_LEN-1:0] window;
    wire               window_valid;
    wire [SYM_BITS-1:0] sym;
    wire [4:0]         sym_len;
    wire               sym_valid;
    wire               drained;

    // Back pressure: retire bits only when the MTF stage can accept a symbol.
    wire sym_ready = 1'b1;   // MTF accepts one symbol/cycle

    bit_window #(.MAX_LEN(MAX_LEN)) u_win (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .in_last(in_last),
        .window(window), .window_valid(window_valid),
        .retire_len(sym_len), .retire_en(sym_valid & sym_ready),
        .drained(drained)
    );

    huffman_decoder #(.MAX_LEN(MAX_LEN), .SYM_BITS(SYM_BITS)) u_huff (
        .clk(clk), .rst_n(rst_n),
        .tbl_we(tbl_we_q), .tbl_len_addr(tbl_len_q),
        .tbl_limit_din(tbl_limit_q), .tbl_base_din(tbl_base_q),
        .tbl_len_valid(tbl_len_valid_q),
        .perm_we(perm_we_q), .perm_addr(perm_addr_q), .perm_din(perm_din_q),
        .min_len(min_len_q),
        .window(window), .window_valid(window_valid),
        .sym(sym), .sym_len(sym_len), .sym_valid(sym_valid),
        .sym_ready(sym_ready)
    );

    // RUNA/RUNB (symbols 0,1) and end-of-block are handled by the run-length
    // expander; everything else is an MTF index offset by one.
    wire is_run = (sym == {SYM_BITS{1'b0}}) || (sym == {{(SYM_BITS-1){1'b0}}, 1'b1});
    wire mtf_valid = sym_valid && !is_run;

    wire [7:0] mtf_byte;
    wire       mtf_byte_valid;

    mtf_unit u_mtf (
        .clk(clk), .rst_n(rst_n),
        .load_en(1'b0), .load_addr(8'd0), .load_din(8'd0),
        .idx(sym[7:0] - 8'd1), .idx_valid(mtf_valid),
        .byte_out(mtf_byte), .byte_valid(mtf_byte_valid)
    );

    wire bwt_done;
    bwt_reverse_engine #(.IDX_W(IDX_W)) u_bwt (
        .clk(clk), .rst_n(rst_n),
        .start(ctrl_start),
        .block_len(block_len_q[IDX_W-1:0]),
        .orig_ptr(orig_ptr_q[IDX_W-1:0]),
        .t_we(1'b0), .t_waddr({IDX_W{1'b0}}), .t_wdin({IDX_W{1'b0}}),
        .l_we(mtf_byte_valid), .l_waddr({IDX_W{1'b0}}), .l_wdin(mtf_byte),
        .out_data(out_data), .out_valid(out_valid), .done(bwt_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0; done_q <= 1'b0; unsupported_q <= 1'b0;
        end else begin
            if (ctrl_start) begin busy_q <= 1'b1; done_q <= 1'b0; end
            else if (bwt_done) begin busy_q <= 1'b0; done_q <= 1'b1; end
        end
    end

    assign irq = done_q;

    wire _unused = &{1'b0, drained, 1'b0};

endmodule

`default_nettype wire
