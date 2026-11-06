// STAND-IN -- NOT the macro's view.
//
// Behavioural stand-in for sky130_sram_4kbyte_1rw1r_32x1024_8 (OpenRAM, 1rw1r,
// 32-bit words, 4-bit byte write mask). The 4 KB macro has no generated Verilog
// yet (#51), so this file models only what rtl/pdk/sky130/README.md records
// under "Read latency finding":
//   - inputs are sampled at the rising edge of clk0 / clk1;
//   - dout is driven after the FALLING edge of the same cycle;
//   - dout is cleared to X shortly after the NEXT rising edge, i.e. it is not
//     held past it (that is why npu_sram_bank adds hold registers).
// The only delay is a nominal 1 ns after each edge (`timescale 1ns/1ps), so
// that a testbench sampling at the falling edge sees the same ordering it would
// see on the macro; it is NOT a figure from the macro. No setup/hold, no power
// pins. A result using this file says nothing about the macro's
// timing. Replace it with the generated Verilog view when #51 lands.
//
// Do not compile this together with rtl/pdk/sky130/npu_sram_bank_bb.v: that
// file declares the same module as a (* blackbox *).

`timescale 1ns/1ps
module sky130_sram_4kbyte_1rw1r_32x1024_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [9:0]  addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [9:0]  addr1,
    output wire [31:0] dout1
);
    reg [31:0] mem [0:1023];

    reg        csb0_r, web0_r, csb1_r;
    reg [3:0]  wmask0_r;
    reg [9:0]  addr0_r, addr1_r;
    reg [31:0] din0_r;
    reg [31:0] dout0_q = 32'bx, dout1_q = 32'bx;

    assign dout0 = dout0_q;
    assign dout1 = dout1_q;

    // Rising edge: sample inputs, perform the write, clear dout to X.
    always @(posedge clk0) begin
        csb0_r <= csb0; web0_r <= web0; wmask0_r <= wmask0;
        addr0_r <= addr0; din0_r <= din0;
        dout0_q <= #1 32'bx;
        if (!csb0 && !web0) begin
            if (wmask0[0]) mem[addr0][7:0]   <= din0[7:0];
            if (wmask0[1]) mem[addr0][15:8]  <= din0[15:8];
            if (wmask0[2]) mem[addr0][23:16] <= din0[23:16];
            if (wmask0[3]) mem[addr0][31:24] <= din0[31:24];
        end
    end

    always @(posedge clk1) begin
        csb1_r <= csb1; addr1_r <= addr1;
        dout1_q <= #1 32'bx;
    end

    // Falling edge: drive the sampled read.
    always @(negedge clk0)
        if (!csb0_r && web0_r) dout0_q <= #1 mem[addr0_r];

    always @(negedge clk1)
        if (!csb1_r) dout1_q <= #1 mem[addr1_r];
endmodule
