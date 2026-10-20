// npu_pe -- one processing element (spec section 2, decision 0001).
//
// Output-stationary: acc += a * b every cycle, INT8 x INT8 -> INT32. a and b
// are also registered and forwarded east / south, which gives the k + m + n
// skew. Idle cycles feed zeros, which add nothing, so no valid bit is needed
// inside the array; only `clr` (start of a tile) is.
module npu_pe (
    input  wire               clk,
    input  wire               clr,
    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,
    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg  signed [31:0] acc
);

    always @(posedge clk) begin
        a_out <= a_in;
        b_out <= b_in;
        if (clr)
            acc <= 32'sd0;
        else
            acc <= acc + a_in * b_in;
    end

endmodule
