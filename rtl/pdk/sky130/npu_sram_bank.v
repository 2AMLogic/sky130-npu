// npu_sram_bank -- the PDK seam (spec section 10).
//
// One logical SRAM bank, 1rw1r, synchronous read, byte write mask. This is the
// ONLY module in rtl/ that is PDK-specific; everything else is PDK-independent
// and is stamped into asap7-npu unchanged. A port replaces this directory.
//
// Two bodies, selected at compile time:
//   * default: the BEHAVIORAL SIMULATION MODEL (what rtl/check.sh and the
//     testbenches compile). It is not the sky130 macro.
//   * -DNPU_SRAM_MACRO: a wrapper over the pinned OpenRAM macro (reuse.lock.json,
//     rtl/pdk/sky130/README.md). The macro's own Verilog (or a blackbox) must be
//     on the file list.
// Both keep the port list and timing contract below.
//
// Timing contract (what the rest of rtl/ relies on):
//   * both ports are synchronous; read data is valid in the cycle AFTER the
//     address, and holds until the next enabled read on that port.
//   * RW port: rw_en with rw_we == 0 is a read; rw_we != 0 writes the masked
//     bytes (rw_we[i] enables byte i, byte 0 is bits [7:0]).
//   * R port: read only.
//   * a read and a write to the same word in the same cycle, on different
//     ports, is not used by the NPU and its result is undefined.
`ifdef NPU_SRAM_MACRO
// Wrapper over the OpenRAM sky130 1rw1r macro (active-low csb/web, wmask).
// The macro samples its inputs at posedge clk and drives dout from the falling
// edge, valid only until the next rising edge (+ hold), then X. The contract
// above says data is valid the cycle after the address and held, so each port
// keeps a hold register: fresh macro output is passed through in the cycle
// after an enabled read, the registered copy is used afterwards.
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

    generate
        if (WORD_BITS != 32)
            NPU_SRAM_MACRO_needs_32_bit_words u_bad_width ();
        else if (DEPTH_WORDS == 1024) begin : g_macro
            // not pre-generated upstream: generator config pinned, see reuse.lock.json
            sky130_sram_4kbyte_1rw1r_32x1024_8 u_macro (
                .clk0(clk), .csb0(~rw_en), .web0(rw_we == 0), .wmask0(rw_we),
                .addr0(rw_addr), .din0(rw_wdata), .dout0(dout0),
                .clk1(clk), .csb1(~r_en), .addr1(r_addr), .dout1(dout1));
        end else if (DEPTH_WORDS == 512) begin : g_macro
            // pre-generated upstream (fallback size)
            sky130_sram_2kbyte_1rw1r_32x512_8 u_macro (
                .clk0(clk), .csb0(~rw_en), .web0(rw_we == 0), .wmask0(rw_we),
                .addr0(rw_addr), .din0(rw_wdata), .dout0(dout0),
                .clk1(clk), .csb1(~r_en), .addr1(r_addr), .dout1(dout1));
        end else
            NPU_SRAM_MACRO_unsupported_depth u_bad_depth ();
    endgenerate
endmodule
`else
module npu_sram_bank #(
    parameter DEPTH_WORDS = 1024,
    parameter WORD_BITS   = 32
) (
    input  wire                         clk,

    // RW port
    input  wire                         rw_en,
    input  wire [WORD_BITS/8-1:0]       rw_we,
    input  wire [$clog2(DEPTH_WORDS)-1:0] rw_addr,
    input  wire [WORD_BITS-1:0]         rw_wdata,
    output reg  [WORD_BITS-1:0]         rw_rdata,

    // R port
    input  wire                         r_en,
    input  wire [$clog2(DEPTH_WORDS)-1:0] r_addr,
    output reg  [WORD_BITS-1:0]         r_rdata
);

    reg [WORD_BITS-1:0] mem [0:DEPTH_WORDS-1];

    integer i;

    always @(posedge clk) begin
        if (rw_en) begin
            if (rw_we == 0) begin
                rw_rdata <= mem[rw_addr];
            end else begin
                for (i = 0; i < WORD_BITS/8; i = i + 1)
                    if (rw_we[i])
                        mem[rw_addr][8*i +: 8] <= rw_wdata[8*i +: 8];
            end
        end
        if (r_en)
            r_rdata <= mem[r_addr];
    end

endmodule
`endif
