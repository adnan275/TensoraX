// ============================================================================
// File: mac_unit.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)
// Description: Synthesizable 16-bit Multiply-Accumulate (MAC) arithmetic unit.
//              Performs signed multiplication (16x16 -> 32) and accumulates
//              into a 32-bit internal register with clear and enable control.
//              Priority order: rst_n (async) > clr_acc (sync) > mac_en (enable).
// ============================================================================

`timescale 1ns / 1ps
`include "tensora_pkg.vh"

module mac_unit #(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,      // Active-low asynchronous reset
    input  wire                         clr_acc,    // Synchronous accumulator clear for new GEMM tile
    input  wire                         mac_en,     // MAC computation enable
    input  wire signed [DATA_WIDTH-1:0] a_val,      // Activation input (Matrix A element)
    input  wire signed [DATA_WIDTH-1:0] b_val,      // Weight input (Matrix B element)
    output reg  signed [ACC_WIDTH-1:0]  acc_out     // 32-bit Accumulated output
);

    // Internal signed product signal (16-bit * 16-bit -> 32-bit signed)
    wire signed [ACC_WIDTH-1:0] product;
    assign product = a_val * b_val;

    // Accumulation register:
    // Priority order:
    // 1. Asynchronous active-low reset (!rst_n) clears acc_out to 0
    // 2. Synchronous clr_acc initializes acc_out with current product (if mac_en) or 0
    // 3. Normal mac_en accumulates: acc_out <= acc_out + product
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= {ACC_WIDTH{1'b0}};
        end else if (clr_acc) begin
            if (mac_en) begin
                acc_out <= product;
            end else begin
                acc_out <= {ACC_WIDTH{1'b0}};
            end
        end else if (mac_en) begin
            acc_out <= acc_out + product;
        end
    end

endmodule
