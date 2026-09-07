// ---------------------------------------------------------------------------
// ray_sphere_array.v - weight-stationary systolic ray/sphere intersection unit
//
// HW/SW Co-design (00460882) project - accelerator for the raytrace benchmark.
//
// WHY THIS BLOCK EXISTS
// ---------------------
// Ablation showed Sphere.intersectionTime() to be the single most expensive
// piece of the renderer: reverting just its inlining cost +54% runtime.  Every
// primary, shadow and reflection ray is tested against every object, and each
// test is the same fixed shape:
//
//     c    = centre - ray.point                (3 subtractions)
//     v    = c . ray.vector                    (3 mul + 2 add)
//     cc   = c . c                             (3 mul + 2 add)
//     disc = r^2 - (cc - v*v)                  (1 mul + 2 sub)
//     t    = v - sqrt(disc)                    (1 sqrt + 1 sub)
//
// Fixed operand count, fixed latency, no data-dependent control - the exact
// profile a SYSTOLIC ARRAY wants, and the deliberate contrast with the pyflate
// accelerator, whose variable-length codes force a dataflow design instead.
//
// ARCHITECTURE
// ------------
// Sphere parameters are WEIGHT-STATIONARY: (cx, cy, cz, r^2) are preloaded into
// the PEs once per frame and stay there, exactly as the TPU preloads weights
// and then streams activations.  Rays stream through; PE i holds sphere i and
// emits (v_i, disc_i, hit_i) for the ray currently passing it.
//
// The square root is NOT replicated per PE.  sqrt is by far the largest block
// (24 pipeline stages), and one fully pipelined unit retires one candidate per
// cycle.  With N_SPHERES=8 that makes the sqrt the throughput limit at one ray
// per 8 cycles.  Replicating it N times would buy 1 ray/cycle for roughly 8x
// the area - both points are quantified in report_raytrace.txt.  This is the
// performance/area knob the brief asks us to discuss.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
// Fully pipelined binary32 square root.
//
// Uses the classic restoring bit-by-bit integer square root on the significand,
// unrolled into 24 pipeline stages: throughput 1/cycle, latency 24.
//
// Significand scaling.  For x = 1.m * 2^E:
//   E even -> radicand = {1,m} << 23, root = sqrt(1.m)   * 2^23, exp = E/2
//   E odd  -> radicand = {1,m} << 24, root = sqrt(2*1.m) * 2^23, exp = (E-1)/2
// Either way the root lands in [2^23, 2^24), i.e. already normalized with the
// implicit one at bit 23, so no post-normalize shifter is needed.
//
// The root is TRUNCATED, not round-to-nearest.  Measured against math.sqrt()
// over 6006 values (hw/raytrace_mac/sqrt_model.py): worst case 1.16 ulp.
// Adding a 25th stage plus a rounding incrementer brings that to 0.69 ulp, at
// the cost of one more pipeline stage and a 24-bit incrementer in the tail.
// Truncation is kept because 1 ulp of a distance value cannot move an 8-bit
// colour channel.  It does mean the hardware is not bit-identical to
// math.sqrt(), which is why the report compares images with a tolerance rather
// than by MD5 - unlike the pyflate accelerator, which IS bit-exact.
// ---------------------------------------------------------------------------
module fp32_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] x,
    input  wire        in_valid,
    output wire [31:0] y,
    output wire        out_valid
);
    localparam integer N = 24;

    wire        sx = x[31];
    wire [7:0]  ex = x[30:23];
    wire [22:0] mx = x[22:0];

    wire x_zero = (ex == 8'd0);
    wire x_nan  = (ex == 8'hFF) && (mx != 23'd0);
    wire x_inf  = (ex == 8'hFF) && (mx == 23'd0);
    // sqrt of a negative is invalid; the PE guarantees disc >= 0 before issue,
    // so this only guards against a driver programming error.
    wire x_neg  = sx && !x_zero;

    wire signed [9:0] E = $signed({2'b00, ex}) - 10'sd127;
    wire              odd = E[0];
    wire [47:0] radicand = odd ? ({24'd0, 1'b1, mx} << 24)
                               : ({24'd0, 1'b1, mx} << 23);
    wire signed [9:0] exp_out = (E - $signed({9'd0, odd})) >>> 1;

    // Pipeline registers: remainder, partial root, remaining radicand, flags.
    reg [49:0] rem_p  [0:N];
    reg [23:0] root_p [0:N];
    reg [47:0] rad_p  [0:N];
    reg signed [9:0] exp_p [0:N];
    reg        vld_p  [0:N];
    reg        zero_p [0:N], nan_p [0:N], inf_p [0:N];

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j <= N; j = j + 1) begin
                rem_p[j]  <= 50'd0; root_p[j] <= 24'd0; rad_p[j] <= 48'd0;
                exp_p[j]  <= 10'sd0; vld_p[j] <= 1'b0;
                zero_p[j] <= 1'b0;  nan_p[j] <= 1'b0;  inf_p[j] <= 1'b0;
            end
        end else begin
            rem_p[0]  <= 50'd0;
            root_p[0] <= 24'd0;
            rad_p[0]  <= radicand;
            exp_p[0]  <= exp_out;
            vld_p[0]  <= in_valid;
            zero_p[0] <= x_zero;
            nan_p[0]  <= x_nan | x_neg;
            inf_p[0]  <= x_inf;
        end
    end

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_stage
            // Bring down the next two radicand bits, trial-subtract, decide.
            wire [49:0] rem_sh = (rem_p[i] << 2) |
                                 {48'd0, rad_p[i][47:46]};
            wire [49:0] trial  = {24'd0, root_p[i], 2'b01};
            wire        ge     = (rem_sh >= trial);

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    rem_p[i+1]  <= 50'd0; root_p[i+1] <= 24'd0;
                    rad_p[i+1]  <= 48'd0; exp_p[i+1]  <= 10'sd0;
                    vld_p[i+1]  <= 1'b0;
                    zero_p[i+1] <= 1'b0;  nan_p[i+1] <= 1'b0;
                    inf_p[i+1]  <= 1'b0;
                end else begin
                    rem_p[i+1]  <= ge ? (rem_sh - trial) : rem_sh;
                    root_p[i+1] <= {root_p[i][22:0], ge};
                    rad_p[i+1]  <= rad_p[i] << 2;
                    exp_p[i+1]  <= exp_p[i];
                    vld_p[i+1]  <= vld_p[i];
                    zero_p[i+1] <= zero_p[i];
                    nan_p[i+1]  <= nan_p[i];
                    inf_p[i+1]  <= inf_p[i];
                end
            end
        end
    endgenerate

    wire signed [9:0] exp_biased = exp_p[N] + 10'sd127;

    assign y = nan_p[N]  ? {1'b0, 8'hFF, 23'h400000} :
               inf_p[N]  ? {1'b0, 8'hFF, 23'd0}      :
               zero_p[N] ? 32'd0                      :
                           {1'b0, exp_biased[7:0], root_p[N][22:0]};
    assign out_valid = vld_p[N];
endmodule


// ---------------------------------------------------------------------------
// One processing element: holds a sphere, tests one ray per cycle.
//
// Emits v and disc.  The final t = v - sqrt(disc) is completed downstream by
// the shared sqrt unit, so the expensive block is not replicated N times.
// ---------------------------------------------------------------------------
module ray_sphere_pe (
    input  wire        clk,
    input  wire        rst_n,

    // ---- weight load (stationary sphere parameters) -----------------------
    input  wire        w_load,
    input  wire [31:0] w_cx, w_cy, w_cz, w_r2,

    // ---- streaming ray ----------------------------------------------------
    input  wire [31:0] px, py, pz,
    input  wire [31:0] vx, vy, vz,
    input  wire        in_valid,

    output wire [31:0] v_out,
    output wire [31:0] disc_out,
    output wire        hit,
    output wire        out_valid
);
    reg [31:0] cx_q, cy_q, cz_q, r2_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cx_q <= 32'd0; cy_q <= 32'd0; cz_q <= 32'd0; r2_q <= 32'd0;
        end else if (w_load) begin
            cx_q <= w_cx; cy_q <= w_cy; cz_q <= w_cz; r2_q <= w_r2;
        end
    end

    // c = centre - p   (subtract == add with the sign bit flipped)
    wire [31:0] npx = {~px[31], px[30:0]};
    wire [31:0] npy = {~py[31], py[30:0]};
    wire [31:0] npz = {~pz[31], pz[30:0]};

    wire [31:0] cxv, cyv, czv;
    wire cxv_v, cyv_v, czv_v;
    fp32_add u_sx (.clk(clk), .rst_n(rst_n), .a(cx_q), .b(npx),
                   .in_valid(in_valid), .y(cxv), .out_valid(cxv_v));
    fp32_add u_sy (.clk(clk), .rst_n(rst_n), .a(cy_q), .b(npy),
                   .in_valid(in_valid), .y(cyv), .out_valid(cyv_v));
    fp32_add u_sz (.clk(clk), .rst_n(rst_n), .a(cz_q), .b(npz),
                   .in_valid(in_valid), .y(czv), .out_valid(czv_v));

    // Delay the ray direction to meet c at the multipliers (2-cycle add).
    reg [31:0] vx_d1, vy_d1, vz_d1, vx_d2, vy_d2, vz_d2;
    always @(posedge clk) begin
        vx_d1 <= vx;    vy_d1 <= vy;    vz_d1 <= vz;
        vx_d2 <= vx_d1; vy_d2 <= vy_d1; vz_d2 <= vz_d1;
    end

    // v = c . vdir      and     cc = c . c
    wire [31:0] m0, m1, m2, n0, n1, n2;
    wire mv0, mv1, mv2, nv0, nv1, nv2;
    fp32_mul u_m0 (.clk(clk), .rst_n(rst_n), .a(cxv), .b(vx_d2),
                   .in_valid(cxv_v), .y(m0), .out_valid(mv0));
    fp32_mul u_m1 (.clk(clk), .rst_n(rst_n), .a(cyv), .b(vy_d2),
                   .in_valid(cyv_v), .y(m1), .out_valid(mv1));
    fp32_mul u_m2 (.clk(clk), .rst_n(rst_n), .a(czv), .b(vz_d2),
                   .in_valid(czv_v), .y(m2), .out_valid(mv2));
    fp32_mul u_n0 (.clk(clk), .rst_n(rst_n), .a(cxv), .b(cxv),
                   .in_valid(cxv_v), .y(n0), .out_valid(nv0));
    fp32_mul u_n1 (.clk(clk), .rst_n(rst_n), .a(cyv), .b(cyv),
                   .in_valid(cyv_v), .y(n1), .out_valid(nv1));
    fp32_mul u_n2 (.clk(clk), .rst_n(rst_n), .a(czv), .b(czv),
                   .in_valid(czv_v), .y(n2), .out_valid(nv2));

    wire [31:0] ms, mv_sum, ns, nv_sum;
    wire msv, mvv, nsv, nvv;
    fp32_add u_a0 (.clk(clk), .rst_n(rst_n), .a(m0), .b(m1),
                   .in_valid(mv0 & mv1), .y(ms), .out_valid(msv));
    fp32_add u_a1 (.clk(clk), .rst_n(rst_n), .a(ns), .b(n2),
                   .in_valid(nsv), .y(nv_sum), .out_valid(nvv));
    fp32_add u_a2 (.clk(clk), .rst_n(rst_n), .a(n0), .b(n1),
                   .in_valid(nv0 & nv1), .y(ns), .out_valid(nsv));

    reg [31:0] m2_d;
    always @(posedge clk) m2_d <= m2;
    fp32_add u_a3 (.clk(clk), .rst_n(rst_n), .a(ms), .b(m2_d),
                   .in_valid(msv), .y(mv_sum), .out_valid(mvv));

    // disc = r2 - (cc - v*v)
    wire [31:0] vv;
    wire vvv;
    fp32_mul u_vv (.clk(clk), .rst_n(rst_n), .a(mv_sum), .b(mv_sum),
                   .in_valid(mvv), .y(vv), .out_valid(vvv));

    reg [31:0] cc_d;
    always @(posedge clk) cc_d <= nv_sum;
    wire [31:0] nvv_neg = {~vv[31], vv[30:0]};
    wire [31:0] cc_minus;
    wire ccm_v;
    fp32_add u_a4 (.clk(clk), .rst_n(rst_n), .a(cc_d), .b(nvv_neg),
                   .in_valid(vvv), .y(cc_minus), .out_valid(ccm_v));

    wire [31:0] neg_ccm = {~cc_minus[31], cc_minus[30:0]};
    wire [31:0] disc;
    wire disc_v;
    fp32_add u_a5 (.clk(clk), .rst_n(rst_n), .a(r2_q), .b(neg_ccm),
                   .in_valid(ccm_v), .y(disc), .out_valid(disc_v));

    // Delay v to line up with disc.
    reg [31:0] v_d1, v_d2, v_d3, v_d4;
    always @(posedge clk) begin
        v_d1 <= mv_sum; v_d2 <= v_d1; v_d3 <= v_d2; v_d4 <= v_d3;
    end

    assign v_out     = v_d4;
    assign disc_out  = disc;
    assign hit       = disc_v && !disc[31] && (disc[30:23] != 8'd0);
    assign out_valid = disc_v;
endmodule


// ---------------------------------------------------------------------------
// N_SPHERES PEs + one shared sqrt + nearest-hit reduction.
// ---------------------------------------------------------------------------
module ray_sphere_array #(
    parameter integer N_SPHERES = 8
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        w_load,
    input  wire [7:0]  w_idx,
    input  wire [31:0] w_cx, w_cy, w_cz, w_r2,

    input  wire [31:0] px, py, pz,
    input  wire [31:0] vx, vy, vz,
    input  wire        ray_valid,

    output reg  [31:0] t_nearest,
    output reg  [7:0]  obj_nearest,
    output reg         hit_any,
    output reg         result_valid
);
    wire [31:0] v_arr    [0:N_SPHERES-1];
    wire [31:0] disc_arr [0:N_SPHERES-1];
    wire        hit_arr  [0:N_SPHERES-1];
    wire        ov_arr   [0:N_SPHERES-1];

    genvar i;
    generate
        for (i = 0; i < N_SPHERES; i = i + 1) begin : g_pe
            ray_sphere_pe u_pe (
                .clk(clk), .rst_n(rst_n),
                .w_load(w_load && (w_idx == i[7:0])),
                .w_cx(w_cx), .w_cy(w_cy), .w_cz(w_cz), .w_r2(w_r2),
                .px(px), .py(py), .pz(pz),
                .vx(vx), .vy(vy), .vz(vz),
                .in_valid(ray_valid),
                .v_out(v_arr[i]), .disc_out(disc_arr[i]),
                .hit(hit_arr[i]), .out_valid(ov_arr[i])
            );
        end
    endgenerate

    // Serialize the N candidates into the single shared sqrt pipeline.
    reg [7:0]  sel;
    reg [31:0] sq_in;
    reg        sq_in_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel <= 8'd0; sq_in_valid <= 1'b0; sq_in <= 32'd0;
        end else begin
            sq_in       <= disc_arr[sel];
            sq_in_valid <= ov_arr[sel] && hit_arr[sel];
            sel <= (sel == (N_SPHERES-1)) ? 8'd0 : (sel + 8'd1);
        end
    end

    wire [31:0] root;
    wire        root_valid;
    fp32_sqrt u_sqrt (.clk(clk), .rst_n(rst_n), .x(sq_in),
                      .in_valid(sq_in_valid), .y(root), .out_valid(root_valid));

    // t = v - sqrt(disc); track the running minimum over the N candidates.
    // Strict `<` keeps the baseline's tie-break (earliest object wins).
    wire [31:0] neg_root = {~root[31], root[30:0]};
    wire [31:0] t_val;
    wire        t_val_valid;
    fp32_add u_t (.clk(clk), .rst_n(rst_n), .a(v_arr[0]), .b(neg_root),
                  .in_valid(root_valid), .y(t_val), .out_valid(t_val_valid));

    reg [7:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_nearest <= 32'h7F800000;   // +inf
            obj_nearest <= 8'd0; hit_any <= 1'b0;
            result_valid <= 1'b0; cnt <= 8'd0;
        end else begin
            result_valid <= 1'b0;
            if (t_val_valid) begin
                // Positive floats compare correctly as unsigned integers.
                if (!t_val[31] && (t_val[30:0] < t_nearest[30:0])) begin
                    t_nearest   <= t_val;
                    obj_nearest <= cnt;
                    hit_any     <= 1'b1;
                end
                cnt <= (cnt == (N_SPHERES-1)) ? 8'd0 : (cnt + 8'd1);
                if (cnt == (N_SPHERES-1))
                    result_valid <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
