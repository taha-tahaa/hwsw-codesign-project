// ---------------------------------------------------------------------------
// tb_rle_final.v - self-checking testbench for rle_final (rle_stages.v)
//
//   iverilog -g2012 -o tb_rle tb_rle_final.v rle_stages.v && ./tb_rle
//
// bzip2's outer run-length coding: four identical bytes are followed by a
// count byte carrying (run length - 4).  The count byte is consumed, not
// emitted.  The software is:
//
//     if nt[i..i+3] are equal:  out += nt[i] * (nt[i+4] + 4);  i += 5
//     else:                     out += nt[i];                  i += 1
//
// Worked case:
//
//   in   41 41 41 41 03 | 42 42 | 43 43 43 43 00 | 44
//   out  41 x (3+4) = 7 | 42 42 | 43 x (0+4) = 4 | 44     -> 14 bytes
//
// The zero count is deliberate: it is the case where four identical bytes are
// followed by no extra copies at all, and an implementation that emits
// "count" instead of "count extra" gets it wrong.
//
// The consumer also stalls on a fixed pattern, because a stage that only works
// when the sink is always ready is not a dataflow stage.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_rle_final;

    localparam integer NIN  = 13;
    localparam integer NOUT = 14;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [7:0] in_data = 8'd0;
    reg        in_valid = 1'b0;
    wire       in_ready;
    wire [7:0] out_data;
    wire       out_valid;
    reg        out_ready = 1'b1;
    wire       busy;

    reg [7:0] stim [0:NIN-1];
    reg [7:0] expected [0:NOUT-1];
    reg [7:0] got [0:63];
    integer   gi = 0;
    integer   errors = 0;
    integer   k;
    reg       saw_stall = 1'b0;

    rle_final dut (
        .clk(clk), .rst_n(rst_n), .clear(1'b0),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .busy(busy)
    );

    // Stall the sink on a fixed, reproducible pattern: ready for three cycles,
    // not ready for one.
    reg [1:0] pat = 2'd0;
    always @(posedge clk) begin
        pat <= pat + 2'd1;
        out_ready <= (pat != 2'd2);
        if (rst_n && !out_ready) saw_stall <= 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            got[gi] <= out_data;
            gi      <= gi + 1;
        end
    end

    task send(input [7:0] b);
        begin
            @(negedge clk);
            in_data  = b;
            in_valid = 1'b1;
            while (in_ready !== 1'b1) @(negedge clk);
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    initial begin
        stim[0]  = 8'h41; stim[1]  = 8'h41; stim[2]  = 8'h41; stim[3] = 8'h41;
        stim[4]  = 8'h03;
        stim[5]  = 8'h42; stim[6]  = 8'h42;
        stim[7]  = 8'h43; stim[8]  = 8'h43; stim[9] = 8'h43; stim[10] = 8'h43;
        stim[11] = 8'h00;
        stim[12] = 8'h44;

        for (k = 0; k < 7; k = k + 1)  expected[k]      = 8'h41;
        expected[7] = 8'h42; expected[8] = 8'h42;
        for (k = 9; k < 13; k = k + 1) expected[k]      = 8'h43;
        expected[13] = 8'h44;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (k = 0; k < NIN; k = k + 1)
            send(stim[k]);

        repeat (60) @(negedge clk);

        if (gi != NOUT) begin
            $display("  FAIL: emitted %0d bytes, expected %0d", gi, NOUT);
            errors = errors + 1;
        end else begin
            for (k = 0; k < NOUT; k = k + 1) begin
                if (got[k] !== expected[k]) begin
                    $display("  FAIL byte %0d: got 0x%02x, want 0x%02x",
                             k, got[k], expected[k]);
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("  ok   14 bytes: 41 x7, 42 x2, 43 x4, 44 - count bytes consumed");
        end

        if (!saw_stall) begin
            $display("  FAIL: the sink never stalled, so back-pressure was not exercised");
            errors = errors + 1;
        end else begin
            $display("  ok   correct through a stalling sink");
        end

        $display("");
        if (errors == 0)
            $display("TB PASS: rle_final matches the software RLE decode");
        else
            $display("TB FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #50000;
        $display("TB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
