// ---------------------------------------------------------------------------
// tb_ray_array.v - array-level testbench for ray_sphere_array
//
//   iverilog -g2012 -o tb_arr tb_ray_array.v ray_sphere_array.v fp32_units.v
//   ./tb_arr
//
// WHY THIS EXISTS
// ---------------
// tb_ray_sphere.v verifies ONE processing element against ONE sphere, and it
// passed while the array around it was wrong in four separate ways: t was
// always computed from sphere 0's v, no pipeline carried the candidate's
// identity across the 25-cycle sqrt, the index counter advanced only on hits,
// and the running minimum was never re-initialized between rays.  A PE-level
// test cannot see any of that.
//
// This testbench checks the thing that actually matters at the array level:
// with several spheres in front of the ray, does the unit report the NEAREST
// one, and does it name the right sphere?
//
// SCENE (ray origin (0,0,0), direction (0,0,-1), all radii give exact results)
//
//   sphere 0: centre (0,0,-20) r=2  -> v=20, cc=400, disc=4,  t = 20-2 = 18
//   sphere 1: centre (0,0,-10) r=2  -> v=10, cc=100, disc=4,  t = 10-2 =  8  <- nearest
//   sphere 2: centre (0,0,-14) r=2  -> v=14, cc=196, disc=4,  t = 14-2 = 12
//   spheres 3..7: centre (100,0,0) r=1 -> v=0, cc=10000, disc=1-10000 <0 -> MISS
//
// Expected: hit_any = 1, t_nearest = 8.0 (0x41000000), obj_nearest = 1.
//
// Under the old code this reported t computed from sphere 0's v for every
// candidate, so it failed immediately.
// ---------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_ray_array;

    localparam integer N = 8;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         w_load = 1'b0;
    reg  [7:0]  w_idx  = 8'd0;
    reg  [31:0] w_cx = 0, w_cy = 0, w_cz = 0, w_r2 = 0;

    reg  [31:0] px = 32'h00000000, py = 32'h00000000, pz = 32'h00000000;
    reg  [31:0] vx = 32'h00000000, vy = 32'h00000000, vz = 32'hBF800000; // (0,0,-1)
    reg         ray_valid = 1'b0;

    wire        ray_ready;
    wire [31:0] t_nearest;
    wire [7:0]  obj_nearest;
    wire        hit_any;
    wire        result_valid;

    ray_sphere_array #(.N_SPHERES(N)) dut (
        .clk(clk), .rst_n(rst_n),
        .w_load(w_load), .w_idx(w_idx),
        .w_cx(w_cx), .w_cy(w_cy), .w_cz(w_cz), .w_r2(w_r2),
        .px(px), .py(py), .pz(pz),
        .vx(vx), .vy(vy), .vz(vz),
        .ray_valid(ray_valid),
        .ray_ready(ray_ready),
        .t_nearest(t_nearest), .obj_nearest(obj_nearest),
        .hit_any(hit_any), .result_valid(result_valid)
    );

    integer errors = 0;
    integer i;
    integer waited;

    task load(input [7:0] idx, input [31:0] cx, input [31:0] cy,
              input [31:0] cz, input [31:0] r2);
        begin
            @(negedge clk);
            w_idx = idx; w_cx = cx; w_cy = cy; w_cz = cz; w_r2 = r2;
            w_load = 1'b1;
            @(negedge clk);
            w_load = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Weight-stationary load: spheres stay put while rays stream.
        load(8'd0, 32'h00000000, 32'h00000000, 32'hC1A00000, 32'h40800000); // -20, r2=4
        load(8'd1, 32'h00000000, 32'h00000000, 32'hC1200000, 32'h40800000); // -10, r2=4
        load(8'd2, 32'h00000000, 32'h00000000, 32'hC1600000, 32'h40800000); // -14, r2=4
        for (i = 3; i < N; i = i + 1)
            load(i[7:0], 32'h42C80000, 32'h00000000, 32'h00000000, 32'h3F800000); // (100,0,0) r2=1

        // One ray.
        @(negedge clk);
        ray_valid = 1'b1;
        @(negedge clk);
        ray_valid = 1'b0;

        // Wait for the result: PE ~14 + capture 1 + serialize 8 + sqrt 25 + add 2.
        waited = 0;
        while (result_valid !== 1'b1 && waited < 400) begin
            @(negedge clk);
            waited = waited + 1;
        end

        if (result_valid !== 1'b1) begin
            $display("FAIL: no result_valid within %0d cycles", waited);
            errors = errors + 1;
        end else begin
            $display("  result after %0d cycles", waited);

            if (hit_any !== 1'b1) begin
                $display("FAIL hit_any: got %b expected 1", hit_any);
                errors = errors + 1;
            end else $display("  ok  hit_any = 1");

            if (t_nearest !== 32'h41000000) begin
                $display("FAIL t_nearest: got %h expected 41000000 (8.0)", t_nearest);
                errors = errors + 1;
            end else $display("  ok  t_nearest = %h (8.0, the nearest sphere)", t_nearest);

            if (obj_nearest !== 8'd1) begin
                $display("FAIL obj_nearest: got %0d expected 1", obj_nearest);
                errors = errors + 1;
            end else $display("  ok  obj_nearest = 1");
        end

        if (errors == 0)
            $display("\nTB PASS: nearest-hit selection correct across %0d spheres", N);
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
