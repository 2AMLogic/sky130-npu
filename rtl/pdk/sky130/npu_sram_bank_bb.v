// npu_sram_bank_bb -- synthesis view of the PDK seam, macro as a black box.
//
// `klt synthesize` requests have no defines key, so the `ifdef NPU_SRAM_MACRO`
// wrapper in npu_sram_bank.v cannot be selected from a request. This file is
// that wrapper body (hold registers + macro instance) as a standalone module,
// with the OpenRAM macro declared `(* blackbox *)` so Yosys keeps it as an
// instance. List this file INSTEAD OF npu_sram_bank.v. The hold registers are
// real logic and are synthesized; the macro's area is not in the reported area.
// Keep the body in step with the ifdef branch of npu_sram_bank.v (1024-word case);
// rtl/check.sh compiles it alongside the wrapper.

(* blackbox *)
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
endmodule

module npu_sram_bank #(
    parameter DEPTH_WORDS = 1024,
    parameter WORD_BITS   = 32
) (
    input  wire                         clk,

    input  wire                         rw_en,
    input  wire [WORD_BITS/8-1:0]       rw_we,
    input  wire [$clog2(DEPTH_WORDS)-1:0] rw_addr,
    input  wire [WORD_BITS-1:0]         rw_wdata,
    output wire [WORD_BITS-1:0]         rw_rdata,

    input  wire                         r_en,
    input  wire [$clog2(DEPTH_WORDS)-1:0] r_addr,
    output wire [WORD_BITS-1:0]         r_rdata
);
    wire [WORD_BITS-1:0] dout0, dout1;
    reg                  rw_fresh = 1'b0, r_fresh = 1'b0;
    reg  [WORD_BITS-1:0] rw_hold, r_hold;

    always @(posedge clk) begin
        rw_fresh <= rw_en && (rw_we == 0);
        r_fresh  <= r_en;
        if (rw_fresh) rw_hold <= dout0;
        if (r_fresh)  r_hold  <= dout1;
    end

    assign rw_rdata = rw_fresh ? dout0 : rw_hold;
    assign r_rdata  = r_fresh  ? dout1 : r_hold;

    // 1024 x 32 only: the target bank size. The 512-word fallback branch of the
    // ifdef wrapper is not synthesized here.
    sky130_sram_4kbyte_1rw1r_32x1024_8 u_macro (
        .clk0(clk), .csb0(~rw_en), .web0(rw_we == 0), .wmask0(rw_we),
        .addr0(rw_addr), .din0(rw_wdata), .dout0(dout0),
        .clk1(clk), .csb1(~r_en), .addr1(r_addr), .dout1(dout1));
endmodule
