// ---------------------------------------------------------------------------
// mtf_bwt_engine.v - move-to-front decoder + inverse Burrows-Wheeler engine
//
// Two stages of the bzip2 back end, sitting downstream of huffman_decoder:
//
//   mtf_unit          symbol index -> byte value, and move that entry to the
//                     front of a 256-entry alphabet.  In software this cost a
//                     three-slice list rebuild per symbol (~93k calls).  In
//                     hardware it is a shift-enable across a register file:
//                     every entry below the hit index shifts down by one in a
//                     single cycle, regardless of index.  O(1) instead of O(n).
//                     `front` exposes tbl[0], which the RUNA/RUNB expander
//                     needs: a run repeats the byte currently at the front.
//
//   bwt_reverse_engine follows the T[] pointer chain to reconstruct the block.
//                     This is a pure pointer chase - the classic irregular,
//                     latency-bound access pattern from the "memory is always
//                     the bottleneck" lecture.  On a CPU every step is a
//                     dependent load that the prefetcher cannot predict.
//
//                     MEMORY MODEL.  T[] and L[] are read SYNCHRONOUSLY: the
//                     address is registered and the data appears on the next
//                     cycle, which is what a real on-chip SRAM does.  An
//                     earlier revision read T[cur] and L[T[cur]] in the same
//                     cycle - two dependent reads in one cycle, which only
//                     works with asynchronous-read memory (i.e. flip-flops).
//                     The chase is therefore a two-deep pipeline:
//
//                         cycle k    : issue T[cur]
//                         cycle k+1  : cur' = T[cur] arrives, issue L[cur']
//                         cycle k+2  : L[cur'] arrives -> one output byte
//
//                     After the two-cycle fill it still retires ONE BYTE PER
//                     CYCLE, because the recurrence cur <- T[cur] closes in
//                     exactly one SRAM latency.  That is the whole argument
//                     for putting T[] on-chip: not bandwidth, but a bounded
//                     one-cycle latency on a dependent load.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
module mtf_unit (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load_en,        // load initial alphabet (from CSR)
    input  wire [7:0]  load_addr,
    input  wire [7:0]  load_din,

    input  wire [7:0]  idx,            // MTF index to look up
    input  wire        idx_valid,
    output reg  [7:0]  byte_out,
    output reg         byte_valid,
    output wire [7:0]  front           // tbl[0], for the run expander
);

    reg [7:0] tbl [0:255];
    integer i;

    // Combinational read of the selected entry, so the shift and the output
    // both see the pre-shift value.
    wire [7:0] hit_val = tbl[idx];

    assign front = tbl[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_valid <= 1'b0;
            byte_out   <= 8'd0;
        end else begin
            byte_valid <= idx_valid;
            if (load_en) begin
                tbl[load_addr] <= load_din;
            end else if (idx_valid) begin
                byte_out <= hit_val;
                // Single-cycle move-to-front: shift [0 .. idx-1] down one slot
                // and drop the hit value into slot 0.  Every entry updates in
                // parallel - this is the whole point of doing MTF in hardware.
                for (i = 255; i >= 1; i = i - 1) begin
                    if (i <= idx)
                        tbl[i] <= tbl[i-1];
                end
                tbl[0] <= hit_val;
            end
        end
    end

endmodule

// ---------------------------------------------------------------------------
module bwt_reverse_engine #(
    parameter integer IDX_W    = 20,          // up to 900k block size
    parameter integer BLOCK_MAX = (1<<20)
) (
    input  wire                clk,
    input  wire                rst_n,

    input  wire                start,
    input  wire [IDX_W-1:0]    block_len,
    input  wire [IDX_W-1:0]    orig_ptr,      // bzip2 block header pointer

    // T[] and L[] are filled before `start` is pulsed.
    input  wire                t_we,
    input  wire [IDX_W-1:0]    t_waddr,
    input  wire [IDX_W-1:0]    t_wdin,
    input  wire                l_we,
    input  wire [IDX_W-1:0]    l_waddr,
    input  wire [7:0]          l_wdin,

    // Second read port on L[], used by bwt_index_builder during its scatter
    // pass.  True dual-port SRAM; the builder and the chase never run at the
    // same time, but the port costs nothing to expose.
    input  wire [IDX_W-1:0]    l_raddr2,
    output reg  [7:0]          l_rdata2,

    // Reconstructed byte stream out, with back-pressure from rle_final.
    output reg  [7:0]          out_data,
    output reg                 out_valid,
    input  wire                out_ready,
    output reg                 done
);

    reg [IDX_W-1:0] T [0:BLOCK_MAX-1];
    reg [7:0]       L [0:BLOCK_MAX-1];

    // SRAM model: the address is presented combinationally and captured by the
    // memory at the clock edge; the data appears in the output register on the
    // next cycle.  That is a 1-cycle-latency synchronous SRAM, and it is what
    // lets a DEPENDENT chase run at one hop per cycle: the output register of
    // T[] is the address input of the next read.
    //
    // (Registering the address as well - address register, then data register -
    // would make the chase two cycles per hop, which is what the first version
    // of this testbench caught.)
    reg [IDX_W-1:0] idx_q;       // current chase index e_i, drives both reads
    reg [7:0]       byte_q;      // L[] output register
    reg             primed;      // idx_q holds a real chase index
    reg             byte_vld;    // byte_q holds a real output byte
    reg             busy;
    reg [IDX_W-1:0] count;

    // Stall the whole chase when the consumer cannot take a byte: a clock
    // enable on the memory output registers and on the control state.
    wire adv = out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            out_valid <= 1'b0;
            out_data  <= 8'd0;
            idx_q     <= {IDX_W{1'b0}};
            byte_q    <= 8'd0;
            primed    <= 1'b0;
            byte_vld  <= 1'b0;
            count     <= {IDX_W{1'b0}};
            l_rdata2  <= 8'd0;
        end else begin
            done <= 1'b0;

            // Fill ports and the builder's second read port always run.
            if (t_we) T[t_waddr] <= t_wdin;
            if (l_we) L[l_waddr] <= l_wdin;
            l_rdata2 <= L[l_raddr2];

            if (start) begin
                idx_q     <= orig_ptr;
                primed    <= 1'b0;
                byte_vld  <= 1'b0;
                out_valid <= 1'b0;
                count     <= {IDX_W{1'b0}};
                busy      <= (block_len != {IDX_W{1'b0}});
            end else if (busy && adv) begin
                // One hop and one byte fetch per cycle, both addressed by the
                // index currently in idx_q:
                //     idx_q  <- T[idx_q]      (the next link in the chain)
                //     byte_q <- L[idx_q]      (this link's output byte)
                idx_q    <= T[idx_q];
                byte_q   <= L[idx_q];
                primed   <= 1'b1;
                byte_vld <= primed;      // suppress L[orig_ptr], not an output

                out_valid <= byte_vld;
                out_data  <= byte_q;

                if (byte_vld) begin
                    count <= count + 1'b1;
                    if (count + 1'b1 == block_len) begin
                        busy     <= 1'b0;
                        primed   <= 1'b0;
                        byte_vld <= 1'b0;
                        done     <= 1'b1;
                    end
                end
            end else if (!busy && adv) begin
                out_valid <= 1'b0;
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk)
        if (rst_n && out_valid)
            assert (count <= block_len);
`endif

endmodule

`default_nettype wire
