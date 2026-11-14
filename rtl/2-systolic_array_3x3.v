// ============================================================================
// File: systolic_array_3x3.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Description: 3x3 output-stationary systolic array. Instantiates N*N pe.v
//              cells in an orthogonal mesh. Matrix A streams west-to-east
//              along each row, matrix B streams north-to-south along each
//              column. Each PE forwards its operands one hop per clock, so
//              operand pairs meet at PE(i,j) when the boundary feed is skewed
//              by one cycle per row (A) and per column (B).
//
// Interface:
//   a_rows  : N packed signed operands, row i at [i*DATA_WIDTH +: DATA_WIDTH]
//             (injected at the west edge of row i)
//   b_cols  : N packed signed operands, column j at [j*DATA_WIDTH +: DATA_WIDTH]
//             (injected at the north edge of column j)
//   c_flat  : N*N packed accumulators, row-major, C[i][j] at
//             [(i*N+j)*ACC_WIDTH +: ACC_WIDTH]
//   valid_in: enables MAC in the whole array's west column; it is forwarded
//             east through the pe.v valid chain. Feed zeros during the skew
//             gaps (before/after each operand stream) - zero operands add 0.
//   clr_acc : synchronous accumulator clear, broadcast to all PEs. Assert on
//             the first feed cycle of a new product (the first product is
//             then loaded instead of accumulated).
// Timing: inputs injected without extra boundary registers, so the final
//         C[2][2] term is accumulated 3N-2 = 7 clocks after the first feed edge.
// ============================================================================

`timescale 1ns / 1ps
`include "tensora_pkg.vh"

module systolic_array_3x3 #(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32,
    parameter N          = 3
)(
    input  wire                              clk,
    input  wire                              rst_n,     // Active-low asynchronous reset
    input  wire                              clr_acc,   // Synchronous accumulator clear (broadcast)
    input  wire                              valid_in,  // Feed-valid flag
    input  wire signed [N*DATA_WIDTH-1:0]    a_rows,    // West-edge activations, one per row
    input  wire signed [N*DATA_WIDTH-1:0]    b_cols,    // North-edge weights, one per column
    output wire signed [N*N*ACC_WIDTH-1:0]   c_flat     // Row-major accumulated results
);

    // Inter-PE wires, one extra index so edge PEs read the boundary inputs
    // at index 0 (west for A, north for B).
    wire signed [DATA_WIDTH-1:0] a_link [0:N-1][0:N];   // a_link[i][j]: A entering PE(i,j)
    wire signed [DATA_WIDTH-1:0] b_link [0:N][0:N-1];   // b_link[i][j]: B entering PE(i,j)
    wire                         v_link [0:N-1][0:N];   // valid entering PE(i,j) from the west

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_edge_a
            assign a_link[i][0] = a_rows[i*DATA_WIDTH +: DATA_WIDTH];
            assign v_link[i][0] = valid_in;
        end
        for (j = 0; j < N; j = j + 1) begin : g_edge_b
            assign b_link[0][j] = b_cols[j*DATA_WIDTH +: DATA_WIDTH];
        end

        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                // Southward valid output is unused: valid flows along rows only.
                wire v_south_unused;
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .clr_acc  (clr_acc),
                    .valid_in (v_link[i][j]),
                    .a_in     (a_link[i][j]),
                    .b_in     (b_link[i][j]),
                    .a_out    (a_link[i][j+1]),
                    .b_out    (b_link[i+1][j]),
                    .valid_out(v_link[i][j+1]),
                    .c_out    (c_flat[(i*N+j)*ACC_WIDTH +: ACC_WIDTH])
                );
            end
        end
    endgenerate

endmodule
