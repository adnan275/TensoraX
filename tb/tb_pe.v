// ============================================================================
// File: tb_pe.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)
// Description: Unit-level self-checking testbench for Processing Element (PE).
//              Verifies MAC computation, spatial forwarding, and accumulator
//              reset under various signed test vectors.
// ============================================================================

`timescale 1ns / 1ps

module tb_pe;

    parameter DATA_WIDTH = 16;
    parameter ACC_WIDTH  = 32;

    // DUT Signals
    reg                          clk;
    reg                          rst_n;
    reg                          clr_acc;
    reg                          valid_in;
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  signed [DATA_WIDTH-1:0] b_in;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire                         valid_out;
    wire signed [ACC_WIDTH-1:0]  c_out;

    // Instantiate Processing Element (DUT)
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .clr_acc   (clr_acc),
        .valid_in  (valid_in),
        .a_in      (a_in),
        .b_in      (b_in),
        .a_out     (a_out),
        .b_out     (b_out),
        .valid_out (valid_out),
        .c_out     (c_out)
    );

    // Clock Generation: 100 MHz (10ns period)
    always #5 clk = ~clk;

    integer errors = 0;

    initial begin
        // Setup Waveform Dump for GTKWave
        $dumpfile("sim/tb_pe.vcd");
        $dumpvars(0, tb_pe);

        $display("---------------------------------------------------------------");
        $display(" [TensoraX] Starting Processing Element (PE) Unit Verification ");
        $display("---------------------------------------------------------------");

        // Initialization
        clk      = 0;
        rst_n    = 0;
        clr_acc  = 0;
        valid_in = 0;
        a_in     = 0;
        b_in     = 0;

        // Apply Reset
        #15;
        rst_n = 1;
        #10;

        // Drive inputs on falling edge to give stable setup time
        @(negedge clk);
        clr_acc  = 1'b1; // Start new accumulation
        valid_in = 1'b1;
        a_in     = 16'sd3;
        b_in     = 16'sd4;

        // Wait for clock edge where PE samples (A=3, B=4)
        @(posedge clk);
        #1; // Post-edge check: forwarding registers must capture input values
        if (a_out !== 16'sd3 || b_out !== 16'sd4) begin
            $display("[FAIL] Time %0t: Pipelined Forwarding Error. a_out=%0d (exp 3), b_out=%0d (exp 4)", $time, a_out, b_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] Time %0t: Pipelined Forwarding verified: a_out=%0d, b_out=%0d", $time, a_out, b_out);
        end

        // Vector 2: A=5, B=-2 -> Product = -10, Acc = 12 + (-10) = 2
        @(negedge clk);
        clr_acc = 1'b0;
        a_in    = 16'sd5;
        b_in    = -16'sd2;

        @(posedge clk);
        #1;
        if (a_out !== 16'sd5 || b_out !== -16'sd2) begin
            $display("[FAIL] Time %0t: Pipelined Forwarding Error: a_out=%0d, b_out=%0d", $time, a_out, b_out);
            errors = errors + 1;
        end

        // Vector 3: A=7, B=6 -> Product = 42, Acc = 2 + 42 = 44
        @(negedge clk);
        a_in = 16'sd7;
        b_in = 16'sd6;

        @(posedge clk);
        #1;

        // Idle state
        @(negedge clk);
        valid_in = 1'b0;
        a_in     = 16'sd0;
        b_in     = 16'sd0;

        @(posedge clk);
        #1;
        // Verify final accumulated dot-product
        if (c_out !== 32'sd44) begin
            $display("[FAIL] Time %0t: Accumulator mismatch: c_out=%0d (Expected: 44)", $time, c_out);
            errors = errors + 1;
        end else begin
            $display("[PASS] Time %0t: Dot-Product Accumulation Correct! c_out=%0d (Expected: 44)", $time, c_out);
        end

        // Summary
        $display("---------------------------------------------------------------");
        if (errors == 0) begin
            $display(" [SUCCESS] Processing Element verification completed with 0 errors!");
        end else begin
            $display(" [FAILURE] Completed with %0d errors.", errors);
        end
        $display("---------------------------------------------------------------");

        #20;
        $finish;
    end

endmodule
