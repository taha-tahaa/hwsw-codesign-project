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
//
//   bwt_reverse_engine follows the T[] pointer chain to reconstruct the block.
//                     This is a pure pointer chase - the classic irregular,
//                     latency-bound access pattern from the "memory is always
//                     the bottleneck" lecture.  On a CPU every step is a
//                     dependent load that the prefetcher cannot predict.  Here
//                     T[] lives in on-chip SRAM (1-cycle, deterministic), and
//                     because the chain is strictly sequential we overlap the
//                     next index fetch with the current byte write.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
module mtf_unit (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load_en,        // load initial alphabet
    input  wire [7:0]  load_addr,
    input  wire [7:0]  load_din,

    input  wire [7:0]  idx,            // MTF index to look up
    input  wire        idx_valid,
    output reg  [7:0]  byte_out,
    output reg         byte_valid
);

    reg [7:0] tbl [0:255];
    integer i;

    // Combinational read of the selected entry, so the shift and the output
    // both see the pre-shift value.
    wire [7:0] hit_val = tbl[idx];

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

    // T[] and L[] are filled by the histogram pass before `start` is pulsed.
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

    // Reconstructed byte stream out.
    output reg  [7:0]          out_data,
    output reg                 out_valid,
    output reg                 done
);

    reg [IDX_W-1:0] T [0:BLOCK_MAX-1];
    reg [7:0]       L [0:BLOCK_MAX-1];

    reg [IDX_W-1:0] cur;
    reg [IDX_W-1:0] count;
    reg             busy;

    always @(posedge clk) begin
        if (t_we) T[t_waddr] <= t_wdin;
        if (l_we) L[l_waddr] <= l_wdin;
        l_rdata2 <= L[l_raddr2];        // 1-cycle latency, as SRAM
    end

    // The chain is inherently serial: cur <- T[cur].  One byte per cycle at a
    // guaranteed 1-cycle SRAM latency, versus a DRAM-latency dependent load
    // chain on the CPU.  That latency collapse - not raw arithmetic - is where
    // the speedup comes from.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            out_valid <= 1'b0;
            cur       <= {IDX_W{1'b0}};
            count     <= {IDX_W{1'b0}};
        end else begin
            done      <= 1'b0;
            out_valid <= 1'b0;
            if (start) begin
                cur   <= orig_ptr;
                count <= {IDX_W{1'b0}};
                busy  <= (block_len != 0);
            end else if (busy) begin
                cur       <= T[cur];
                out_data  <= L[T[cur]];
                out_valid <= 1'b1;
                count     <= count + 1'b1;
                if (count + 1'b1 == block_len) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
