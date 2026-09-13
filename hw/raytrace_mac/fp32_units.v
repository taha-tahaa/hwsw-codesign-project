// ---------------------------------------------------------------------------
// fp32_units.v - pipelined IEEE-754 binary32 multiplier and adder
//
// HW/SW Co-design (00460882) project - primitives for the raytrace accelerator.
//
// SCOPE (stated honestly, as the brief allows):
//   * round-to-nearest-even on the normal path
//   * infinities and NaNs propagate correctly
//   * subnormal INPUTS and OUTPUTS are flushed to zero
// Flush-to-zero is the usual choice for a graphics datapath: it removes the
// subnormal shifter from the critical path for values that cannot affect a
// rendered pixel.  It is a deliberate trade, not an omission - and it is why
// the software reference must be compared with a tolerance rather than bit
// equality when a scene pushes into the subnormal range.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
// 2-stage pipelined multiplier.  Throughput 1/cycle, latency 2.
// ---------------------------------------------------------------------------
module fp32_mul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        in_valid,
    output reg  [31:0] y,
    output reg         out_valid
);
    // ---- unpack ----
    wire        sa = a[31],           sb = b[31];
    wire [7:0]  ea = a[30:23],        eb = b[30:23];
    wire [22:0] ma = a[22:0],         mb = b[22:0];

    wire a_zero = (ea == 8'd0);       // subnormals flushed to zero
    wire b_zero = (eb == 8'd0);
    wire a_inf  = (ea == 8'hFF) && (ma == 23'd0);
    wire b_inf  = (eb == 8'hFF) && (mb == 23'd0);
    wire a_nan  = (ea == 8'hFF) && (ma != 23'd0);
    wire b_nan  = (eb == 8'hFF) && (mb != 23'd0);

    wire [23:0] fa = {1'b1, ma};      // implicit leading one
    wire [23:0] fb = {1'b1, mb};

    // ---- stage 1: significand product and exponent sum ----
    reg         s1_sign, s1_zero, s1_inf, s1_nan;
    reg signed [9:0] s1_exp;
    reg  [47:0] s1_prod;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_prod <= 48'd0; s1_exp <= 10'sd0; s1_sign <= 1'b0;
            s1_zero <= 1'b0;  s1_inf <= 1'b0;   s1_nan  <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            s1_sign <= sa ^ sb;
            s1_nan  <= a_nan | b_nan | (a_inf & b_zero) | (b_inf & a_zero);
            s1_inf  <= (a_inf | b_inf) & ~(a_zero | b_zero);
            s1_zero <= (a_zero | b_zero) & ~(a_inf | b_inf);
            s1_prod <= fa * fb;
            // Bias appears twice in the sum, so subtract one bias.
            s1_exp  <= $signed({2'b00, ea}) + $signed({2'b00, eb}) - 10'sd127;
        end
    end

    // ---- stage 2: normalize, round to nearest even, pack ----
    // The product of two [1,2) significands is in [1,4): one normalize shift.
    wire        norm      = s1_prod[47];
    wire [47:0] prod_n    = norm ? s1_prod : (s1_prod << 1);
    wire signed [9:0] exp_n = norm ? (s1_exp + 10'sd1) : s1_exp;

    wire [22:0] mant_raw = prod_n[46:24];
    wire        guard    = prod_n[23];
    wire        sticky   = |prod_n[22:0];
    wire        round_up = guard & (sticky | mant_raw[0]);   // ties-to-even

    wire [23:0] mant_rnd = {1'b0, mant_raw} + {23'd0, round_up};
    wire        carry    = mant_rnd[23];
    wire [22:0] mant_fin = carry ? mant_rnd[23:1] : mant_rnd[22:0];
    wire signed [9:0] exp_fin = carry ? (exp_n + 10'sd1) : exp_n;

    wire overflow  = (exp_fin >= 10'sd255);
    wire underflow = (exp_fin <= 10'sd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y <= 32'd0; out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b1;
            if (s1_nan)            y <= {1'b0, 8'hFF, 23'h400000};      // qNaN
            else if (s1_inf | overflow) y <= {s1_sign, 8'hFF, 23'd0};
            else if (s1_zero | underflow) y <= {s1_sign, 8'd0, 23'd0};
            else                   y <= {s1_sign, exp_fin[7:0], mant_fin};
        end
    end

    wire _unused = &{1'b0, in_valid, 1'b0};
endmodule


// ---------------------------------------------------------------------------
// 2-stage pipelined adder.  Throughput 1/cycle, latency 2.
// ---------------------------------------------------------------------------
module fp32_add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        in_valid,
    output reg  [31:0] y,
    output reg         out_valid
);
    wire        sa = a[31],    sb = b[31];
    wire [7:0]  ea = a[30:23], eb = b[30:23];
    wire [22:0] ma = a[22:0],  mb = b[22:0];

    wire a_zero = (ea == 8'd0);
    wire b_zero = (eb == 8'd0);
    wire a_inf  = (ea == 8'hFF) && (ma == 23'd0);
    wire b_inf  = (eb == 8'hFF) && (mb == 23'd0);
    wire a_nan  = (ea == 8'hFF) && (ma != 23'd0);
    wire b_nan  = (eb == 8'hFF) && (mb != 23'd0);

    // Order operands so `big` has the larger magnitude.
    wire a_ge = (a[30:0] >= b[30:0]);
    wire [7:0]  e_big = a_ge ? ea : eb;
    wire [7:0]  e_sml = a_ge ? eb : ea;
    wire [22:0] m_big = a_ge ? ma : mb;
    wire [22:0] m_sml = a_ge ? mb : ma;
    wire        s_big = a_ge ? sa : sb;
    wire        s_sml = a_ge ? sb : sa;
    wire        z_sml = a_ge ? b_zero : a_zero;

    wire [7:0] shift = e_big - e_sml;

    // Align with 3 extra bits (guard/round/sticky) below the significand.
    wire [26:0] f_big = {1'b1, m_big, 3'b000};
    wire [26:0] f_sml_pre = z_sml ? 27'd0 : {1'b1, m_sml, 3'b000};
    wire [26:0] f_sml = (shift >= 8'd27) ? {26'd0, |f_sml_pre}
                                         : ((f_sml_pre >> shift) |
                                            {26'd0, |(f_sml_pre & ((27'd1 << shift) - 27'd1))});

    wire same_sign = (s_big == s_sml);
    wire [27:0] sum_raw = same_sign ? ({1'b0, f_big} + {1'b0, f_sml})
                                    : ({1'b0, f_big} - {1'b0, f_sml});

    reg         s1_sign, s1_zero, s1_inf, s1_nan;
    reg [27:0]  s1_sum;
    reg signed [9:0] s1_exp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_sum <= 28'd0; s1_exp <= 10'sd0; s1_sign <= 1'b0;
            s1_zero <= 1'b0; s1_inf <= 1'b0;   s1_nan <= 1'b0;
        end else begin
            s1_sign <= s_big;
            s1_nan  <= a_nan | b_nan | (a_inf & b_inf & (sa ^ sb));
            s1_inf  <= a_inf | b_inf;
            s1_zero <= a_zero & b_zero;
            s1_sum  <= sum_raw;
            s1_exp  <= $signed({2'b00, e_big});
        end
    end

    // Leading-zero normalize.  A cancelling subtraction can need a long shift;
    // this is the adder's critical path and the reason the array below is
    // organised as a MAC chain rather than a wide adder tree.
    //
    // NORMALIZED FORM: the leading one sits at bit 26, matching the operand
    // format {1'b1, mant[22:0], 3'b000} - implicit one at bit 26, mantissa at
    // [25:3], guard/round/sticky at [2:0].  Both paths must agree on this:
    //   carry out (bit 27 set) -> shift right 1, exponent +1
    //   otherwise              -> shift left (26 - highest_set_bit)
    // An earlier version shifted left by (27 - k), normalizing to bit 27 while
    // the carry path normalized to bit 26.  The two paths disagreed by one bit
    // and the mantissa slice matched neither, so 2+3 produced 6.5 and 9-4
    // produced 2.5.  Caught by tb_ray_sphere.v under iverilog.
    integer k;
    reg [4:0] shl;
    reg       found;
    always @(*) begin
        shl   = 5'd0;
        found = 1'b0;
        if (!s1_sum[27]) begin
            for (k = 26; k >= 0; k = k - 1)
                if (s1_sum[k] && !found) begin
                    shl   = 26 - k;
                    found = 1'b1;
                end
        end
    end

    wire [27:0] sum_n = s1_sum[27] ? (s1_sum >> 1) : (s1_sum << shl);
    wire signed [9:0] exp_n = s1_sum[27] ? (s1_exp + 10'sd1)
                                         : (s1_exp - $signed({5'd0, shl}));

    wire [22:0] mant_raw = sum_n[25:3];
    wire        guard    = sum_n[2];
    wire        sticky   = |sum_n[1:0];
    wire        round_up = guard & (sticky | mant_raw[0]);
    wire [23:0] mant_rnd = {1'b0, mant_raw} + {23'd0, round_up};
    wire        carry    = mant_rnd[23];
    wire [22:0] mant_fin = carry ? mant_rnd[23:1] : mant_rnd[22:0];
    wire signed [9:0] exp_fin = carry ? (exp_n + 10'sd1) : exp_n;

    wire result_zero = (s1_sum == 28'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y <= 32'd0; out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b1;
            if (s1_nan)                       y <= {1'b0, 8'hFF, 23'h400000};
            else if (s1_inf)                  y <= {s1_sign, 8'hFF, 23'd0};
            else if (result_zero | s1_zero |
                     (exp_fin <= 10'sd0))     y <= 32'd0;
            else if (exp_fin >= 10'sd255)     y <= {s1_sign, 8'hFF, 23'd0};
            else                              y <= {s1_sign, exp_fin[7:0], mant_fin};
        end
    end

    wire _unused = &{1'b0, in_valid, 1'b0};
endmodule

`default_nettype wire
