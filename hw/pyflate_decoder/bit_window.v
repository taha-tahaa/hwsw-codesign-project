// ---------------------------------------------------------------------------
// bit_window.v - MSB-first sliding bit window with variable-width retire
//
// Replaces the software RBitfield.  The baseline consumed the stream one BIT
// at a time through a six-deep Python call chain (readbits -> needbits ->
// _more -> _read -> file.read); here a 64-bit barrel shifter presents the next
// MAX_LEN bits combinationally and retires a data-dependent 1..MAX_LEN bits
// per cycle, refilling 32 bits at a time from the input stream.
//
// Interface is valid/ready throughout (dataflow discipline): the window only
// advances when the consumer actually accepted a symbol.
// ---------------------------------------------------------------------------

`default_nettype none

module bit_window #(
    parameter integer MAX_LEN = 20,
    parameter integer WIN_W   = 64
) (
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- 32-bit compressed input stream (from DMA) ------------------------
    input  wire [31:0]          in_data,
    input  wire                 in_valid,
    output wire                 in_ready,
    input  wire                 in_last,

    // ---- Window presented to the decoder ----------------------------------
    output wire [MAX_LEN-1:0]   window,
    output wire                 window_valid,

    // ---- Retire request from the decoder ----------------------------------
    input  wire [4:0]           retire_len,
    input  wire                 retire_en,

    output wire                 drained
);

    // buf_q holds bit_cnt valid bits, left-aligned (MSB = next bit out).
    reg [WIN_W-1:0]      buf_q;
    reg [$clog2(WIN_W+1)-1:0] bit_cnt;
    reg                  last_seen;

    // Refill whenever there is room for a full 32-bit word.
    wire can_refill = (bit_cnt <= (WIN_W - 32));
    assign in_ready = can_refill && !last_seen;

    assign window       = buf_q[WIN_W-1 -: MAX_LEN];
    assign window_valid = (bit_cnt >= MAX_LEN) || (last_seen && bit_cnt != 0);
    assign drained      = last_seen && (bit_cnt == 0);

    wire [WIN_W-1:0] shifted = retire_en ? (buf_q << retire_len) : buf_q;
    wire [$clog2(WIN_W+1)-1:0] cnt_after =
        retire_en ? (bit_cnt - retire_len) : bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_q     <= {WIN_W{1'b0}};
            bit_cnt   <= 0;
            last_seen <= 1'b0;
        end else begin
            // Retire first, then insert the refill word at the free low end so
            // that a retire and a refill can complete in the same cycle.
            if (in_valid && in_ready) begin
                buf_q   <= shifted | ({{(WIN_W-32){1'b0}}, in_data}
                                      << (WIN_W - 32 - cnt_after));
                bit_cnt <= cnt_after + 32;
                if (in_last)
                    last_seen <= 1'b1;
            end else begin
                buf_q   <= shifted;
                bit_cnt <= cnt_after;
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk)
        if (rst_n && retire_en)
            assert (bit_cnt >= retire_len);   // never retire bits we lack
`endif

endmodule

`default_nettype wire
