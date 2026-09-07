// ---------------------------------------------------------------------------
// tb_huffman_decoder.v - self-checking testbench for huffman_decoder.v
//
//   iverilog -g2012 -o tb_huff tb_huffman_decoder.v huffman_decoder.v && ./tb_huff
//
// Table under test (canonical, MSB-first), produced by the same
// build_decode_tables() the optimized Python decoder uses:
//
//   symbol  length  code            perm  = [0,1,2,3,4,5]
//     0       2      00             min_len = 2, max_len = 4
//     1       2      01             limit[2]=2   base[2]=0
//     2       2      10             limit[3]=6   base[3]=3
//     3       3      110            limit[4]=15  base[4]=10
//     4       4      1110
//     5       4      1111
//
// Stimulus is the symbol sequence 0,3,5,2,4,1,3,0 encoded MSB-first:
//   00 110 1111 10 1110 01 110 00   ->  0011011111011100111000  (22 bits)
//
// The test drives the window directly and retires sym_len bits itself, which
// exercises the decoder independently of bit_window.v.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_huffman_decoder;

    localparam integer MAX_LEN  = 20;
    localparam integer SYM_BITS = 9;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg                      tbl_we = 1'b0;
    reg  [4:0]               tbl_len_addr = 5'd0;
    reg  signed [MAX_LEN+1:0] tbl_limit_din = 0;
    reg  signed [MAX_LEN+1:0] tbl_base_din  = 0;
    reg                      tbl_len_valid = 1'b0;

    reg                      perm_we = 1'b0;
    reg  [SYM_BITS-1:0]      perm_addr = 0;
    reg  [SYM_BITS-1:0]      perm_din  = 0;

    reg  [4:0]               min_len = 5'd2;
    reg  [MAX_LEN-1:0]       window = 0;
    reg                      window_valid = 1'b0;

    wire [SYM_BITS-1:0]      sym;
    wire [4:0]               sym_len;
    wire                     sym_valid;

    huffman_decoder #(.MAX_LEN(MAX_LEN), .SYM_BITS(SYM_BITS)) dut (
        .clk(clk), .rst_n(rst_n),
        .tbl_we(tbl_we), .tbl_len_addr(tbl_len_addr),
        .tbl_limit_din(tbl_limit_din), .tbl_base_din(tbl_base_din),
        .tbl_len_valid(tbl_len_valid),
        .perm_we(perm_we), .perm_addr(perm_addr), .perm_din(perm_din),
        .min_len(min_len),
        .window(window), .window_valid(window_valid),
        .sym(sym), .sym_len(sym_len), .sym_valid(sym_valid),
        .sym_ready(1'b1)
    );

    // Bit source: 22 significant bits, left-justified in a 64-bit register.
    reg [63:0] stream = 64'h37DCE00000000000;
    reg [5:0]  consumed = 6'd0;

    localparam integer NSYM = 8;
    reg [8:0] expect_sym [0:NSYM-1];
    reg [4:0] expect_len [0:NSYM-1];

    integer errors = 0;
    integer i;

    task load_len(input [4:0] l, input signed [MAX_LEN+1:0] lim,
                  input signed [MAX_LEN+1:0] bas);
        begin
            @(negedge clk);
            tbl_len_addr  = l;
            tbl_limit_din = lim;
            tbl_base_din  = bas;
            tbl_len_valid = 1'b1;
            tbl_we        = 1'b1;
            @(negedge clk);
            tbl_we        = 1'b0;
        end
    endtask

    task load_perm(input [8:0] a, input [8:0] d);
        begin
            @(negedge clk);
            perm_addr = a; perm_din = d; perm_we = 1'b1;
            @(negedge clk);
            perm_we = 1'b0;
        end
    endtask

    initial begin
        expect_sym[0]=9'd0; expect_len[0]=5'd2;
        expect_sym[1]=9'd3; expect_len[1]=5'd3;
        expect_sym[2]=9'd5; expect_len[2]=5'd4;
        expect_sym[3]=9'd2; expect_len[3]=5'd2;
        expect_sym[4]=9'd4; expect_len[4]=5'd4;
        expect_sym[5]=9'd1; expect_len[5]=5'd2;
        expect_sym[6]=9'd3; expect_len[6]=5'd3;
        expect_sym[7]=9'd0; expect_len[7]=5'd2;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Lengths 2..4 carry codes; 1 and 5..20 do not.
        load_len(5'd2, 2,  0);
        load_len(5'd3, 6,  3);
        load_len(5'd4, 15, 10);
        for (i = 0; i < 6; i = i + 1)
            load_perm(i[8:0], i[8:0]);

        min_len = 5'd2;
        window_valid = 1'b1;

        for (i = 0; i < NSYM; i = i + 1) begin
            window = stream[63 -: MAX_LEN];
            #1;    // settle combinational decode
            if (sym !== expect_sym[i] || sym_len !== expect_len[i]) begin
                $display("FAIL symbol %0d: got sym=%0d len=%0d, expected sym=%0d len=%0d",
                         i, sym, sym_len, expect_sym[i], expect_len[i]);
                errors = errors + 1;
            end else begin
                $display("  ok  symbol %0d: sym=%0d len=%0d", i, sym, sym_len);
            end
            stream   = stream << sym_len;    // retire
            consumed = consumed + sym_len;
            @(negedge clk);
        end

        if (errors == 0)
            $display("\nTB PASS: %0d symbols decoded, %0d bits consumed",
                     NSYM, consumed);
        else
            $display("\nTB FAIL: %0d errors", errors);
        $finish;
    end

endmodule

`default_nettype wire
