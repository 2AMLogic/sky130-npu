// Throwaway toolchain-smoke fixture: an 8-bit counter with synchronous reset.
// Not part of the NPU; chooses nothing the target spec owns.
module counter (
    input  wire       clk,
    input  wire       rst,
    output reg  [7:0] q
);
    always @(posedge clk) begin
        if (rst) q <= 8'd0;
        else     q <= q + 8'd1;
    end
endmodule
