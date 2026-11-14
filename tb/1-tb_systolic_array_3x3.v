// ============================================================================
// File: tb_systolic_array_3x3.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Team TensoraX
// Status: PROVISIONAL INTERFACE. The project docs (ARCHITECTURE.md, README)
//         specify the dataflow (A westward per row, B northward per column,
//         1-cycle skew per row/column, output-stationary) but do NOT define
//         the array top-level's port names or bus packing. The DUT hookup
//         below (a_rows/b_cols packed boundary buses, c_flat packed row-major
//         result, valid_in/clr_acc/rst_n) is an assumption consistent with
//         that dataflow. When the actual array RTL is merged, adapt the DUT
//         instantiation and feed tasks to its real ports before reporting
//         results; the check logic itself is interface-independent.
//         The 7-cycle latency assertion assumes the existing pe.v (one
//         registered forwarding hop per PE) and unregistered boundary
//         injection; an extra boundary pipeline stage shifts it by one.
// Description: Top-level self-checking testbench for the 3x3 systolic array.
//              Feeds skewed activation/weight streams, computes a software
//              golden reference inside the testbench, and compares all nine
//              accumulated outputs. Checks:
//                Test 1: unsigned ramp matrices (README reference case)
//                Test 2: signed corner case (negative operands)
//                Test 3: identity weights (C must equal A)
//                Latency: outputs must settle exactly 7 cycles (3N-2) after
//                         the first feed edge
//                Reset: asynchronous rst_n clears all accumulators
// ============================================================================

`timescale 1ns / 1ps

module tb_systolic_array_3x3;

    localparam DATA_WIDTH = 16;
    localparam ACC_WIDTH  = 32;
    localparam N          = 3;

    reg                            clk;
    reg                            rst_n;
    reg                            clr_acc;
    reg                            valid_in;
    reg  signed [N*DATA_WIDTH-1:0] a_rows;
    reg  signed [N*DATA_WIDTH-1:0] b_cols;
    wire signed [N*N*ACC_WIDTH-1:0] c_flat;

    systolic_array_3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .N         (N)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .clr_acc  (clr_acc),
        .valid_in (valid_in),
        .a_rows   (a_rows),
        .b_cols   (b_cols),
        .c_flat   (c_flat)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    integer errors = 0;
    integer i, j, k, t;

    integer A [0:2][0:2];
    integer B [0:2][0:2];
    integer C [0:2][0:2];
    integer measured [0:2][0:2];

    // Feed one skewed wavefront of the current A/B contents.
    // First feed edge (t=0) is the latency reference point.
    task feed_wavefront;
        begin
            @(negedge clk);
            valid_in = 1'b1;
            for (t = 0; t <= 2*N-2; t = t + 1) begin
                for (i = 0; i < N; i = i + 1) begin
                    k = t - i;  // row skew: row i starts i cycles late
                    if (k >= 0 && k < N)
                        a_rows[i*DATA_WIDTH +: DATA_WIDTH] = A[i][k];
                    else
                        a_rows[i*DATA_WIDTH +: DATA_WIDTH] = 0;
                end
                for (j = 0; j < N; j = j + 1) begin
                    k = t - j;  // column skew: column j starts j cycles late
                    if (k >= 0 && k < N)
                        b_cols[j*DATA_WIDTH +: DATA_WIDTH] = B[k][j];
                    else
                        b_cols[j*DATA_WIDTH +: DATA_WIDTH] = 0;
                end
                if (t == 0) clr_acc = 1'b1; else clr_acc = 1'b0;
                @(negedge clk);
            end
            valid_in = 1'b0;
            clr_acc  = 1'b0;
            a_rows   = 0;
            b_cols   = 0;
        end
    endtask

    task compute_golden;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    C[i][j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        C[i][j] = C[i][j] + A[i][k] * B[k][j];
                end
        end
    endtask

    // Capture DUT outputs and compare against golden. Returns mismatch count.
    task check_result;
        input [8*40-1:0] test_name;
        integer local_errors;
        begin
            local_errors = 0;
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    measured[i][j] = c_flat[(i*N+j)*ACC_WIDTH +: ACC_WIDTH];
                    if (measured[i][j] !== C[i][j]) begin
                        $display("[FAIL] %0s: C[%0d][%0d] = %0d, expected %0d",
                                 test_name, i, j, measured[i][j], C[i][j]);
                        local_errors = local_errors + 1;
                    end
                end
            if (local_errors == 0)
                $display("[PASS] %0s: all 9 outputs match golden reference", test_name);
            errors = errors + local_errors;
        end
    endtask

    task print_matrix_c;
        begin
            $display("  Computed Matrix C: [ %0d %0d %0d ; %0d %0d %0d ; %0d %0d %0d ]",
                     measured[0][0], measured[0][1], measured[0][2],
                     measured[1][0], measured[1][1], measured[1][2],
                     measured[2][0], measured[2][1], measured[2][2]);
        end
    endtask

    initial begin
        $dumpfile("sim/tb_systolic_array_3x3.vcd");
        $dumpvars(0, tb_systolic_array_3x3);

        $display("===================================================================");
        $display(" [TensoraX] 3x3 Systolic Array Matrix Multiplication Verification  ");
        $display("===================================================================");

        clk      = 0;
        rst_n    = 0;
        clr_acc  = 0;
        valid_in = 0;
        a_rows   = 0;
        b_cols   = 0;

        #20;
        rst_n = 1;
        #10;

        // ---------------- Test 1: unsigned ramp matrices ----------------
        // Latency reference: feed_wavefront's first drive edge. The array must
        // present correct outputs 7 posedges (3N-2) after that edge.
        A[0][0]=1; A[0][1]=2; A[0][2]=3;
        A[1][0]=4; A[1][1]=5; A[1][2]=6;
        A[2][0]=7; A[2][1]=8; A[2][2]=9;
        B[0][0]=9; B[0][1]=8; B[0][2]=7;
        B[1][0]=6; B[1][1]=5; B[1][2]=4;
        B[2][0]=3; B[2][1]=2; B[2][2]=1;
        compute_golden;

        fork
            feed_wavefront;
            begin
                // Align to the first feed edge, then count 7 posedges (3N-2)
                @(negedge clk);
                repeat (7) @(posedge clk);
                #1;
                check_result("Test1 unsigned ramp (at cycle 7)");
                print_matrix_c;
            end
        join

        // ---------------- Test 2: signed corner case ----------------
        A[0][0]=-3; A[0][1]= 7; A[0][2]=  0;
        A[1][0]= 5; A[1][1]=-8; A[1][2]=  2;
        A[2][0]= 1; A[2][1]=-1; A[2][2]= -6;
        B[0][0]= 4; B[0][1]=-2; B[0][2]=  9;
        B[1][0]=-5; B[1][1]= 3; B[1][2]= -7;
        B[2][0]= 6; B[2][1]= 0; B[2][2]= -1;
        compute_golden;
        feed_wavefront;
        repeat (3) @(negedge clk);
        check_result("Test2 signed corner");
        print_matrix_c;

        // ---------------- Test 3: identity weights (C = A) ----------------
        A[0][0]=11; A[0][1]=-4; A[0][2]=  7;
        A[1][0]= 0; A[1][1]= 9; A[1][2]= -2;
        A[2][0]= 3; A[2][1]= 5; A[2][2]=  8;
        B[0][0]=1; B[0][1]=0; B[0][2]=0;
        B[1][0]=0; B[1][1]=1; B[1][2]=0;
        B[2][0]=0; B[2][1]=0; B[2][2]=1;
        compute_golden;
        feed_wavefront;
        repeat (3) @(negedge clk);
        check_result("Test3 identity weights");
        print_matrix_c;

        // ---------------- Test 4: asynchronous reset ----------------
        @(negedge clk);
        rst_n = 0;
        #1;
        begin : reset_check
            integer ri, rj, rz;
            rz = 0;
            for (ri = 0; ri < N; ri = ri + 1)
                for (rj = 0; rj < N; rj = rj + 1)
                    if (c_flat[(ri*N+rj)*ACC_WIDTH +: ACC_WIDTH] !== 0) rz = rz + 1;
            if (rz == 0)
                $display("[PASS] Test4 reset: all 9 accumulators cleared by rst_n");
            else begin
                $display("[FAIL] Test4 reset: %0d accumulators non-zero after rst_n", rz);
                errors = errors + 1;
            end
        end
        rst_n = 1;

        $display("-------------------------------------------------------------------");
        if (errors == 0)
            $display(" [SUCCESS] 3x3 systolic array verification completed with 0 errors!");
        else
            $display(" [FAILURE] Completed with %0d errors.", errors);
        $display("-------------------------------------------------------------------");

        #20;
        $finish;
    end

endmodule
