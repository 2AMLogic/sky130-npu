// npu_requant -- drain datapath: bias add, requantize, ReLU, saturate to INT8
// (spec section 3.2). Four lanes, one 32-bit result word (four INT8) per cycle.
//
//   t = acc + bias                          (INT32, fits by the bias contract)
//   p = t * mult                            (exact, |p| < 2^47)
//   r = (p + (1 << (shift-1))) >>> shift    (shift > 0, floor / arithmetic)
//   r = p                                   (shift == 0)
//   if relu: r = max(r, 0)
//   out = clamp(r, -128, 127)
//
// Three register stages: t, p, out. in_vld travels with the data; out_vld is
// in_vld delayed by LATENCY cycles. `flush` clears the valid bits (SOFT_RESET).
module npu_requant (
    input  wire         clk,
    input  wire         flush,
    input  wire         in_vld,
    input  wire [127:0] acc4,     // lane j: bits [32*j +: 32]
    input  wire [127:0] bias4,
    input  wire [15:0]  mult,     // UINT16
    input  wire [5:0]   shift,    // 0..47 (checked by the controller)
    input  wire         relu,
    output reg          out_vld,
    output reg  [31:0]  out_word  // byte j = lane j
);

    localparam LATENCY = 3;

    reg                v1, v2;
    reg signed [31:0]  t_q [0:3];
    reg signed [49:0]  p_q [0:3];

    // 50-bit signed: |p| < 2^47 and the rounding term is at most 2^46.
    function [7:0] lane_out;
        input signed [49:0] p;
        input [5:0]         sh;
        input               rl;
        reg signed [49:0]   half;
        reg signed [49:0]   r;
        begin
            half = (sh == 6'd0) ? 50'sd0 : (50'sd1 <<< (sh - 6'd1));
            r    = (p + half) >>> sh;
            if (rl && r < 0)
                lane_out = 8'h00;
            else if (r > 50'sd127)
                lane_out = 8'h7F;
            else if (r < -50'sd128)
                lane_out = 8'h80;
            else
                lane_out = r[7:0];
        end
    endfunction

    integer j;
    always @(posedge clk) begin
        for (j = 0; j < 4; j = j + 1) begin
            t_q[j] <= $signed(acc4[32*j +: 32]) + $signed(bias4[32*j +: 32]);
            p_q[j] <= t_q[j] * $signed({1'b0, mult});
            out_word[8*j +: 8] <= lane_out(p_q[j], shift, relu);
        end
        if (flush) begin
            v1      <= 1'b0;
            v2      <= 1'b0;
            out_vld <= 1'b0;
        end else begin
            v1      <= in_vld;
            v2      <= v1;
            out_vld <= v2;
        end
    end

endmodule
