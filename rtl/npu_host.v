// npu_host -- Wishbone B4 classic slave (32-bit, byte-addressed, SEL honored)
// and the register file of spec section 6.
//
// Every response (ACK or ERR) is registered, so it arrives one cycle after the
// request is accepted; a bank-window access additionally waits until the bank
// port is granted. ACK/ERR is never asserted in the cycle a request starts, so
// a master that holds STB until it sees ACK/ERR works unmodified.
//
// Address map (block-relative, 16-bit byte address):
//   0x0000-0x00FF  registers (reserved offsets read 0, writes ignored)
//   0x0100-0x013C  BIAS[0..15]; entries >= ARRAY_N read 0, writes ignored
//   0x0140-0x0FFF  reserved: read 0, writes ignored
//   0x1000 + 0x1000*b  bank b window; offsets >= bank size, banks >= NBANKS: ERR
module npu_host #(
    parameter ARRAY_N    = 8,
    parameter NBANKS     = 4,
    parameter BANK_BYTES = 4096,
    parameter K_MAX      = 256
) (
    input  wire        clk,
    input  wire        rst,

    // Wishbone
    input  wire        wb_cyc_i,
    input  wire        wb_stb_i,
    input  wire        wb_we_i,
    input  wire [15:0] wb_adr_i,
    input  wire [31:0] wb_dat_i,
    input  wire [3:0]  wb_sel_i,
    output wire [31:0] wb_dat_o,
    output wire        wb_ack_o,
    output wire        wb_err_o,
    output wire        irq,

    // to npu_ctrl
    output reg         start,
    output reg         soft_reset,
    output wire [8:0]  cfg_k,
    output wire [7:0]  cfg_a_bank,
    output wire [7:0]  cfg_b_bank,
    output wire [7:0]  cfg_out_bank,
    output wire [31:0] cfg_a_off,
    output wire [31:0] cfg_b_off,
    output wire [31:0] cfg_out_off,
    output wire [15:0] cfg_mult,
    output wire [5:0]  cfg_shift,
    output wire        cfg_relu,
    output wire [32*ARRAY_N-1:0] bias_flat,

    // from npu_ctrl
    input  wire        busy,
    input  wire        status_clear,
    input  wire        done_set,
    input  wire        err_set,
    input  wire [3:0]  err_code,
    input  wire [31:0] perf_cycles,
    input  wire [8:0]  act_k,
    input  wire [$clog2(NBANKS)-1:0] act_a_bank,
    input  wire [$clog2(NBANKS)-1:0] act_b_bank,
    input  wire [$clog2(NBANKS)-1:0] act_out_bank,
    input  wire [$clog2(BANK_BYTES):0] act_a_off,
    input  wire [$clog2(BANK_BYTES):0] act_b_off,
    input  wire [$clog2(BANK_BYTES):0] act_out_off,

    // bank window (npu_banks)
    output wire        h_req,
    output wire [$clog2(NBANKS)-1:0] h_bank,
    output wire [$clog2(BANK_BYTES/4)-1:0] h_word,
    output wire [3:0]  h_we,
    output wire [31:0] h_wdata,
    input  wire        h_grant,
    input  wire [31:0] h_rdata
);

    localparam OW = $clog2(BANK_BYTES) + 1;
    localparam BW = $clog2(NBANKS);
    localparam [7:0] CAP_N     = ARRAY_N;
    localparam [7:0] CAP_BANKS = NBANKS;
    localparam [7:0] CAP_LOG2_BANK_BYTES = $clog2(BANK_BYTES);
    localparam [7:0] CAP_LOG2_K_MAX      = $clog2(K_MAX);

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg        irq_en;
    reg        st_done, st_err;
    reg [3:0]  st_code;
    reg [8:0]  r_k;
    reg [7:0]  r_a_bank, r_b_bank, r_out_bank;
    reg [31:0] r_a_off, r_b_off, r_out_off;
    reg [15:0] r_mult;
    reg [5:0]  r_shift;
    reg        r_relu;
    reg [31:0] bias [0:ARRAY_N-1];

    assign cfg_k        = r_k;
    assign cfg_a_bank   = r_a_bank;
    assign cfg_b_bank   = r_b_bank;
    assign cfg_out_bank = r_out_bank;
    assign cfg_a_off    = r_a_off;
    assign cfg_b_off    = r_b_off;
    assign cfg_out_off  = r_out_off;
    assign cfg_mult     = r_mult;
    assign cfg_shift    = r_shift;
    assign cfg_relu     = r_relu;

    genvar gi;
    generate
        for (gi = 0; gi < ARRAY_N; gi = gi + 1) begin : g_bias
            assign bias_flat[32*gi +: 32] = bias[gi];
        end
    endgenerate

    assign irq = irq_en && (st_done || st_err);

    function [31:0] merge;
        input [31:0] old;
        input [31:0] new_;
        input [3:0]  sel;
        begin
            merge = {sel[3] ? new_[31:24] : old[31:24],
                     sel[2] ? new_[23:16] : old[23:16],
                     sel[1] ? new_[15:8]  : old[15:8],
                     sel[0] ? new_[7:0]   : old[7:0]};
        end
    endfunction

    // ------------------------------------------------------------------
    // Request decode
    // ------------------------------------------------------------------
    reg        rsp_ack, rsp_err, rsp_bank;
    reg [31:0] rsp_dat;

    wire req      = wb_cyc_i && wb_stb_i && !rsp_ack && !rsp_err;
    wire in_regs  = (wb_adr_i[15:12] == 4'd0);
    wire in_bank  = (wb_adr_i[15:12] >= 4'd1) && (wb_adr_i[15:12] <= NBANKS) &&
                    (wb_adr_i[11:0] < BANK_BYTES);
    wire [BW-1:0] w_bank = wb_adr_i[15:12] - 4'd1;
    wire [11:0]   w_off  = wb_adr_i[11:0];

    wire is_bias = in_regs && (wb_adr_i[11:6] == 6'd4);       // 0x100-0x13F of the register block
    wire [3:0] bias_idx = wb_adr_i[5:2];
    wire [5:0] reg_idx  = wb_adr_i[7:2];                    // valid if adr[11:8] == 0
    wire is_reg  = in_regs && (wb_adr_i[11:8] == 4'd0);

    // Legality of a host access to a bank window while BUSY (spec section 5.3).
    wire [13:0] off14 = {2'b0, w_off};
    wire [13:0] a_lo   = {1'b0, act_a_off};
    wire [13:0] a_hi   = a_lo + act_k * ARRAY_N;
    wire [13:0] b_lo   = {1'b0, act_b_off};
    wire [13:0] b_hi   = b_lo + act_k * ARRAY_N;
    wire [13:0] o_lo   = {1'b0, act_out_off};
    wire [13:0] o_hi   = o_lo + ARRAY_N * ARRAY_N;

    wire hit_a = (w_bank == act_a_bank)   && (off14 >= a_lo) && (off14 < a_hi);
    wire hit_b = (w_bank == act_b_bank)   && (off14 >= b_lo) && (off14 < b_hi);
    wire hit_o = (w_bank == act_out_bank) && (off14 >= o_lo) && (off14 < o_hi);

    wire act_bank_hit = (w_bank == act_a_bank) || (w_bank == act_b_bank);
    wire bank_denied  = busy && ((ARRAY_N == 4) ? (hit_a || hit_b || hit_o) : act_bank_hit);

    // Bank window request towards npu_banks: held until granted.
    assign h_req   = req && in_bank && !bank_denied;
    assign h_bank  = w_bank;
    assign h_word  = w_off[$clog2(BANK_BYTES)-1:2];
    assign h_we    = wb_we_i ? wb_sel_i : 4'h0;
    assign h_wdata = wb_dat_i;

    // ------------------------------------------------------------------
    // Register read mux
    // ------------------------------------------------------------------
    reg [31:0] rd;
    always @* begin
        rd = 32'd0;
        if (is_bias) begin
            if (bias_idx < ARRAY_N)
                rd = bias[bias_idx[$clog2(ARRAY_N)-1:0]];
        end else if (is_reg) begin
            case (reg_idx)
            6'h00: rd = 32'h4E505530;
            6'h01: rd = 32'd1;
            6'h02: rd = {CAP_LOG2_K_MAX, CAP_LOG2_BANK_BYTES, CAP_BANKS, CAP_N};
            6'h03: rd = {29'd0, irq_en, 2'b00};
            6'h04: rd = {20'd0, st_code, 5'd0, st_err, st_done, busy};
            6'h05: rd = {23'd0, r_k};
            6'h06: rd = {8'd0, r_out_bank, r_b_bank, r_a_bank};
            6'h07: rd = r_a_off;
            6'h08: rd = r_b_off;
            6'h09: rd = r_out_off;
            6'h0A: rd = {16'd0, r_mult};
            6'h0B: rd = {23'd0, r_relu, 2'b00, r_shift};
            6'h0C: rd = perf_cycles;
            default: rd = 32'd0;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Sequential: register writes, status, response
    // ------------------------------------------------------------------
    wire reg_wr = req && wb_we_i && (is_reg || is_bias);
    integer i;

    always @(posedge clk) begin
        start      <= 1'b0;
        soft_reset <= 1'b0;

        if (rst) begin
            irq_en     <= 1'b0;
            st_done    <= 1'b0;
            st_err     <= 1'b0;
            st_code    <= 4'd0;
            r_k        <= 9'd0;
            r_a_bank   <= 8'd0;
            r_b_bank   <= 8'd0;
            r_out_bank <= 8'd0;
            r_a_off    <= 32'd0;
            r_b_off    <= 32'd0;
            r_out_off  <= 32'd0;
            r_mult     <= 16'd0;
            r_shift    <= 6'd0;
            r_relu     <= 1'b0;
            for (i = 0; i < ARRAY_N; i = i + 1)
                bias[i] <= 32'd0;
            rsp_ack    <= 1'b0;
            rsp_err    <= 1'b0;
            rsp_bank   <= 1'b0;
            rsp_dat    <= 32'd0;
        end else begin
            // ---- status events from the controller (set wins over clear) ----
            if (status_clear || soft_reset) begin
                st_done <= 1'b0;
                st_err  <= 1'b0;
                st_code <= 4'd0;
            end
            if (done_set)
                st_done <= 1'b1;
            if (err_set) begin
                st_err  <= 1'b1;
                st_code <= err_code;
            end

            // ---- response ----
            rsp_ack  <= 1'b0;
            rsp_err  <= 1'b0;
            rsp_bank <= 1'b0;

            if (req) begin
                if (in_regs) begin
                    // register space (including reserved): 1-cycle ACK
                    rsp_ack <= 1'b1;
                    rsp_dat <= rd;
                end else if (!in_bank || bank_denied) begin
                    rsp_err <= 1'b1;
                end else if (h_grant) begin
                    rsp_ack  <= 1'b1;
                    rsp_bank <= 1'b1;
                end
            end

            // ---- register writes ----
            if (reg_wr) begin
                if (is_bias) begin
                    // BIAS is read while draining: writes during BUSY are dropped.
                    if (bias_idx < ARRAY_N && !busy)
                        bias[bias_idx[$clog2(ARRAY_N)-1:0]] <=
                            merge(bias[bias_idx[$clog2(ARRAY_N)-1:0]], wb_dat_i, wb_sel_i);
                end else begin
                    case (reg_idx)
                    6'h03: begin   // CTRL
                        if (wb_sel_i[0]) begin
                            start      <= wb_dat_i[0];
                            soft_reset <= wb_dat_i[1];
                            irq_en     <= wb_dat_i[2];
                        end
                    end
                    6'h04: begin   // STATUS, RW1C
                        if (wb_sel_i[0]) begin
                            if (wb_dat_i[1]) st_done <= 1'b0;
                            if (wb_dat_i[2]) begin
                                st_err  <= 1'b0;
                                st_code <= 4'd0;
                            end
                        end
                    end
                    6'h05: r_k        <= merge({23'd0, r_k}, wb_dat_i, wb_sel_i);
                    6'h06: begin
                        if (wb_sel_i[0]) r_a_bank   <= wb_dat_i[7:0];
                        if (wb_sel_i[1]) r_b_bank   <= wb_dat_i[15:8];
                        if (wb_sel_i[2]) r_out_bank <= wb_dat_i[23:16];
                    end
                    6'h07: r_a_off    <= merge(r_a_off,   wb_dat_i, wb_sel_i);
                    6'h08: r_b_off    <= merge(r_b_off,   wb_dat_i, wb_sel_i);
                    6'h09: r_out_off  <= merge(r_out_off, wb_dat_i, wb_sel_i);
                    6'h0A: r_mult     <= merge({16'd0, r_mult}, wb_dat_i, wb_sel_i);
                    6'h0B: begin
                        if (wb_sel_i[0]) r_shift <= wb_dat_i[5:0];
                        if (wb_sel_i[1]) r_relu  <= wb_dat_i[8];
                    end
                    default: ;
                    endcase
                end
            end
        end
    end

    assign wb_ack_o = rsp_ack;
    assign wb_err_o = rsp_err;
    assign wb_dat_o = rsp_bank ? h_rdata : rsp_dat;

endmodule
