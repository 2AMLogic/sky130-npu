// npu_top -- sky130-npu top level: INT8 output-stationary GEMM accelerator with
// banked SRAM, Wishbone B4 classic slave host interface (spec/npu.md).
//
// ARRAY_N is the only size parameter. Legal values per spec section 1 are
// {4, 8, 16}; this RTL implements 4 (fallback) and 8 (target). 16 (stretch) is
// legal in the spec but its two-banks-per-operand interleave is not designed
// (CLAUDE.md: stretch must not drive the architecture), so it is rejected at
// elaboration with a message that says so, as is any other value.
//
// Derived values (bank count and size) are in rtl/README.md. Clock/reset: `clk`,
// synchronous active-high `rst`.
module npu_top #(
    parameter ARRAY_N = 8
) (
    input  wire        clk,
    input  wire        rst,

    // Wishbone B4 classic slave
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [15:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,
    output wire        wb_err_o,

    output wire        irq
);

    // ------------------------------------------------------------------
    // Parameter legality (elaboration-time, loud in Icarus, Yosys, Verilator)
    // ------------------------------------------------------------------
    generate
        if (ARRAY_N != 4 && ARRAY_N != 8) begin : g_illegal_array_n
            // Instantiating a module that does not exist fails elaboration in
            // every tool; the module name is the message.
            ERROR_ARRAY_N_must_be_4_or_8__16_is_legal_in_the_spec_but_not_implemented__see_rtl_README
                u_fail ();
        end
    endgenerate

    // 4 x 4: 2 banks x 2 KB.  8 x 8: 4 banks x 4 KB.  (spec section 5.1)
    localparam NBANKS     = (ARRAY_N == 4) ? 2 : 4;
    localparam BANK_BYTES = (ARRAY_N == 4) ? 2048 : 4096;
    localparam K_MAX      = 256;
    localparam BW         = $clog2(NBANKS);
    localparam OW         = $clog2(BANK_BYTES) + 1;
    localparam AW         = $clog2(BANK_BYTES/4);
    localparam NWORDS     = ARRAY_N * ARRAY_N / 4;

    // ---- host <-> ctrl ----
    wire        start, soft_reset;
    wire [8:0]  cfg_k;
    wire [7:0]  cfg_a_bank, cfg_b_bank, cfg_out_bank;
    wire [31:0] cfg_a_off, cfg_b_off, cfg_out_off;
    wire [15:0] cfg_mult;
    wire [5:0]  cfg_shift;
    wire        cfg_relu;
    wire [32*ARRAY_N-1:0] bias_flat;

    wire        busy, status_clear, done_set, err_set;
    wire [3:0]  err_code;
    wire [31:0] perf_cycles;

    wire [8:0]  act_k;
    wire [BW-1:0] act_a_bank, act_b_bank, act_out_bank;
    wire [OW-1:0] act_a_off, act_b_off, act_out_off;
    wire [15:0] act_mult;
    wire [5:0]  act_shift;
    wire        act_relu;

    // ---- host <-> banks ----
    wire        h_req, h_grant;
    wire [BW-1:0] h_bank;
    wire [AW-1:0] h_word;
    wire [3:0]  h_we;
    wire [31:0] h_wdata, h_rdata;

    // ---- ctrl <-> datapath ----
    wire        op_rd_en, acc_clr, drain_vld, flush, rq_vld;
    wire [AW-1:0] a_word, b_word, wr_word;
    wire [$clog2(NWORDS)-1:0] drain_idx;
    wire [8*ARRAY_N-1:0] a_vec_raw, b_vec_raw;
    wire [31:0] rq_word;

    npu_host #(
        .ARRAY_N(ARRAY_N), .NBANKS(NBANKS), .BANK_BYTES(BANK_BYTES), .K_MAX(K_MAX)
    ) u_host (
        .clk(clk), .rst(rst),
        .wb_cyc_i(wb_cyc_i), .wb_stb_i(wb_stb_i), .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i), .wb_sel_i(wb_sel_i),
        .wb_dat_o(wb_dat_o), .wb_ack_o(wb_ack_o), .wb_err_o(wb_err_o), .irq(irq),
        .start(start), .soft_reset(soft_reset),
        .cfg_k(cfg_k), .cfg_a_bank(cfg_a_bank), .cfg_b_bank(cfg_b_bank),
        .cfg_out_bank(cfg_out_bank), .cfg_a_off(cfg_a_off), .cfg_b_off(cfg_b_off),
        .cfg_out_off(cfg_out_off), .cfg_mult(cfg_mult), .cfg_shift(cfg_shift),
        .cfg_relu(cfg_relu), .bias_flat(bias_flat),
        .busy(busy), .status_clear(status_clear), .done_set(done_set),
        .err_set(err_set), .err_code(err_code), .perf_cycles(perf_cycles),
        .act_k(act_k), .act_a_bank(act_a_bank), .act_b_bank(act_b_bank),
        .act_out_bank(act_out_bank), .act_a_off(act_a_off), .act_b_off(act_b_off),
        .act_out_off(act_out_off),
        .h_req(h_req), .h_bank(h_bank), .h_word(h_word), .h_we(h_we),
        .h_wdata(h_wdata), .h_grant(h_grant), .h_rdata(h_rdata)
    );

    npu_ctrl #(
        .ARRAY_N(ARRAY_N), .NBANKS(NBANKS), .BANK_BYTES(BANK_BYTES), .K_MAX(K_MAX)
    ) u_ctrl (
        .clk(clk), .rst(rst),
        .start(start), .soft_reset(soft_reset),
        .cfg_k(cfg_k), .cfg_a_bank(cfg_a_bank), .cfg_b_bank(cfg_b_bank),
        .cfg_out_bank(cfg_out_bank), .cfg_a_off(cfg_a_off), .cfg_b_off(cfg_b_off),
        .cfg_out_off(cfg_out_off), .cfg_mult(cfg_mult), .cfg_shift(cfg_shift),
        .cfg_relu(cfg_relu),
        .busy(busy), .status_clear(status_clear), .done_set(done_set),
        .err_set(err_set), .err_code(err_code), .perf_cycles(perf_cycles),
        .act_k(act_k), .act_a_bank(act_a_bank), .act_b_bank(act_b_bank),
        .act_out_bank(act_out_bank), .act_a_off(act_a_off), .act_b_off(act_b_off),
        .act_out_off(act_out_off), .act_mult(act_mult), .act_shift(act_shift),
        .act_relu(act_relu),
        .op_rd_en(op_rd_en), .a_word(a_word), .b_word(b_word),
        .acc_clr(acc_clr), .drain_idx(drain_idx), .drain_vld(drain_vld),
        .flush(flush), .rq_vld(rq_vld), .wr_word(wr_word)
    );

    npu_banks #(
        .ARRAY_N(ARRAY_N), .NBANKS(NBANKS), .BANK_BYTES(BANK_BYTES)
    ) u_banks (
        .clk(clk),
        .op_rd_en(op_rd_en), .a_bank(act_a_bank), .b_bank(act_b_bank),
        .a_word(a_word), .b_word(b_word),
        .a_vec(a_vec_raw), .b_vec(b_vec_raw),
        .wr_en(rq_vld), .wr_bank(act_out_bank), .wr_word(wr_word), .wr_data(rq_word),
        .h_req(h_req), .h_bank(h_bank), .h_word(h_word), .h_we(h_we),
        .h_wdata(h_wdata), .h_grant(h_grant), .h_rdata(h_rdata)
    );

    // Operand capture: bank data is valid the cycle after op_rd_en; register it
    // (macro access time stays off the MAC path) and force zeros when idle.
    reg                  rd_vld_q;
    reg [8*ARRAY_N-1:0]  a_vec, b_vec;
    always @(posedge clk) begin
        rd_vld_q <= op_rd_en;
        a_vec    <= rd_vld_q ? a_vec_raw : {8*ARRAY_N{1'b0}};
        b_vec    <= rd_vld_q ? b_vec_raw : {8*ARRAY_N{1'b0}};
    end

    wire [32*ARRAY_N*ARRAY_N-1:0] acc_flat;

    npu_array #(.ARRAY_N(ARRAY_N)) u_array (
        .clk(clk), .clr(acc_clr), .a_vec(a_vec), .b_vec(b_vec), .acc_flat(acc_flat)
    );

    // Drain: word d holds elements 4d .. 4d+3 of the row-major tile, so lane j
    // is element e = 4d + j with bias index e mod ARRAY_N.
    reg [127:0] acc4, bias4;
    integer j;
    always @* begin
        for (j = 0; j < 4; j = j + 1) begin
            acc4[32*j +: 32]  = acc_flat[32*(4*drain_idx + j) +: 32];
            bias4[32*j +: 32] = bias_flat[32*((4*drain_idx + j) % ARRAY_N) +: 32];
        end
    end

    npu_requant u_rq (
        .clk(clk), .flush(flush), .in_vld(drain_vld),
        .acc4(acc4), .bias4(bias4),
        .mult(act_mult), .shift(act_shift), .relu(act_relu),
        .out_vld(rq_vld), .out_word(rq_word)
    );

endmodule
