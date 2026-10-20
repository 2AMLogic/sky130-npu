// npu_array -- ARRAY_N x ARRAY_N output-stationary PE grid with edge skew.
//
// a_vec / b_vec carry one k-vector each (spec section 5.2): byte i of a_vec is
// A[i][k], byte j of b_vec is B[k][j]. They must be zero when no operand is
// being fed. Row m of A is delayed m cycles, column n of B n cycles, and each
// PE adds one more cycle east / south, so PE (m, n) sees step k at cycle
// k + m + n.
//
// acc_flat holds acc[m][n] at bits [(m*N+n)*32 +: 32] (row-major).
module npu_array #(
    parameter ARRAY_N = 8
) (
    input  wire                       clk,
    input  wire                       clr,
    input  wire [8*ARRAY_N-1:0]       a_vec,
    input  wire [8*ARRAY_N-1:0]       b_vec,
    output wire [32*ARRAY_N*ARRAY_N-1:0] acc_flat
);

    // a_edge[m] / b_edge[n]: skewed operand entering row m / column n.
    wire [7:0] a_edge [0:ARRAY_N-1];
    wire [7:0] b_edge [0:ARRAY_N-1];

    genvar m, n, d;
    generate
        for (m = 0; m < ARRAY_N; m = m + 1) begin : g_skew_a
            if (m == 0) begin : g_direct
                assign a_edge[m] = a_vec[8*m +: 8];
            end else begin : g_delay
                reg [7:0] dly [0:m-1];
                for (d = 0; d < m; d = d + 1) begin : g_stage
                    if (d == 0) begin : g_first
                        always @(posedge clk)
                            dly[d] <= a_vec[8*m +: 8];
                    end else begin : g_next
                        always @(posedge clk)
                            dly[d] <= dly[d-1];
                    end
                end
                assign a_edge[m] = dly[m-1];
            end
        end
        for (n = 0; n < ARRAY_N; n = n + 1) begin : g_skew_b
            if (n == 0) begin : g_direct
                assign b_edge[n] = b_vec[8*n +: 8];
            end else begin : g_delay
                reg [7:0] dly [0:n-1];
                for (d = 0; d < n; d = d + 1) begin : g_stage
                    if (d == 0) begin : g_first
                        always @(posedge clk)
                            dly[d] <= b_vec[8*n +: 8];
                    end else begin : g_next
                        always @(posedge clk)
                            dly[d] <= dly[d-1];
                    end
                end
                assign b_edge[n] = dly[n-1];
            end
        end
    endgenerate

    // a_w[m][n]: A entering PE (m, n) from the west; b_w likewise from the north.
    wire [7:0] a_w [0:ARRAY_N-1][0:ARRAY_N];
    wire [7:0] b_w [0:ARRAY_N][0:ARRAY_N-1];

    generate
        for (m = 0; m < ARRAY_N; m = m + 1) begin : g_row
            assign a_w[m][0] = a_edge[m];
            for (n = 0; n < ARRAY_N; n = n + 1) begin : g_col
                if (m == 0) begin : g_top
                    assign b_w[0][n] = b_edge[n];
                end
                npu_pe u_pe (
                    .clk  (clk),
                    .clr  (clr),
                    .a_in (a_w[m][n]),
                    .b_in (b_w[m][n]),
                    .a_out(a_w[m][n+1]),
                    .b_out(b_w[m+1][n]),
                    .acc  (acc_flat[32*(m*ARRAY_N+n) +: 32])
                );
            end
        end
    endgenerate

endmodule
