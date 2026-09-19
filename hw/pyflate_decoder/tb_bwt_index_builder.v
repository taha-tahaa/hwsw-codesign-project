// ---------------------------------------------------------------------------
// tb_bwt_index_builder.v - self-checking testbench for bwt_index_builder.v
//
//   iverilog -g2012 -o tb_bib tb_bwt_index_builder.v bwt_index_builder.v
//   ./tb_bib
//
// Worked case: L = "banana" = 62 61 6E 61 6E 61
//
//   histogram      'a'(0x61) = 3   'b'(0x62) = 1   'n'(0x6E) = 2
//   prefix sum     base['a'] = 0   base['b'] = 3   base['n'] = 4
//
//   scatter, i = 0..5:
//     i=0 'b' -> T[3]=0, base['b']=4
//     i=1 'a' -> T[0]=1, base['a']=1
//     i=2 'n' -> T[4]=2, base['n']=5
//     i=3 'a' -> T[1]=3, base['a']=2
//     i=4 'n' -> T[5]=4, base['n']=6
//     i=5 'a' -> T[2]=5, base['a']=3
//
//   expected T = [1, 3, 5, 0, 2, 4]
//
// Those values were produced by running the project's own reference algorithm
// in Python, not derived by hand, so the testbench and the software agree by
// construction rather than by hope.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_bwt_index_builder;

    localparam integer IDX_W = 20;
    localparam integer N     = 6;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [7:0]       sym_byte  = 8'd0;
    reg              sym_valid = 1'b0;
    reg              clear     = 1'b0;
    reg              start     = 1'b0;
    reg  [IDX_W-1:0] block_len = N;

    wire [IDX_W-1:0] l_raddr;
    wire             t_we;
    wire [IDX_W-1:0] t_waddr, t_wdin;
    wire             busy, done;

    // L[] memory, modelling the second read port with 1-cycle latency.
    reg [7:0] Lmem [0:N-1];
    reg [7:0] l_rdata;
    always @(posedge clk) l_rdata <= Lmem[l_raddr];

    // T[] memory the builder writes into.
    reg [IDX_W-1:0] Tmem [0:N-1];
    always @(posedge clk) if (t_we) Tmem[t_waddr] <= t_wdin;

    bwt_index_builder #(.IDX_W(IDX_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .sym_byte(sym_byte), .sym_valid(sym_valid), .clear(clear),
        .start(start), .block_len(block_len),
        .l_raddr(l_raddr), .l_rdata(l_rdata),
        .t_we(t_we), .t_waddr(t_waddr), .t_wdin(t_wdin),
        .busy(busy), .done(done)
    );

    reg [IDX_W-1:0] expect_T [0:N-1];
    integer i, errors = 0, waited;

    initial begin
        Lmem[0] = 8'h62; Lmem[1] = 8'h61; Lmem[2] = 8'h6E;
        Lmem[3] = 8'h61; Lmem[4] = 8'h6E; Lmem[5] = 8'h61;

        expect_T[0] = 1; expect_T[1] = 3; expect_T[2] = 5;
        expect_T[3] = 0; expect_T[4] = 2; expect_T[5] = 4;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Phase A: stream the block's bytes past the builder, exactly as the
        // MTF stage would. The histogram rides the stream for free.
        clear = 1'b1; @(negedge clk); clear = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            sym_byte  = Lmem[i];
            sym_valid = 1'b1;
            @(negedge clk);
        end
        sym_valid = 1'b0;
        @(negedge clk);

        // Phases B and C.
        start = 1'b1; @(negedge clk); start = 1'b0;

        waited = 0;
        while (done !== 1'b1 && waited < 2000) begin
            @(negedge clk);
            waited = waited + 1;
        end

        if (done !== 1'b1) begin
            $display("FAIL: builder never asserted done (%0d cycles)", waited);
            errors = errors + 1;
        end else begin
            $display("  built T[] in %0d cycles (256 prefix + %0d scatter)",
                     waited, N);
            for (i = 0; i < N; i = i + 1) begin
                if (Tmem[i] !== expect_T[i]) begin
                    $display("FAIL T[%0d] = %0d, expected %0d",
                             i, Tmem[i], expect_T[i]);
                    errors = errors + 1;
                end else begin
                    $display("  ok  T[%0d] = %0d", i, Tmem[i]);
                end
            end
        end

        if (errors == 0)
            $display("\nTB PASS: T[] matches the software reference exactly");
        else
            $display("\nTB FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("\nTB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
