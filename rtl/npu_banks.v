// npu_banks -- the SRAM banks, the bank mux and the port arbitration.
//
// One npu_sram_bank per bank (the PDK seam). Roles are not fixed in hardware:
// A_BANK / B_BANK / OUT_BANK select banks per tile, so ping-pong (spec section
// 2) is the host alternating A_BANK between 0 and 1 and B_BANK between 2 and 3.
//
// Port use per bank:
//   * R port : operand word 0 of the k-vector (the only operand port at N = 4).
//   * RW port: operand word 1 at N = 8 (both ports busy, so no host access to
//              an active bank), the result write, and host window accesses.
//   * Priority on the RW port: result write, operand read, host. A host access
//     that loses is simply not granted this cycle and waits (spec section 5.3).
module npu_banks #(
    parameter ARRAY_N    = 8,
    parameter NBANKS     = 4,
    parameter BANK_BYTES = 4096
) (
    input  wire        clk,

    // operand read (npu_ctrl); data is valid the cycle after op_rd_en
    input  wire        op_rd_en,
    input  wire [$clog2(NBANKS)-1:0] a_bank,
    input  wire [$clog2(NBANKS)-1:0] b_bank,
    input  wire [$clog2(BANK_BYTES/4)-1:0] a_word,
    input  wire [$clog2(BANK_BYTES/4)-1:0] b_word,
    output wire [8*ARRAY_N-1:0] a_vec,
    output wire [8*ARRAY_N-1:0] b_vec,

    // result write
    input  wire        wr_en,
    input  wire [$clog2(NBANKS)-1:0] wr_bank,
    input  wire [$clog2(BANK_BYTES/4)-1:0] wr_word,
    input  wire [31:0] wr_data,

    // host window access (already checked for legality by npu_host)
    input  wire        h_req,
    input  wire [$clog2(NBANKS)-1:0] h_bank,
    input  wire [$clog2(BANK_BYTES/4)-1:0] h_word,
    input  wire [3:0]  h_we,           // byte mask; 0 = read
    input  wire [31:0] h_wdata,
    output wire        h_grant,
    output wire [31:0] h_rdata         // valid the cycle after h_grant
);

    localparam AW  = $clog2(BANK_BYTES/4);
    localparam BW  = $clog2(NBANKS);
    localparam WPV = ARRAY_N / 4;      // 1 (N = 4) or 2 (N = 8)

    wire [31:0] rw_rdata [0:NBANKS-1];
    wire [31:0] r_rdata  [0:NBANKS-1];

    wire        h_blocked;
    assign h_grant = h_req && !h_blocked;

    reg [BW-1:0] h_bank_q;
    always @(posedge clk)
        if (h_grant)
            h_bank_q <= h_bank;

    assign h_rdata = rw_rdata[h_bank_q];

    genvar b;
    generate
        for (b = 0; b < NBANKS; b = b + 1) begin : g_bank
            wire a_hit   = op_rd_en && (a_bank == b);
            wire b_hit   = op_rd_en && (b_bank == b);
            wire res_hit = wr_en    && (wr_bank == b);

            // RW port: result write > operand word 1 (N = 8 only) > host.
            wire op_rw   = (WPV == 2) && (a_hit || b_hit);
            wire host_hit = h_req && (h_bank == b);

            wire        rw_en    = res_hit || op_rw || host_hit;
            wire [3:0]  rw_we    = res_hit ? 4'hF : op_rw ? 4'h0 : h_we;
            wire [AW-1:0] rw_addr = res_hit ? wr_word :
                                    op_rw   ? ((a_hit ? a_word : b_word) + 1'b1) :
                                              h_word;
            wire [31:0] rw_wdata = res_hit ? wr_data : h_wdata;

            wire        r_en     = a_hit || b_hit;
            wire [AW-1:0] r_addr = a_hit ? a_word : b_word;

            npu_sram_bank #(
                .DEPTH_WORDS(BANK_BYTES/4),
                .WORD_BITS  (32)
            ) u_bank (
                .clk     (clk),
                .rw_en   (rw_en),
                .rw_we   (rw_we),
                .rw_addr (rw_addr),
                .rw_wdata(rw_wdata),
                .rw_rdata(rw_rdata[b]),
                .r_en    (r_en),
                .r_addr  (r_addr),
                .r_rdata (r_rdata[b])
            );
        end
    endgenerate

    // The host loses on its bank if the result write or an operand RW-port
    // read uses that bank's RW port this cycle.
    assign h_blocked = (wr_en && (wr_bank == h_bank)) ||
                       ((WPV == 2) && op_rd_en && ((a_bank == h_bank) || (b_bank == h_bank)));

    // Operand k-vectors: word 0 from the R port, word 1 (N = 8) from RW.
    wire [31:0] a_w0 = r_rdata[a_bank];
    wire [31:0] b_w0 = r_rdata[b_bank];
    wire [31:0] a_w1 = rw_rdata[a_bank];
    wire [31:0] b_w1 = rw_rdata[b_bank];

    generate
        if (WPV == 2) begin : g_wide
            assign a_vec = {a_w1, a_w0};
            assign b_vec = {b_w1, b_w0};
        end else begin : g_narrow
            assign a_vec = a_w0;
            assign b_vec = b_w0;
        end
    endgenerate

endmodule
