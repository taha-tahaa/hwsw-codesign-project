// ---------------------------------------------------------------------------
// tb_run_expander.v - run_expander + mtf_unit, checked against the software
//
//   iverilog -g2012 -o tb_run tb_run_expander.v rle_stages.v mtf_bwt_engine.v
//   ./tb_run
//
// This is stage 2 of the back end as a whole: RUNA/RUNB expansion feeding the
// move-to-front unit.  The reference is the software loop in
// pyflate_optimized.decode_huffman_block():
//
//     if r <= 1:                      # RUNA = 0, RUNB = 1
//         if repeat == 0: power = 1
//         repeat += power << r
//         power  <<= 1
//         continue
//     elif repeat > 0:
//         buffer += bytes(favourites[0]) * repeat
//         repeat = 0
//     ...
//     o = favourites[r-1];  move-to-front(r-1);  buffer.append(o)
//
// Worked case.  Alphabet A B C D; symbols 2, RUNA, RUNB, 3, EOB:
//
//   sym=2   -> literal, j=1 -> 'B' (0x42); list becomes B A C D
//   sym=0   -> RUNA: power=1, repeat += 1<<0 = 1, power=2
//   sym=1   -> RUNB: repeat += 2<<1 = 4  -> repeat = 5, power = 4
//   sym=3   -> literal, but the run flushes first: five copies of the front
//              byte 'B', then j=2 -> 'C' (0x43); list becomes C B A D
//   sym=EOB -> block_done
//
//   expected stream: 42  42 42 42 42 42  43        (7 bytes)
//
// It also checks the thing that makes this stage worth building: sym_ready
// MUST drop while a run drains, otherwise the decoder would keep pushing
// symbols into a stage that is busy emitting.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_run_expander;

    localparam integer SYM_BITS = 9;
    localparam [SYM_BITS-1:0] EOB = 9'd5;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg                  clear = 1'b0;
    reg  [SYM_BITS-1:0]  sym = 9'd0;
    reg                  sym_valid = 1'b0;
    wire                 sym_ready;

    wire [7:0] mtf_idx, mtf_front, mtf_byte;
    wire       mtf_idx_valid, mtf_byte_valid;
    wire [7:0] byte_out;
    wire       byte_valid;
    wire       block_done;

    reg        load_en   = 1'b0;
    reg  [7:0] load_addr = 8'd0;
    reg  [7:0] load_din  = 8'd0;

    integer errors = 0;
    integer gi = 0;
    integer k;
    reg [7:0] got [0:31];
    reg [7:0] expected [0:6];
    reg       stalled_during_run = 1'b0;
    reg       saw_done = 1'b0;

    run_expander #(.SYM_BITS(SYM_BITS), .CNT_W(21)) u_run (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .sym(sym), .sym_valid(sym_valid), .sym_ready(sym_ready), .eob(EOB),
        .mtf_idx(mtf_idx), .mtf_idx_valid(mtf_idx_valid),
        .mtf_front(mtf_front), .mtf_byte(mtf_byte),
        .mtf_byte_valid(mtf_byte_valid),
        .byte_out(byte_out), .byte_valid(byte_valid),
        .block_done(block_done)
    );

    mtf_unit u_mtf (
        .clk(clk), .rst_n(rst_n),
        .load_en(load_en), .load_addr(load_addr), .load_din(load_din),
        .idx(mtf_idx), .idx_valid(mtf_idx_valid),
        .byte_out(mtf_byte), .byte_valid(mtf_byte_valid), .front(mtf_front)
    );

    // Collect the emitted block bytes.
    always @(posedge clk) begin
        if (rst_n && byte_valid) begin
            got[gi] <= byte_out;
            gi      <= gi + 1;
        end
        if (rst_n && block_done) saw_done <= 1'b1;
        // Back-pressure must actually be exercised.
        if (rst_n && !sym_ready) stalled_during_run <= 1'b1;
    end

    task send_sym(input [SYM_BITS-1:0] s);
        begin
            @(negedge clk);
            sym       = s;
            sym_valid = 1'b1;
            // Wait for a cycle whose rising edge will accept the symbol.
            while (sym_ready !== 1'b1) @(negedge clk);
            @(negedge clk);
            sym_valid = 1'b0;
        end
    endtask

    task load_alphabet;
        integer j;
        begin
            for (j = 0; j < 256; j = j + 1) begin
                @(negedge clk);
                load_en   = 1'b1;
                load_addr = j[7:0];
                load_din  = (j < 4) ? (8'h41 + j[7:0]) : 8'd0;
            end
            @(negedge clk);
            load_en = 1'b0;
        end
    endtask

    initial begin
        expected[0] = 8'h42;
        expected[1] = 8'h42;
        expected[2] = 8'h42;
        expected[3] = 8'h42;
        expected[4] = 8'h42;
        expected[5] = 8'h42;
        expected[6] = 8'h43;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        load_alphabet;

        @(negedge clk);
        clear = 1'b1;
        @(negedge clk);
        clear = 1'b0;

        send_sym(9'd2);     // literal 'B'
        send_sym(9'd0);     // RUNA
        send_sym(9'd1);     // RUNB   -> repeat = 5
        send_sym(9'd3);     // literal 'C', preceded by the flush
        send_sym(EOB);

        repeat (20) @(negedge clk);

        if (gi != 7) begin
            $display("  FAIL: emitted %0d bytes, expected 7", gi);
            errors = errors + 1;
        end else begin
            for (k = 0; k < 7; k = k + 1) begin
                if (got[k] !== expected[k]) begin
                    $display("  FAIL byte %0d: got 0x%02x, want 0x%02x",
                             k, got[k], expected[k]);
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("  ok   7 bytes: 42 x6 then 43, matching the software loop");
        end

        if (!stalled_during_run) begin
            $display("  FAIL: sym_ready never dropped - the run drained with no back-pressure");
            errors = errors + 1;
        end else begin
            $display("  ok   sym_ready dropped while the run drained (real back-pressure)");
        end

        if (!saw_done) begin
            $display("  FAIL: block_done never pulsed after EOB");
            errors = errors + 1;
        end else begin
            $display("  ok   block_done pulsed after EOB, runs flushed");
        end

        $display("");
        if (errors == 0)
            $display("TB PASS: RUNA/RUNB expansion matches the software reference");
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
