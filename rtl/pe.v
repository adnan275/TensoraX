// ============================================================================
// File: pe.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)
// Description: Core 2D Systolic Processing Element (PE) module.
//              Combines a 16-bit MAC unit with spatial data propagation
//              registers for horizontal (A) and vertical (B) wavefront passing.
// ============================================================================

`timescale 1ns / 1ps
`include "tensora_pkg.vh"

module pe #(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,      // Active-low asynchronous reset
    input  wire                         clr_acc,    // Synchronous accumulator clear
    input  wire                         valid_in,   // Valid input flag
    input  wire signed [DATA_WIDTH-1:0] a_in,       // Horizontal streaming input (from West)
    input  wire signed [DATA_WIDTH-1:0] b_in,       // Vertical streaming input (from North)
    
    output reg  signed [DATA_WIDTH-1:0] a_out,      // Pipelined horizontal forwarding (to East)
    output reg  signed [DATA_WIDTH-1:0] b_out,      // Pipelined vertical forwarding (to South)
    output reg                          valid_out,  // Propagated control valid
    output wire signed [ACC_WIDTH-1:0]  c_out       // Local accumulated dot-product result
);

    // Instantiate Dedicated MAC Unit
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_mac (
        .clk     (clk),
        .rst_n   (rst_n),
        .clr_acc (clr_acc),
        .mac_en  (valid_in),
        .a_val   (a_in),
        .b_val   (b_in),
        .acc_out (c_out)
    );

    // Spatial Forwarding Pipeline Registers (Wavefront Dataflow)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out     <= {DATA_WIDTH{1'b0}};
            b_out     <= {DATA_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else begin
            a_out     <= a_in;
            b_out     <= b_in;
            valid_out <= valid_in;
        end
    end

endmodule
