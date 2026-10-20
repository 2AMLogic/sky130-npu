// npu_sram_bank -- the PDK seam (spec section 10).
//
// One logical SRAM bank, 1rw1r, synchronous read, byte write mask. This is the
// ONLY module in rtl/ that is PDK-specific; everything else is PDK-independent
// and is stamped into asap7-npu unchanged. A port replaces this directory.
//
// This file is the BEHAVIORAL SIMULATION MODEL. It is not the sky130 macro:
// no OpenRAM macro is imported or pinned here (reuse.lock.json does not exist,
// see spec/decisions/0002-sram-source.md). A wrapper over a real macro must
// keep the port list and timing contract below.
//
// Timing contract (what the rest of rtl/ relies on):
//   * both ports are synchronous; read data is valid in the cycle AFTER the
//     address, and holds until the next enabled read on that port.
//   * RW port: rw_en with rw_we == 0 is a read; rw_we != 0 writes the masked
//     bytes (rw_we[i] enables byte i, byte 0 is bits [7:0]).
//   * R port: read only.
//   * a read and a write to the same word in the same cycle, on different
//     ports, is not used by the NPU and its result is undefined.
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
