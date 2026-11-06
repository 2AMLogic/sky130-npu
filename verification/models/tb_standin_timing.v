// Direct timing check of the stand-in against the documented macro behaviour:
// dout is X after the rising edge, valid from the falling edge of the read
// cycle, and X again right after the next rising edge. Prints PASS/FAIL.
`timescale 1ns/1ps
module tb;
    reg clk0 = 0, clk1 = 0;
    always #10 begin clk0 = ~clk0; clk1 = ~clk1; end
    reg csb0 = 1, web0 = 1, csb1 = 1;
    reg [3:0] wm = 0;
    reg [9:0] a0 = 0, a1 = 0;
    reg [31:0] d0 = 0;
    wire [31:0] q0, q1;
    integer bad = 0;
    sky130_sram_4kbyte_1rw1r_32x1024_8 m(.clk0(clk0), .csb0(csb0), .web0(web0),
        .wmask0(wm), .addr0(a0), .din0(d0), .dout0(q0),
        .clk1(clk1), .csb1(csb1), .addr1(a1), .dout1(q1));
    task chk(input ok, input [255:0] what);
        if (!ok) begin bad = bad + 1; $display("FAIL %0s @%0t", what, $time); end
    endtask
    initial begin
        @(negedge clk0); csb0 = 0; web0 = 0; wm = 4'hF; a0 = 7; d0 = 32'h12345678;
        @(negedge clk0); wm = 4'b0010; d0 = 32'hAABBCCDD;           // masked write
        @(negedge clk0); web0 = 1; csb1 = 0; a1 = 7;                // read, both ports
        @(posedge clk0); #2;
        chk(q0 === 32'bx && q1 === 32'bx, "X after rising edge");
        @(negedge clk0); #2;
        chk(q0 === 32'h1234CC78 && q1 === 32'h1234CC78, "valid after falling edge");
        csb0 = 1; csb1 = 1;
        @(posedge clk0); #2;
        chk(q0 === 32'bx && q1 === 32'bx, "not held past next rising edge");
        if (bad == 0) $display("PASS standin timing"); else $display("FAIL standin timing");
        $finish;
    end
endmodule
