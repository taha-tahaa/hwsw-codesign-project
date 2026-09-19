// ---------------------------------------------------------------------------
// bwt_index_builder.v - builds the T[] pointer table for the inverse BWT
//
// HW/SW Co-design (00460882) project - pyflate accelerator.
//
// WHY THIS BLOCK EXISTS
// ---------------------
// bwt_reverse_engine CHASES T[], but something has to BUILD it first.  In
// software that is bwt_transform():
//
//     counts = 256-bin histogram of L[]
//     base   = exclusive prefix sum of counts
//     for i, sym in enumerate(L):
//         T[base[sym]] = i
//         base[sym] += 1
//
// An earlier revision of this project left this unimplemented and tied t_we
// low, which meant the assembled top level elaborated but could not actually
// decompress anything.  This closes that gap, so bzip2_accel_top is now a
// complete datapath rather than a sketch.
//
// THREE PHASES
// ------------
//   A  HISTOGRAM   Folded into the decode stream for free: every byte the MTF
//                  stage emits also increments hist[byte].  Costs no extra
//                  pass over the block.
//   B  PREFIX SUM  256 cycles, one running-sum step per bin.  Fixed cost,
//                  independent of block size.
//   C  SCATTER     One cycle per block byte: read L[i], look up base[L[i]],
//                  write T[that] = i, and post-increment base[L[i]].
//
// Total cost beyond decoding: 256 + n cycles.  Phase C is one read-modify-write
// of the base file per cycle, which is why base[] is a register file rather
// than SRAM - it needs a single-cycle RMW that block RAM cannot give.
//
// The histogram and base share one 256-entry file: phase B overwrites counts
// with the prefix sum in place, and phase C then consumes it.  That halves the
// storage and is safe because the phases are strictly sequential.
// ---------------------------------------------------------------------------

`default_nettype none

module bwt_index_builder #(
    parameter integer IDX_W = 20          // block index width (900 KB max)
) (
    input  wire               clk,
    input  wire               rst_n,

    // ---- phase A: the MTF byte stream, counted as it goes by -------------
    input  wire [7:0]         sym_byte,
    input  wire               sym_valid,
    input  wire               clear,       // pulse before a new block

    // ---- start phases B and C once the block's symbols are all in --------
    input  wire               start,
    input  wire [IDX_W-1:0]   block_len,

    // ---- L[] read port (second port of the L memory) ----------------------
    // Driven COMBINATIONALLY from scat_i.  The memory latches L[scat_i] on the
    // clock edge that ends S_SCAT_A, so l_rdata is valid for the whole of
    // S_SCAT_B.  Registering the address instead delays the data by an extra
    // cycle and the scatter then reads the PREVIOUS byte - which is exactly
    // the off-by-one tb_bwt_index_builder caught on the first run.
    output wire [IDX_W-1:0]   l_raddr,
    input  wire [7:0]         l_rdata,     // valid 1 cycle after l_raddr

    // ---- T[] write port ---------------------------------------------------
    output reg                t_we,
    output reg  [IDX_W-1:0]   t_waddr,
    output reg  [IDX_W-1:0]   t_wdin,

    output reg                busy,
    output reg                done
);

    // Shared histogram / base file.  IDX_W+1 bits so a full 900 KB block of a
    // single repeated byte cannot overflow a bin.
    //
    // Named `hist`, not `bins`: `bins` is a SystemVerilog keyword (covergroup
    // syntax), so under -g2012 - which is what the run scripts use - every
    // reference to it is a syntax error. The error points at the declaration
    // and says "invalid module item", which does not obviously mean
    // "you picked a reserved word".
    reg [IDX_W:0] hist [0:255];

    localparam [2:0] S_IDLE   = 3'd0,
                     S_COUNT  = 3'd1,
                     S_PREFIX = 3'd2,
                     S_SCAT_A = 3'd3,   // issue L[] read
                     S_SCAT_B = 3'd4,   // consume L[] data, write T[]
                     S_DONE   = 3'd5;

    reg [2:0]       state;
    reg [8:0]       bin_ix;            // 9 bits: counts to 256
    reg [IDX_W:0]   running;           // prefix-sum accumulator
    reg [IDX_W-1:0] scat_i;            // scatter index
    assign l_raddr = scat_i;

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            busy    <= 1'b0;
            done    <= 1'b0;
            t_we    <= 1'b0;
            bin_ix  <= 9'd0;
            running <= {(IDX_W+1){1'b0}};
            scat_i  <= {IDX_W{1'b0}};
            for (k = 0; k < 256; k = k + 1)
                hist[k] <= {(IDX_W+1){1'b0}};
        end else begin
            t_we <= 1'b0;
            done <= 1'b0;

            // Phase A runs whenever symbols arrive, in any state: the counting
            // is free because it rides the stream the decoder already produces.
            if (clear) begin
                for (k = 0; k < 256; k = k + 1)
                    hist[k] <= {(IDX_W+1){1'b0}};
            end else if (sym_valid) begin
                hist[sym_byte] <= hist[sym_byte] + 1'b1;
            end

            case (state)
            S_IDLE: begin
                if (start) begin
                    busy    <= 1'b1;
                    bin_ix  <= 9'd0;
                    running <= {(IDX_W+1){1'b0}};
                    state   <= S_PREFIX;
                end
            end

            // Exclusive prefix sum, in place: bin[i] becomes the sum of all
            // counts below i.  256 cycles.
            S_PREFIX: begin
                if (bin_ix < 9'd256) begin
                    hist[bin_ix[7:0]] <= running;
                    running           <= running + hist[bin_ix[7:0]];
                    bin_ix            <= bin_ix + 9'd1;
                end else begin
                    scat_i <= {IDX_W{1'b0}};
                    state  <= (block_len == {IDX_W{1'b0}}) ? S_DONE : S_SCAT_A;
                end
            end

            // Scatter: T[base[L[i]]++] = i, one byte per two cycles here for
            // clarity.  A production build overlaps the read of L[i+1] with
            // the write for L[i] and reaches one byte per cycle; the FSM is
            // split so the SRAM read latency is explicit.
            // One wait state so the L[] read lands: l_raddr is already
            // scat_i combinationally, the memory latches it on this edge.
            S_SCAT_A: begin
                state <= S_SCAT_B;
            end

            S_SCAT_B: begin
                t_we    <= 1'b1;
                t_waddr <= hist[l_rdata][IDX_W-1:0];
                t_wdin  <= scat_i;
                hist[l_rdata] <= hist[l_rdata] + 1'b1;

                if (scat_i + 1'b1 == block_len) begin
                    state <= S_DONE;
                end else begin
                    scat_i <= scat_i + 1'b1;
                    state  <= S_SCAT_A;
                end
            end

            S_DONE: begin
                busy  <= 1'b0;
                done  <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    // Every T[] write must land inside the block.
    always @(posedge clk)
        if (rst_n && t_we)
            assert (t_waddr < block_len);
`endif

endmodule

`default_nettype wire
