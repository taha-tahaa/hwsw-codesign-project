// ---------------------------------------------------------------------------
// bzip2_accel_top.v - top level of the bzip2 decode accelerator
//
// Datapath:
//
//   bit_window -> huffman_decoder -> run_expander -> mtf_unit
//                                         |
//                                         v  byte stream (L[] + histogram)
//                              bwt_index_builder  ->  bwt_reverse_engine
//                                                            |
//                                                            v
//                                                        rle_final -> out
//
// HW/SW INTERFACE
// ---------------
// The host drives a memory-mapped register block and two data streams.  This
// obeys the three interface rules from the accelerator-design lecture:
//
//   Rule 1 - end users do not change their code.  A Python program still calls
//            bz2.decompress(); nothing above the library moves.
//   Rule 2 - if software must change, confine it to the runtime/library.  Only
//            the decompressor library gains an ioctl-style fast path.
//   Rule 3 - never break the user's code.  START reports UNSUPPORTED for a
//            randomised block or a block larger than the on-chip index SRAM,
//            and the driver falls back to the software decoder.  The optimized
//            Python module mirrors this: a gzip input falls back to the
//            baseline path rather than failing.
//
// WHAT IS MODELLED HERE, AND WHAT IS NOT
// --------------------------------------
// The CSR port is a single-cycle register interface: address, write-enable,
// write data, read data.  An AXI4-Lite (or PCIe BAR) adapter in front of it is
// a standard wrapper and is NOT part of this project.  Likewise the compressed
// input and decompressed output are STREAM ports with valid/ready; the DMA
// engine that would fill and drain them from host memory is not implemented.
// SRC_ADDR/SRC_LEN/DST_ADDR are stored here for that engine to consume, which
// is why they are real registers with read-back rather than documentation.
//
// Addresses handed to that DMA engine are IOVAs: the accelerator is a DMA
// master behind the IOMMU, so it cannot scribble outside the buffers the
// driver mapped for it - the same protection boundary discussed for NICs in
// the bottlenecks lecture, and the reason the driver maps per request.
//
// CSR map (32-bit registers, offset from the accelerator's base address):
//   0x00  CTRL        [0] START  [1] ABORT                      (W, pulses)
//   0x04  STATUS      [0] BUSY [1] DONE [2] ERR [3] UNSUPPORTED (RO)
//   0x08  SRC_ADDR    IOVA of the compressed block              (RW)
//   0x0C  SRC_LEN     bytes of compressed input                 (RW)
//   0x10  DST_ADDR    IOVA of the output buffer                 (RW)
//   0x14  DST_LEN     bytes emitted so far                      (RO)
//   0x18  ORIG_PTR    BWT origin pointer from the block header  (RW)
//   0x1C  BLOCK_LEN   declared block capacity (100k * digit)    (RW)
//   0x20  MIN_LEN     shortest Huffman code length              (RW)
//   0x24  TBL_CTRL    table-load window: [4:0] len, [8] valid   (RW)
//   0x28  TBL_LIMIT   limit[len]                                (RW)
//   0x2C  TBL_BASE    base[len]  - writing this commits the entry (RW)
//   0x30  PERM_CTRL   [8:0] addr, [24:16] symbol, [31] strobe   (RW)
//   0x34  EOB_SYM     end-of-block symbol id (symbols_in_use-1) (RW)
//   0x38  BLK_FLAGS   [0] RANDOMISED -> UNSUPPORTED             (RW)
//   0x3C  MTF_LOAD    [7:0] addr, [23:16] byte, [31] strobe     (W)
//   0x40  DEC_LEN     decoded block length, known only after the
//                     end-of-block symbol                       (RO)
// ---------------------------------------------------------------------------

`default_nettype none

module bzip2_accel_top #(
    parameter integer MAX_LEN   = 20,
    parameter integer SYM_BITS  = 9,
    parameter integer IDX_W     = 20,
    parameter integer BLOCK_MAX = (1<<20)
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CSR (register port; an AXI4-Lite/BAR adapter goes in front) ------
    input  wire        csr_we,
    input  wire [7:0]  csr_addr,
    input  wire [31:0] csr_wdata,
    output reg  [31:0] csr_rdata,

    // ---- Compressed input stream (filled by the DMA read engine) ----------
    input  wire [31:0] in_data,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_last,

    // ---- Decompressed output stream (drained by the DMA write engine) -----
    output wire [7:0]  out_data,
    output wire        out_valid,
    input  wire        out_ready,

    output wire        irq
);

    // =======================================================================
    // CSRs
    // =======================================================================
    reg        ctrl_start, ctrl_abort;
    reg [31:0] src_addr_q, src_len_q, dst_addr_q, dst_len_q;
    reg [31:0] orig_ptr_q, block_len_q;
    reg [4:0]  min_len_q;
    reg        blk_randomised_q;
    reg        busy_q, done_q, err_q, unsupported_q;

    reg        tbl_we_q, tbl_len_valid_q;
    reg [4:0]  tbl_len_q;
    reg signed [MAX_LEN+1:0] tbl_limit_q, tbl_base_q;

    reg        perm_we_q;
    reg [SYM_BITS-1:0] perm_addr_q, perm_din_q;

    reg        mtf_load_q;
    reg [7:0]  mtf_load_addr_q, mtf_load_din_q;

    reg [IDX_W-1:0] dec_len_q;          // decoded block length

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_start <= 1'b0; ctrl_abort <= 1'b0;
            tbl_we_q   <= 1'b0; perm_we_q  <= 1'b0; mtf_load_q <= 1'b0;
            src_addr_q <= 32'd0; src_len_q <= 32'd0; dst_addr_q <= 32'd0;
            orig_ptr_q <= 32'd0; block_len_q <= 32'd0; min_len_q <= 5'd1;
            blk_randomised_q <= 1'b0;
            tbl_len_q <= 5'd0; tbl_len_valid_q <= 1'b0;
            tbl_limit_q <= {(MAX_LEN+2){1'b0}}; tbl_base_q <= {(MAX_LEN+2){1'b0}};
            perm_addr_q <= {SYM_BITS{1'b0}}; perm_din_q <= {SYM_BITS{1'b0}};
            mtf_load_addr_q <= 8'd0; mtf_load_din_q <= 8'd0;
        end else begin
            // Single-cycle pulses.
            ctrl_start <= 1'b0;
            ctrl_abort <= 1'b0;
            tbl_we_q   <= 1'b0;
            perm_we_q  <= 1'b0;
            mtf_load_q <= 1'b0;
            if (csr_we) begin
                case (csr_addr)
                    8'h00: begin
                        ctrl_start <= csr_wdata[0];
                        ctrl_abort <= csr_wdata[1];
                    end
                    8'h08: src_addr_q  <= csr_wdata;
                    8'h0C: src_len_q   <= csr_wdata;
                    8'h10: dst_addr_q  <= csr_wdata;
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
                    8'h34: ;                       // EOB_SYM, latched below
                    8'h38: blk_randomised_q <= csr_wdata[0];
                    8'h3C: begin
                        mtf_load_addr_q <= csr_wdata[7:0];
                        mtf_load_din_q  <= csr_wdata[23:16];
                        mtf_load_q      <= csr_wdata[31];
                    end
                    default: ;
                endcase
            end
        end
    end

    // ---- End-of-block symbol id (declared before the read-back mux) -------
    reg [SYM_BITS-1:0] eob;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                           eob <= {SYM_BITS{1'b0}};
        else if (csr_we && csr_addr == 8'h34) eob <= csr_wdata[SYM_BITS-1:0];
    end

    always @(*) begin
        case (csr_addr)
            8'h04:   csr_rdata = {28'd0, unsupported_q, err_q, done_q, busy_q};
            8'h08:   csr_rdata = src_addr_q;
            8'h0C:   csr_rdata = src_len_q;
            8'h10:   csr_rdata = dst_addr_q;
            8'h14:   csr_rdata = dst_len_q;
            8'h18:   csr_rdata = orig_ptr_q;
            8'h1C:   csr_rdata = block_len_q;
            8'h20:   csr_rdata = {27'd0, min_len_q};
            8'h34:   csr_rdata = {{(32-SYM_BITS){1'b0}}, eob};
            8'h38:   csr_rdata = {31'd0, blk_randomised_q};
            8'h40:   csr_rdata = {{(32-IDX_W){1'b0}}, dec_len_q};
            default: csr_rdata = 32'd0;
        endcase
    end

    // Rule 3: refuse what the hardware cannot do, instead of doing it wrong.
    // A randomised block (deprecated bzip2 feature, unsupported by the
    // software decoder too) or a block larger than the on-chip index memory
    // is reported rather than attempted.
    wire [31:0] block_max_w      = BLOCK_MAX;
    wire        start_unsupported = blk_randomised_q ||
                                    (block_len_q > block_max_w);

    // =======================================================================
    // Stage 1: bit window + Huffman decoder
    // =======================================================================
    wire [MAX_LEN-1:0]  window;
    wire                window_valid;
    wire [SYM_BITS-1:0] sym;
    wire [4:0]          sym_len;
    wire                sym_valid, sym_ready, decode_err;
    wire                drained;

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
        .sym_ready(sym_ready), .decode_err(decode_err)
    );

    // =======================================================================
    // Stage 2: RUNA/RUNB expansion + move-to-front
    // =======================================================================
    wire [7:0] mtf_idx, mtf_front, mtf_byte;
    wire       mtf_idx_valid, mtf_byte_valid;
    wire [7:0] blk_byte;
    wire       blk_byte_valid;
    wire       block_done;

    run_expander #(.SYM_BITS(SYM_BITS), .CNT_W(IDX_W+1)) u_run (
        .clk(clk), .rst_n(rst_n), .clear(ctrl_start | ctrl_abort),
        .sym(sym), .sym_valid(sym_valid), .sym_ready(sym_ready), .eob(eob),
        .mtf_idx(mtf_idx), .mtf_idx_valid(mtf_idx_valid),
        .mtf_front(mtf_front), .mtf_byte(mtf_byte),
        .mtf_byte_valid(mtf_byte_valid),
        .byte_out(blk_byte), .byte_valid(blk_byte_valid),
        .block_done(block_done)
    );

    mtf_unit u_mtf (
        .clk(clk), .rst_n(rst_n),
        .load_en(mtf_load_q), .load_addr(mtf_load_addr_q),
        .load_din(mtf_load_din_q),
        .idx(mtf_idx), .idx_valid(mtf_idx_valid),
        .byte_out(mtf_byte), .byte_valid(mtf_byte_valid),
        .front(mtf_front)
    );

    // ---- L[] fill: the block byte stream, written sequentially ------------
    reg [IDX_W-1:0] l_waddr_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                          l_waddr_q <= {IDX_W{1'b0}};
        else if (ctrl_start || ctrl_abort)   l_waddr_q <= {IDX_W{1'b0}};
        else if (blk_byte_valid)             l_waddr_q <= l_waddr_q + 1'b1;
    end

    // The block length is NOT in the bzip2 header - it is however many bytes
    // the block decoded to, so it is captured when the end-of-block symbol
    // has been processed and the last byte written.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          dec_len_q <= {IDX_W{1'b0}};
        else if (ctrl_start) dec_len_q <= {IDX_W{1'b0}};
        else if (block_done) dec_len_q <= l_waddr_q;
    end

    // =======================================================================
    // Stage 3: build T[], then chase it
    // =======================================================================
    wire             bib_t_we;
    wire [IDX_W-1:0] bib_t_waddr, bib_t_wdin;
    wire [IDX_W-1:0] bib_l_raddr;
    wire [7:0]       l_rdata2;
    wire             bib_busy, bib_done;

    // The builder starts one cycle AFTER block_done, because dec_len_q is
    // latched on that same edge and the builder samples the length when it
    // leaves idle.
    reg bib_start_q, chase_start_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bib_start_q   <= 1'b0;
            chase_start_q <= 1'b0;
        end else begin
            bib_start_q   <= block_done;
            chase_start_q <= bib_done;
        end
    end

    bwt_index_builder #(.IDX_W(IDX_W)) u_bib (
        .clk(clk), .rst_n(rst_n),
        .sym_byte(blk_byte), .sym_valid(blk_byte_valid),
        .clear(ctrl_start | ctrl_abort),
        .start(bib_start_q),
        .block_len(dec_len_q),
        .l_raddr(bib_l_raddr), .l_rdata(l_rdata2),
        .t_we(bib_t_we), .t_waddr(bib_t_waddr), .t_wdin(bib_t_wdin),
        .busy(bib_busy), .done(bib_done)
    );

    wire [7:0] bwt_byte;
    wire       bwt_valid, bwt_ready, bwt_done;

    bwt_reverse_engine #(.IDX_W(IDX_W), .BLOCK_MAX(BLOCK_MAX)) u_bwt (
        .clk(clk), .rst_n(rst_n),
        .start(chase_start_q),
        .block_len(dec_len_q),
        .orig_ptr(orig_ptr_q[IDX_W-1:0]),
        .t_we(bib_t_we), .t_waddr(bib_t_waddr), .t_wdin(bib_t_wdin),
        .l_we(blk_byte_valid), .l_waddr(l_waddr_q), .l_wdin(blk_byte),
        .l_raddr2(bib_l_raddr), .l_rdata2(l_rdata2),
        .out_data(bwt_byte), .out_valid(bwt_valid), .out_ready(bwt_ready),
        .done(bwt_done)
    );

    // =======================================================================
    // Stage 4: final run-length expansion, then out to the DMA write channel
    // =======================================================================
    wire rle_busy;

    rle_final u_rle (
        .clk(clk), .rst_n(rst_n), .clear(ctrl_start | ctrl_abort),
        .in_data(bwt_byte), .in_valid(bwt_valid), .in_ready(bwt_ready),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .busy(rle_busy)
    );

    // =======================================================================
    // Status, completion and interrupt
    // =======================================================================
    reg bwt_done_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0; done_q <= 1'b0; err_q <= 1'b0;
            unsupported_q <= 1'b0; bwt_done_q <= 1'b0; dst_len_q <= 32'd0;
        end else begin
            if (ctrl_abort) begin
                busy_q <= 1'b0; bwt_done_q <= 1'b0;
            end else if (ctrl_start) begin
                busy_q        <= !start_unsupported;
                done_q        <= start_unsupported;   // refused: report at once
                err_q         <= 1'b0;
                unsupported_q <= start_unsupported;
                bwt_done_q    <= 1'b0;
                dst_len_q     <= 32'd0;
            end else begin
                if (decode_err)  err_q <= 1'b1;
                // The block is only finished when the chase has ended AND the
                // final run-length stage has drained.
                if (bwt_done)    bwt_done_q <= 1'b1;
                if (bwt_done_q && !rle_busy && busy_q) begin
                    busy_q <= 1'b0;
                    done_q <= 1'b1;
                end
                if (out_valid && out_ready)
                    dst_len_q <= dst_len_q + 32'd1;
            end
        end
    end

    assign irq = done_q;

    wire _unused = &{1'b0, drained, bib_busy, src_len_q, dst_addr_q, 1'b0};

endmodule

`default_nettype wire
