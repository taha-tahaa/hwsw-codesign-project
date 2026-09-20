// ---------------------------------------------------------------------------
// tb_mtf_unit.v - self-checking testbench for mtf_unit (mtf_bwt_engine.v)
//
//   iverilog -g2012 -o tb_mtf tb_mtf_unit.v mtf_bwt_engine.v && ./tb_mtf
//
// The software this replaces is one line:
//
//     o = favourites[j];  favourites.insert(0, favourites.pop(j))
//
// so the hardware must return the entry at the index BEFORE the move, and the
// list must end up with that entry at the front and everything above it
// shifted down by one.  Worked case, alphabet A B C D:
//
//   idx=2 -> 'C' (0x43), list becomes C A B D      (front = 0x43)
//   idx=0 -> 'C' again,  list unchanged            (front = 0x43)
//   idx=3 -> 'D' (0x44), list becomes D C A B      (front = 0x44)
//   idx=2 -> 'A' (0x41), list becomes A D C B      (front = 0x41)
//
// This block previously had NO testbench while the report claimed it was
// individually verified.  That claim is now true.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_mtf_unit;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg        load_en   = 1'b0;
    reg  [7:0] load_addr = 8'd0;
    reg  [7:0] load_din  = 8'd0;
    reg  [7:0] idx       = 8'd0;
    reg        idx_valid = 1'b0;

    wire [7:0] byte_out, front;
    wire       byte_valid;

    integer errors = 0;
    integer i;

    mtf_unit dut (
        .clk(clk), .rst_n(rst_n),
        .load_en(load_en), .load_addr(load_addr), .load_din(load_din),
        .idx(idx), .idx_valid(idx_valid),
        .byte_out(byte_out), .byte_valid(byte_valid), .front(front)
    );

    task load_alphabet;
        integer k;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                @(negedge clk);
                load_en   = 1'b1;
                load_addr = k[7:0];
                load_din  = (k < 4) ? (8'h41 + k[7:0]) : 8'd0;   // A B C D 0...
            end
            @(negedge clk);
            load_en = 1'b0;
        end
    endtask

    // Look up one index and check the byte that comes back one cycle later.
    task lookup(input [7:0] want_idx, input [7:0] want_byte,
                input [7:0] want_front);
        begin
            @(negedge clk);
            idx       = want_idx;
            idx_valid = 1'b1;
            @(negedge clk);
            idx_valid = 1'b0;
            if (byte_valid !== 1'b1) begin
                $display("  FAIL idx=%0d: byte_valid not asserted", want_idx);
                errors = errors + 1;
            end else if (byte_out !== want_byte) begin
                $display("  FAIL idx=%0d: got 0x%02x, want 0x%02x",
                         want_idx, byte_out, want_byte);
                errors = errors + 1;
            end else if (front !== want_front) begin
                $display("  FAIL idx=%0d: front 0x%02x, want 0x%02x",
                         want_idx, front, want_front);
                errors = errors + 1;
            end else begin
                $display("  ok   idx=%0d -> 0x%02x, front now 0x%02x",
                         want_idx, byte_out, front);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        load_alphabet;
        if (front !== 8'h41) begin
            $display("  FAIL after load: front 0x%02x, want 0x41", front);
            errors = errors + 1;
        end

        lookup(8'd2, 8'h43, 8'h43);   // C to the front
        lookup(8'd0, 8'h43, 8'h43);   // already at the front: no change
        lookup(8'd3, 8'h44, 8'h44);   // D to the front
        lookup(8'd2, 8'h41, 8'h41);   // A to the front

        // A quiet cycle must not disturb the list.
        @(negedge clk);
        if (front !== 8'h41) begin
            $display("  FAIL idle cycle changed the front");
            errors = errors + 1;
        end

        $display("");
        if (errors == 0)
            $display("TB PASS: mtf_unit returns the pre-move entry and reorders correctly");
        else
            $display("TB FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #20000;
        $display("TB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
