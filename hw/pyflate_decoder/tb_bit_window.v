// ---------------------------------------------------------------------------
// tb_bit_window.v - testbench for bit_window.v
//
//   iverilog -g2012 -o tb_win tb_bit_window.v bit_window.v && ./tb_win
//
// WHY THIS EXISTS
// ---------------
// bit_window was the only datapath block in the pyflate accelerator with no
// test of its own: huffman_decoder was verified standalone with the window
// driven directly by the testbench, and bzip2_accel_top was only elaborated,
// never simulated.  A variable-width retire with a simultaneous refill is
// exactly the kind of logic that looks obviously right and is not.
//
// WHAT IS CHECKED
// ---------------
// A known bit pattern is streamed in 32 bits at a time and retired in an
// irregular sequence of widths (3, 1, 20, 7, 13, 5, 11, 20...).  After each
// retire the window must equal the next MAX_LEN bits of the reference stream.
// That covers:
//   * retire widths from 1 up to MAX_LEN
//   * a retire and a refill landing in the same cycle
//   * the window staying correct across word boundaries
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_bit_window;

    localparam integer MAX_LEN = 20;
    localparam integer WIN_W   = 64;
    localparam integer NWORDS  = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [31:0] in_data;
    reg         in_valid = 1'b0;
    reg         in_last  = 1'b0;
    wire        in_ready;

    wire [MAX_LEN-1:0] window;
    wire               window_valid;
    reg  [4:0]         retire_len = 5'd0;
    reg                retire_en  = 1'b0;
    wire               drained;

    bit_window #(.MAX_LEN(MAX_LEN), .WIN_W(WIN_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .in_last(in_last),
        .window(window), .window_valid(window_valid),
        .retire_len(retire_len), .retire_en(retire_en),
        .drained(drained)
    );

    // Reference: the same bits as one long vector, MSB first.
    reg [31:0] words [0:NWORDS-1];
    reg [NWORDS*32-1:0] ref_bits;
    integer bitpos;          // how many bits have been retired so far
    integer errors = 0;
    integer widx;
    integer i, k;

    // Irregular retire widths, including 1 and MAX_LEN.
    reg [4:0] widths [0:11];

    function [MAX_LEN-1:0] ref_window(input integer pos);
        integer b;
        begin
            ref_window = {MAX_LEN{1'b0}};
            for (b = 0; b < MAX_LEN; b = b + 1)
                ref_window[MAX_LEN-1-b] = ref_bits[NWORDS*32-1-(pos+b)];
        end
    endfunction

    initial begin
        words[0] = 32'h37DCE001; words[1] = 32'hA5A5F00F;
        words[2] = 32'h89ABCDEF; words[3] = 32'hDEADBEEF;
        words[4] = 32'h00FF00FF; words[5] = 32'h5555AAAA;
        words[6] = 32'hCAFEBABE; words[7] = 32'h13579BDF;

        for (i = 0; i < NWORDS; i = i + 1)
            for (k = 0; k < 32; k = k + 1)
                ref_bits[NWORDS*32-1-(i*32+k)] = words[i][31-k];

        widths[0]=5'd3;  widths[1]=5'd1;  widths[2]=5'd20; widths[3]=5'd7;
        widths[4]=5'd13; widths[5]=5'd5;  widths[6]=5'd11; widths[7]=5'd20;
        widths[8]=5'd2;  widths[9]=5'd17; widths[10]=5'd9; widths[11]=5'd4;

        bitpos = 0;
        widx   = 0;
        in_data = words[0];

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
    end

    // Feed words whenever the window has room.
    always @(negedge clk) begin
        if (rst_n && in_ready && widx < NWORDS) begin
            in_data  = words[widx];
            in_valid = 1'b1;
            in_last  = (widx == NWORDS-1);
            widx     = widx + 1;
        end else begin
            in_valid = 1'b0;
        end
    end

    integer step;
    initial begin
        @(posedge rst_n);
        // let the window fill
        repeat (6) @(negedge clk);

        for (step = 0; step < 12; step = step + 1) begin
            @(negedge clk);
            if (!window_valid) begin
                $display("FAIL step %0d: window not valid", step);
                errors = errors + 1;
            end else if (window !== ref_window(bitpos)) begin
                $display("FAIL step %0d: window=%05h expected %05h (bitpos %0d)",
                         step, window, ref_window(bitpos), bitpos);
                errors = errors + 1;
            end else begin
                $display("  ok  step %0d: window=%05h after %0d bits, retiring %0d",
                         step, window, bitpos, widths[step]);
            end
            retire_len = widths[step];
            retire_en  = 1'b1;
            bitpos     = bitpos + widths[step];
            @(negedge clk);
            retire_en  = 1'b0;
        end

        if (errors == 0)
            $display("\nTB PASS: %0d retires, %0d bits consumed, window correct throughout",
                     12, bitpos);
        else
            $display("\nTB FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("\nTB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
