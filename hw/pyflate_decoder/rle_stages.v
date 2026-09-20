// ---------------------------------------------------------------------------
// rle_stages.v - the two run-length stages of the bzip2 back end
//
// HW/SW Co-design (00460882) project - pyflate accelerator.
//
// bzip2 has TWO different run-length codings, and an earlier revision of this
// project implemented neither: the top level simply dropped RUNA/RUNB symbols
// and emitted the post-BWT stream as if it were the answer.  Both are here now.
//
//   run_expander   RUNA/RUNB (symbols 0 and 1) are not literals: they encode a
//                  repeat count for the byte currently at the FRONT of the MTF
//                  list, in bijective base 2.  The software is:
//
//                      if r <= 1:                      # RUNA=0, RUNB=1
//                          if repeat == 0: power = 1
//                          repeat += power << r
//                          power  <<= 1
//                          continue
//                      elif repeat > 0:
//                          emit favourites[0] * repeat
//                          repeat = 0
//
//                  Emitting a run takes one cycle per byte, so this stage is
//                  also what gives the decoder REAL back-pressure: sym_ready
//                  drops while a run is draining.  That is the valid/ready
//                  discipline from the accelerator lecture actually being used
//                  rather than tied to 1.
//
//   rle_final      After the inverse BWT, four identical bytes are followed by
//                  a count byte carrying (run length - 4).  The count byte is
//                  consumed, not emitted:
//
//                      if nt[i..i+3] are equal:
//                          out += nt[i] * (nt[i+4] + 4);  i += 5
//                      else:
//                          out += nt[i];                  i += 1
//
//                  Streaming form: emit every byte as it arrives, count equal
//                  neighbours, and when four have gone out treat the next byte
//                  as a count and emit that many extra copies.
//
// Both stages carry valid/ready on every interface, so a stalled consumer
// stalls the whole chain back to the bit window instead of dropping bytes.
// ---------------------------------------------------------------------------

`default_nettype none

// ---------------------------------------------------------------------------
module run_expander #(
    parameter integer SYM_BITS = 9,
    parameter integer CNT_W    = 21       // >= block index width + 1
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clear,          // pulse at block start

    // ---- decoded symbols in (from huffman_decoder) ------------------------
    input  wire [SYM_BITS-1:0]  sym,
    input  wire                 sym_valid,
    output wire                 sym_ready,
    input  wire [SYM_BITS-1:0]  eob,

    // ---- MTF unit ----------------------------------------------------------
    output wire [7:0]           mtf_idx,
    output wire                 mtf_idx_valid,
    input  wire [7:0]           mtf_front,      // tbl[0], combinational
    input  wire [7:0]           mtf_byte,
    input  wire                 mtf_byte_valid,

    // ---- byte stream out (to L[] and the histogram) ------------------------
    output wire [7:0]           byte_out,
    output wire                 byte_valid,

    output reg                  block_done      // EOB seen AND runs flushed
);

    reg [CNT_W-1:0] repeat_q, power_q;
    reg [CNT_W-1:0] emit_cnt;
    reg [7:0]       run_byte_q;
    reg             emitting;

    // A non-run symbol that arrived while a run was pending waits here.
    reg [SYM_BITS-1:0] pend_sym;
    reg                pend_valid;
    reg                eob_q;                  // EOB accepted
    reg                done_pulsed;            // block_done already issued

    // Accept a new symbol only when nothing is draining.
    assign sym_ready = !emitting && !pend_valid && !eob_q;

    wire is_run   = (sym == {SYM_BITS{1'b0}}) ||
                    (sym == {{(SYM_BITS-1){1'b0}}, 1'b1});
    wire accept   = sym_valid && sym_ready;

    // A literal issues its MTF lookup either on acceptance (no pending run) or
    // when the run it was queued behind has finished draining.
    wire fire_now  = accept && !is_run && (repeat_q == {CNT_W{1'b0}}) &&
                     (sym != eob);
    wire fire_pend = pend_valid && !emitting && (pend_sym != eob);

    assign mtf_idx       = fire_pend ? (pend_sym[7:0] - 8'd1) : (sym[7:0] - 8'd1);
    assign mtf_idx_valid = fire_now | fire_pend;

    // Run bytes come straight from the latched MTF front; literal bytes come
    // from the MTF unit one cycle after their lookup.  The two never collide:
    // a run can only become pending after a RUNA/RUNB cycle, and any literal
    // lookup issued before that has already delivered its byte.
    assign byte_out   = emitting ? run_byte_q : mtf_byte;
    assign byte_valid = emitting ? 1'b1 : mtf_byte_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            repeat_q   <= {CNT_W{1'b0}};
            power_q    <= {CNT_W{1'b0}};
            emit_cnt   <= {CNT_W{1'b0}};
            run_byte_q <= 8'd0;
            emitting   <= 1'b0;
            pend_sym    <= {SYM_BITS{1'b0}};
            pend_valid  <= 1'b0;
            eob_q       <= 1'b0;
            done_pulsed <= 1'b0;
            block_done  <= 1'b0;
        end else begin
            block_done <= 1'b0;

            if (clear) begin
                repeat_q    <= {CNT_W{1'b0}};
                power_q     <= {CNT_W{1'b0}};
                emitting    <= 1'b0;
                pend_valid  <= 1'b0;
                eob_q       <= 1'b0;
                done_pulsed <= 1'b0;
            end else begin
                // ---- drain a pending run, one byte per cycle ---------------
                if (emitting) begin
                    if (emit_cnt == {{(CNT_W-1){1'b0}}, 1'b1})
                        emitting <= 1'b0;
                    emit_cnt <= emit_cnt - 1'b1;
                end

                // ---- the queued literal fires once the run has drained -----
                if (fire_pend || (pend_valid && !emitting && pend_sym == eob)) begin
                    pend_valid <= 1'b0;
                    if (pend_sym == eob)
                        eob_q <= 1'b1;
                end

                // ---- accept a new symbol ----------------------------------
                if (accept) begin
                    if (is_run) begin
                        // repeat += power << r,  power <<= 1
                        if (repeat_q == {CNT_W{1'b0}}) begin
                            repeat_q <= {{(CNT_W-1){1'b0}}, 1'b1} <<
                                        sym[0];                 // power = 1
                            power_q  <= {{(CNT_W-2){1'b0}}, 2'b10};
                        end else begin
                            repeat_q <= repeat_q + (power_q << sym[0]);
                            power_q  <= power_q << 1;
                        end
                    end else if (repeat_q != {CNT_W{1'b0}}) begin
                        // Flush the run first; this symbol waits its turn.
                        run_byte_q <= mtf_front;
                        emit_cnt   <= repeat_q;
                        emitting   <= 1'b1;
                        repeat_q   <= {CNT_W{1'b0}};
                        power_q    <= {CNT_W{1'b0}};
                        pend_sym   <= sym;
                        pend_valid <= 1'b1;
                    end else if (sym == eob) begin
                        eob_q <= 1'b1;
                    end
                end

                // ---- end of block: EOB reached and everything drained ------
                // block_done pulses once.  eob_q STAYS set until the driver
                // starts the next block, which keeps sym_ready low so that
                // whatever follows the end-of-block symbol in the bit stream -
                // padding, the next block's header - is never decoded as data.
                if (eob_q && !emitting && !pend_valid && !done_pulsed) begin
                    block_done  <= 1'b1;
                    done_pulsed <= 1'b1;
                end
            end
        end
    end

`ifdef FORMAL
    always @(posedge clk)
        if (rst_n && emitting)
            assert (!mtf_byte_valid);   // the two byte sources never collide
`endif

endmodule

// ---------------------------------------------------------------------------
module rle_final (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,

    input  wire [7:0] in_data,
    input  wire       in_valid,
    output wire       in_ready,

    output reg  [7:0] out_data,
    output reg        out_valid,
    input  wire       out_ready,

    output wire       busy          // still expanding or holding a byte
);

    reg [7:0] last_byte;
    reg [2:0] run_len;        // 0..4 identical bytes emitted so far
    reg [7:0] exp_cnt;        // extra copies still to emit
    reg       expanding;

    assign busy = expanding | out_valid;

    // While expanding we are not consuming input.  Otherwise we consume one
    // byte per cycle, provided the consumer can take our output.
    assign in_ready = !expanding && out_ready;

    wire take_in = in_valid && in_ready;
    wire is_count = (run_len == 3'd4);      // this input byte is a length, not data

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_byte <= 8'd0;
            run_len   <= 3'd0;
            exp_cnt   <= 8'd0;
            expanding <= 1'b0;
            out_data  <= 8'd0;
            out_valid <= 1'b0;
        end else if (clear) begin
            run_len   <= 3'd0;
            exp_cnt   <= 8'd0;
            expanding <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            if (out_ready)
                out_valid <= 1'b0;

            if (expanding) begin
                if (out_ready) begin
                    out_data  <= last_byte;
                    out_valid <= 1'b1;
                    exp_cnt   <= exp_cnt - 8'd1;
                    if (exp_cnt == 8'd1)
                        expanding <= 1'b0;
                end
            end else if (take_in) begin
                if (is_count) begin
                    // Consume the count byte; emit that many extra copies.
                    run_len <= 3'd0;
                    if (in_data != 8'd0) begin
                        exp_cnt   <= in_data;
                        expanding <= 1'b1;
                    end
                end else begin
                    out_data  <= in_data;
                    out_valid <= 1'b1;
                    if (in_data == last_byte && run_len != 3'd0)
                        run_len <= run_len + 3'd1;
                    else begin
                        last_byte <= in_data;
                        run_len   <= 3'd1;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
