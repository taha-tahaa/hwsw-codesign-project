// ---------------------------------------------------------------------------
// tb_bwt_reverse.v - self-checking testbench for bwt_reverse_engine
//
//   iverilog -g2012 -o tb_rev tb_bwt_reverse.v mtf_bwt_engine.v && ./tb_rev
//
// The pointer chase that the whole accelerator exists for.  Vectors come from
// the project's own software, not from hand calculation:
//
//     S    = "banana_bandana!"
//     L    = last column of the sorted rotations of S
//     orig = index of S among those rotations          = 8
//     T    = counting sort of L (what bwt_index_builder produces)
//     out  = pyflate_optimized.bwt_reverse(L, orig)    = S
//
// So a correct engine reproduces the original string exactly.
//
// Two things are checked that the old engine could not have passed:
//
//   1. The memories are read SYNCHRONOUSLY here - address registered, data one
//      cycle later - which is what an on-chip SRAM does.  The previous version
//      read T[cur] and L[T[cur]] in the same cycle, two dependent reads in one
//      cycle, which only works with asynchronous-read memory.
//   2. The sink stalls on a fixed pattern.  A chase that drops or duplicates a
//      byte when out_ready falls is wrong even if the byte order looks right.
//
// This block previously had NO testbench while the report claimed it was
// individually verified.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_bwt_reverse;

    localparam integer IDX_W = 20;
    localparam integer N     = 15;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg              start = 1'b0;
    reg  [IDX_W-1:0] block_len = N;
    reg  [IDX_W-1:0] orig_ptr  = 20'd8;

    reg              t_we = 1'b0;
    reg  [IDX_W-1:0] t_waddr = {IDX_W{1'b0}}, t_wdin = {IDX_W{1'b0}};
    reg              l_we = 1'b0;
    reg  [IDX_W-1:0] l_waddr = {IDX_W{1'b0}};
    reg  [7:0]       l_wdin = 8'd0;

    wire [7:0] out_data;
    wire       out_valid;
    reg        out_ready = 1'b1;
    wire       done;
    wire [7:0] l_rdata2;

    reg [7:0]       Lvec [0:N-1];
    reg [IDX_W-1:0] Tvec [0:N-1];
    reg [7:0]       expected [0:N-1];
    reg [7:0]       got [0:63];
    integer         gi = 0;
    integer         errors = 0;
    integer         k;
    reg             saw_stall = 1'b0;
    reg             saw_done  = 1'b0;

    bwt_reverse_engine #(.IDX_W(IDX_W), .BLOCK_MAX(64)) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .block_len(block_len), .orig_ptr(orig_ptr),
        .t_we(t_we), .t_waddr(t_waddr), .t_wdin(t_wdin),
        .l_we(l_we), .l_waddr(l_waddr), .l_wdin(l_wdin),
        .l_raddr2({IDX_W{1'b0}}), .l_rdata2(l_rdata2),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .done(done)
    );

    // Reproducible stall pattern: ready, ready, stall, ready ...
    reg [1:0] pat = 2'd0;
    always @(posedge clk) begin
        pat       <= pat + 2'd1;
        out_ready <= (pat != 2'd2);
        if (rst_n && !out_ready) saw_stall <= 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            got[gi] <= out_data;
            gi      <= gi + 1;
        end
        if (rst_n && done) saw_done <= 1'b1;
    end

    initial begin
        // L = last column of the sorted rotations of "banana_bandana!"
        Lvec[0]='h61; Lvec[1]='h61; Lvec[2]='h6e; Lvec[3]='h6e; Lvec[4]='h64;
        Lvec[5]='h6e; Lvec[6]='h62; Lvec[7]='h62; Lvec[8]='h21; Lvec[9]='h5f;
        Lvec[10]='h6e; Lvec[11]='h61; Lvec[12]='h61; Lvec[13]='h61; Lvec[14]='h61;

        // T = counting sort of L, exactly what bwt_index_builder writes.
        Tvec[0]=8;  Tvec[1]=9;  Tvec[2]=0;  Tvec[3]=1;  Tvec[4]=11;
        Tvec[5]=12; Tvec[6]=13; Tvec[7]=14; Tvec[8]=6;  Tvec[9]=7;
        Tvec[10]=4; Tvec[11]=2; Tvec[12]=3; Tvec[13]=5; Tvec[14]=10;

        // expected = "banana_bandana!"
        expected[0]='h62; expected[1]='h61; expected[2]='h6e; expected[3]='h61;
        expected[4]='h6e; expected[5]='h61; expected[6]='h5f; expected[7]='h62;
        expected[8]='h61; expected[9]='h6e; expected[10]='h64; expected[11]='h61;
        expected[12]='h6e; expected[13]='h61; expected[14]='h21;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // Fill L[] and T[] the way the decode stages would.
        for (k = 0; k < N; k = k + 1) begin
            @(negedge clk);
            l_we = 1'b1; l_waddr = k[IDX_W-1:0]; l_wdin = Lvec[k];
            t_we = 1'b1; t_waddr = k[IDX_W-1:0]; t_wdin = Tvec[k];
        end
        @(negedge clk);
        l_we = 1'b0; t_we = 1'b0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        repeat (120) @(negedge clk);

        if (gi != N) begin
            $display("  FAIL: emitted %0d bytes, expected %0d", gi, N);
            errors = errors + 1;
        end else begin
            for (k = 0; k < N; k = k + 1) begin
                if (got[k] !== expected[k]) begin
                    $display("  FAIL byte %0d: got 0x%02x, want 0x%02x",
                             k, got[k], expected[k]);
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("  ok   15 bytes reconstructed: \"banana_bandana!\"");
        end

        if (!saw_stall) begin
            $display("  FAIL: the sink never stalled, so the stall path is untested");
            errors = errors + 1;
        end else begin
            $display("  ok   byte stream correct through a stalling sink");
        end

        if (!saw_done) begin
            $display("  FAIL: done never asserted");
            errors = errors + 1;
        end else begin
            $display("  ok   done asserted at the end of the block");
        end

        $display("");
        if (errors == 0)
            $display("TB PASS: inverse BWT matches the software reference");
        else
            $display("TB FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("TB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
