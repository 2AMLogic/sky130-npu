// npu_ctrl -- START validation, run-configuration latch, and the tile FSM.
//
//   IDLE -> FEED (K cycles, one k-vector read per cycle)
//        -> WAIT (2*ARRAY_N cycles, skew flush)
//        -> DRAIN (ARRAY_N*ARRAY_N/4 cycles, one result word per cycle)
//        -> TAIL (requantizer pipeline empties) -> IDLE, DONE.
//
// Stall-then-drain: no shadow accumulator, drain does not overlap the next
// tile (spec section 2, 9). Nothing is written to any bank unless START passed
// every check (spec section 6: "On ERR no bank is written").
module npu_ctrl #(
    parameter ARRAY_N     = 8,
    parameter NBANKS      = 4,
    parameter BANK_BYTES  = 4096,
    parameter K_MAX       = 256,
    parameter REQ_LAT     = 3          // npu_requant LATENCY
) (
    input  wire        clk,
    input  wire        rst,

    // from npu_host
    input  wire        start,          // CTRL.START written
    input  wire        soft_reset,     // CTRL.SOFT_RESET written
    input  wire [8:0]  cfg_k,
    input  wire [7:0]  cfg_a_bank,
    input  wire [7:0]  cfg_b_bank,
    input  wire [7:0]  cfg_out_bank,
    input  wire [31:0] cfg_a_off,
    input  wire [31:0] cfg_b_off,
    input  wire [31:0] cfg_out_off,
    input  wire [15:0] cfg_mult,
    input  wire [5:0]  cfg_shift,
    input  wire        cfg_relu,

    // to npu_host
    output wire        busy,
    output reg         status_clear,   // new operation: clear DONE / ERR
    output reg         done_set,
    output reg         err_set,
    output reg  [3:0]  err_code,
    output reg  [31:0] perf_cycles,

    // latched run configuration (stable while busy)
    output reg  [8:0]  act_k,
    output reg  [$clog2(NBANKS)-1:0] act_a_bank,
    output reg  [$clog2(NBANKS)-1:0] act_b_bank,
    output reg  [$clog2(NBANKS)-1:0] act_out_bank,
    output reg  [$clog2(BANK_BYTES):0] act_a_off,
    output reg  [$clog2(BANK_BYTES):0] act_b_off,
    output reg  [$clog2(BANK_BYTES):0] act_out_off,
    output reg  [15:0] act_mult,
    output reg  [5:0]  act_shift,
    output reg         act_relu,

    // operand reads (npu_banks)
    output wire        op_rd_en,
    output wire [$clog2(BANK_BYTES/4)-1:0] a_word,   // word address of k-vector word 0
    output wire [$clog2(BANK_BYTES/4)-1:0] b_word,

    // array / requantizer
    output wire        acc_clr,
    output wire [$clog2(ARRAY_N*ARRAY_N/4)-1:0] drain_idx,
    output wire        drain_vld,
    output wire        flush,


    // result write (npu_banks); data comes from npu_requant
    input  wire        rq_vld,
    output wire [$clog2(BANK_BYTES/4)-1:0] wr_word
);

    localparam WPV     = ARRAY_N / 4;                // 32-bit words per k-vector
    localparam NWORDS  = ARRAY_N * ARRAY_N / 4;      // result words per tile
    localparam AW      = $clog2(BANK_BYTES/4);
    localparam OW      = $clog2(BANK_BYTES) + 1;     // byte offset width (holds BANK_BYTES)

    localparam [2:0] S_IDLE = 3'd0, S_FEED = 3'd1, S_WAIT = 3'd2,
                     S_DRAIN = 3'd3, S_TAIL = 3'd4;

    reg [2:0]  state;
    reg [8:0]  cnt;                                   // FEED: k; WAIT/DRAIN/TAIL: step
    reg [$clog2(NWORDS):0] wr_cnt;

    assign busy = (state != S_IDLE);

    // ------------------------------------------------------------------
    // START validation on the raw (unlatched) configuration.
    // 34-bit arithmetic: offsets are 32-bit registers, so nothing wraps.
    // ------------------------------------------------------------------
    wire [33:0] a_end   = {2'b0, cfg_a_off}   + cfg_k * ARRAY_N;
    wire [33:0] b_end   = {2'b0, cfg_b_off}   + cfg_k * ARRAY_N;
    wire [33:0] out_end = {2'b0, cfg_out_off} + ARRAY_N * ARRAY_N;

    wire e_k = (cfg_k == 9'd0) || (cfg_k > K_MAX);

    wire e_bank = (cfg_a_bank >= NBANKS) || (cfg_b_bank >= NBANKS) ||
                  (cfg_out_bank >= NBANKS) || (cfg_a_bank == cfg_b_bank);
    wire e_align = ((cfg_a_off % ARRAY_N) != 0) || ((cfg_b_off % ARRAY_N) != 0) ||
                   ((cfg_out_off % 4) != 0);
    wire e_range = (a_end > BANK_BYTES) || (b_end > BANK_BYTES) || (out_end > BANK_BYTES);
    wire e_off   = e_bank || e_align || e_range;

    // Result range [out_off, out_end) against an operand range in a shared bank.
    wire ov_a = (cfg_out_bank == cfg_a_bank) &&
                ({2'b0, cfg_out_off} < a_end) && ({2'b0, cfg_a_off} < out_end);
    wire ov_b = (cfg_out_bank == cfg_b_bank) &&
                ({2'b0, cfg_out_off} < b_end) && ({2'b0, cfg_b_off} < out_end);
    wire e_ovl = ov_a || ov_b;

    wire e_shift = (cfg_shift > 6'd47);

    // Lowest code wins when several apply (spec lists no priority).
    wire [3:0] code_now = e_k     ? 4'd1 :
                          e_off   ? 4'd2 :
                          e_ovl   ? 4'd3 :
                          e_shift ? 4'd4 : 4'd0;

    // ------------------------------------------------------------------
    // Event pulses to the host registers
    // ------------------------------------------------------------------
    wire go = start && !soft_reset && (state == S_IDLE) && (code_now == 4'd0);

    always @* begin
        status_clear = 1'b0;
        err_set      = 1'b0;
        err_code     = 4'd0;
        if (start && !soft_reset) begin
            if (state != S_IDLE) begin
                err_set  = 1'b1;
                err_code = 4'd5;                     // START while BUSY
            end else begin
                status_clear = 1'b1;
                if (code_now != 4'd0) begin
                    err_set  = 1'b1;
                    err_code = code_now;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        done_set <= 1'b0;
        if (rst || soft_reset) begin
            state       <= S_IDLE;
            cnt         <= 9'd0;
            wr_cnt      <= 0;
            perf_cycles <= 32'd0;
            if (rst) begin
                act_k        <= 9'd0;
                act_a_bank   <= 0;
                act_b_bank   <= 0;
                act_out_bank <= 0;
                act_a_off    <= 0;
                act_b_off    <= 0;
                act_out_off  <= 0;
                act_mult     <= 16'd0;
                act_shift    <= 6'd0;
                act_relu     <= 1'b0;
            end
        end else begin
            if (state != S_IDLE && perf_cycles != 32'hFFFF_FFFF)
                perf_cycles <= perf_cycles + 32'd1;

            case (state)
            S_IDLE: begin
                if (go) begin
                    act_k        <= cfg_k;
                    act_a_bank   <= cfg_a_bank[$clog2(NBANKS)-1:0];
                    act_b_bank   <= cfg_b_bank[$clog2(NBANKS)-1:0];
                    act_out_bank <= cfg_out_bank[$clog2(NBANKS)-1:0];
                    act_a_off    <= cfg_a_off[OW-1:0];
                    act_b_off    <= cfg_b_off[OW-1:0];
                    act_out_off  <= cfg_out_off[OW-1:0];
                    act_mult     <= cfg_mult;
                    act_shift    <= cfg_shift;
                    act_relu     <= cfg_relu;
                    state        <= S_FEED;
                    cnt          <= 9'd0;
                    wr_cnt       <= 0;
                    perf_cycles  <= 32'd0;
                end
            end
            S_FEED: begin
                cnt <= cnt + 9'd1;
                if (cnt == act_k - 9'd1) begin
                    state <= S_WAIT;
                    cnt   <= 9'd0;
                end
            end
            S_WAIT: begin
                cnt <= cnt + 9'd1;
                if (cnt == 2*ARRAY_N - 1) begin
                    state <= S_DRAIN;
                    cnt   <= 9'd0;
                end
            end
            S_DRAIN: begin
                cnt <= cnt + 9'd1;
                if (cnt == NWORDS - 1) begin
                    state <= S_TAIL;
                    cnt   <= 9'd0;
                end
            end
            S_TAIL: begin
                cnt <= cnt + 9'd1;
                if (cnt == REQ_LAT - 1) begin
                    state    <= S_IDLE;
                    done_set <= 1'b1;
                end
            end
            default: state <= S_IDLE;
            endcase

            if (rq_vld)
                wr_cnt <= wr_cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Combinational control outputs
    // ------------------------------------------------------------------
    assign op_rd_en  = (state == S_FEED);
    assign acc_clr   = (state == S_FEED) && (cnt == 9'd0);
    assign a_word    = (act_a_off >> 2) + cnt * WPV;
    assign b_word    = (act_b_off >> 2) + cnt * WPV;

    assign drain_vld = (state == S_DRAIN);
    assign drain_idx = cnt[$clog2(NWORDS)-1:0];
    assign flush     = soft_reset || rst;

    assign wr_word   = (act_out_off >> 2) + wr_cnt;

endmodule
