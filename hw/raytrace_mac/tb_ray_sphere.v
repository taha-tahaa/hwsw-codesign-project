// ---------------------------------------------------------------------------
// tb_ray_sphere.v - self-checking testbench for the raytrace accelerator
//
//   iverilog -g2012 -o tb_ray tb_ray_sphere.v ray_sphere_array.v fp32_units.v
//   ./tb_ray
//
// Three checks, from the primitives upward:
//
//   1. fp32_mul   - 2 * 3 = 6, exactly.
//   2. fp32_add   - 2 + 3 = 5, and 9 + (-4) = 5 (sign-flip subtract path).
//   3. fp32_sqrt  - sqrt(4) = 2, sqrt(9) = 3 exactly; these are the cases the
//                   truncating root must still get bit-exact.
//   4. ray_sphere_pe - the worked intersection below.
//
// Worked intersection (also computed by hand in report_raytrace.txt):
//   sphere centre (0, 0, -10), radius 2  ->  r^2 = 4
//   ray    origin (0, 0,   0), direction (0, 0, -1)   [already unit length]
//
//   c    = centre - origin = (0, 0, -10)
//   v    = c . dir         = 10
//   cc   = c . c           = 100
//   disc = r^2 - (cc - v*v) = 4 - (100 - 100) = 4
//   t    = v - sqrt(disc)   = 10 - 2 = 8
//
// Every intermediate is exactly representable in binary32, so this case must
// be bit-exact end to end - no tolerance needed.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_ray_sphere;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;

    task check(input [127:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %h expected %h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("  ok  %0s = %h", name, got);
            end
        end
    endtask

    // ---------------- primitive: multiplier --------------------------------
    reg  [31:0] mul_a = 32'h40000000;   // 2.0
    reg  [31:0] mul_b = 32'h40400000;   // 3.0
    wire [31:0] mul_y;
    wire        mul_v;
    fp32_mul u_mul (.clk(clk), .rst_n(rst_n), .a(mul_a), .b(mul_b),
                    .in_valid(1'b1), .y(mul_y), .out_valid(mul_v));

    // ---------------- primitive: adder -------------------------------------
    reg  [31:0] add_a = 32'h40000000;   // 2.0
    reg  [31:0] add_b = 32'h40400000;   // 3.0
    wire [31:0] add_y;
    wire        add_v;
    fp32_add u_add (.clk(clk), .rst_n(rst_n), .a(add_a), .b(add_b),
                    .in_valid(1'b1), .y(add_y), .out_valid(add_v));

    // ---------------- primitive: square root -------------------------------
    reg  [31:0] sq_x = 32'h40800000;    // 4.0
    reg         sq_v = 1'b0;
    wire [31:0] sq_y;
    wire        sq_ov;
    fp32_sqrt u_sqrt (.clk(clk), .rst_n(rst_n), .x(sq_x),
                      .in_valid(sq_v), .y(sq_y), .out_valid(sq_ov));

    // ---------------- the PE ------------------------------------------------
    reg         w_load = 1'b0;
    reg         ray_valid = 1'b0;
    wire [31:0] pe_v, pe_disc;
    wire        pe_hit, pe_ov;

    ray_sphere_pe u_pe (
        .clk(clk), .rst_n(rst_n),
        .w_load(w_load),
        .w_cx(32'h00000000), .w_cy(32'h00000000),
        .w_cz(32'hC1200000),                       // -10.0
        .w_r2(32'h40800000),                       //   4.0
        .px(32'h00000000), .py(32'h00000000), .pz(32'h00000000),
        .vx(32'h00000000), .vy(32'h00000000), .vz(32'hBF800000),  // -1.0
        .in_valid(ray_valid),
        .v_out(pe_v), .disc_out(pe_disc), .hit(pe_hit), .out_valid(pe_ov)
    );

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // --- multiplier: 2 * 3 = 6
        repeat (4) @(negedge clk);
        check("fp32_mul 2*3", mul_y, 32'h40C00000);

        // --- adder: 2 + 3 = 5
        repeat (2) @(negedge clk);
        check("fp32_add 2+3", add_y, 32'h40A00000);

        // --- adder subtract path: 9 + (-4) = 5
        add_a = 32'h41100000;   //  9.0
        add_b = 32'hC0800000;   // -4.0
        repeat (4) @(negedge clk);
        check("fp32_add 9-4", add_y, 32'h40A00000);

        // --- sqrt(4) = 2
        sq_x = 32'h40800000;
        sq_v = 1'b1;
        @(negedge clk);
        sq_v = 1'b0;
        repeat (26) @(negedge clk);
        check("fp32_sqrt(4)", sq_y, 32'h40000000);

        // --- sqrt(9) = 3
        sq_x = 32'h41100000;
        sq_v = 1'b1;
        @(negedge clk);
        sq_v = 1'b0;
        repeat (26) @(negedge clk);
        check("fp32_sqrt(9)", sq_y, 32'h40400000);

        // --- the PE: load the sphere, then stream one ray
        w_load = 1'b1;
        @(negedge clk);
        w_load = 1'b0;

        ray_valid = 1'b1;
        @(negedge clk);
        ray_valid = 1'b0;

        repeat (20) @(negedge clk);
        check("pe v",    pe_v,    32'h41200000);   // 10.0
        check("pe disc", pe_disc, 32'h40800000);   //  4.0
        if (pe_hit !== 1'b1) begin
            $display("FAIL pe hit: expected 1");
            errors = errors + 1;
        end else begin
            $display("  ok  pe hit = 1");
        end

        if (errors == 0)
            $display("\nTB PASS: all checks bit-exact");
        else
            $display("\nTB FAIL: %0d errors", errors);
        $finish;
    end

    // Watchdog so a hang in CI fails instead of spinning forever.
    initial begin
        #200000;
        $display("\nTB FAIL: timeout");
        $finish;
    end

endmodule

`default_nettype wire
