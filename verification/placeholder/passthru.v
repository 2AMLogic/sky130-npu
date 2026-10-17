// THROWAWAY placeholder DUT for the harness skeleton (issue #7).
// A registered pass-through with synchronous active-high reset. It decides
// nothing about the real design (arithmetic, dataflow, array size are #3's)
// and is replaced when the real RTL lands.
`timescale 1ns/1ps
module passthru #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    always @(posedge clk) begin
        if (rst) q <= {WIDTH{1'b0}};
        else     q <= d;
    end
endmodule
