// ============================================================================
// File: array_assertions.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Role: System Verification & Testbench Lead
// Description: Cycle-by-cycle assertion checker for systolic_array_3x3.
//              Instantiate it inside a testbench next to an instance named
//              `dut`; it watches every PE through hierarchical references
//              (dut.g_row[i].g_col[j].u_pe.*) and checks these invariants on
//              every clock edge, independently of what the testbench expects:
//
//   A1  FORWARD  a_out/b_out/valid_out equal last cycle's a_in/b_in/valid_in
//   A2  MAC      acc' = acc + a*b (valid, no clr)    | acc' = a*b (valid, clr)
//                acc' = 0         (no valid, clr)    | acc' = acc (hold)
//                with 32-bit two's-complement wrap
//   A3  RESET    while rst_n is low every PE register is zero
//   A4  NO-X     after reset no PE output is X or Z
//   A5  LINK     PE(i,j+1).a_in == PE(i,j).a_out, PE(i+1,j).b_in == PE(i,j).b_out,
//                PE(i,j+1).valid_in == PE(i,j).valid_out
//   A6  EDGE     west/north PE inputs equal the a_rows/b_cols/valid_in ports
//   A7  OUTMAP   c_flat[(i*N+j)] == PE(i,j).c_out (row-major output mapping)
//
//   Icarus Verilog has no concurrent SVA, so each assertion is written as an
//   explicit check that increments assert_fail and prints [ASSERT-FAIL].
//   Call report task (or read assert_fail/assert_checks) at end of test.
// ============================================================================

`timescale 1ns / 1ps

module array_assertions #(
    parameter N          = 3,
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32,
    parameter MAX_PRINT  = 20
)(
    input wire clk,
    input wire rst_n
);

    integer assert_checks = 0;
    integer assert_fail   = 0;
    integer fail_by_id [1:7];
    integer k_init;
    initial for (k_init = 1; k_init <= 7; k_init = k_init + 1) fail_by_id[k_init] = 0;

    task fail;
        input integer id;
        input integer pi;
        input integer pj;
        input [8*60-1:0] msg;
        begin
            assert_fail    = assert_fail + 1;
            fail_by_id[id] = fail_by_id[id] + 1;
            if (assert_fail <= MAX_PRINT)
                $display("[ASSERT-FAIL] A%0d PE(%0d,%0d) t=%0t: %0s", id, pi, pj, $time, msg);
        end
    endtask

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_ci
            for (gj = 0; gj < N; gj = gj + 1) begin : g_cj

                // Pre-edge snapshot of this PE
                reg signed [DATA_WIDTH-1:0] a_prev, b_prev;
                reg                         v_prev, clr_prev, rst_prev;
                reg signed [ACC_WIDTH-1:0]  c_prev, c_exp;
                reg signed [2*ACC_WIDTH-1:0] wide;

                always @(posedge clk) begin
                    // Values read at the edge are the pre-edge values
                    a_prev   = dut.g_row[gi].g_col[gj].u_pe.a_in;
                    b_prev   = dut.g_row[gi].g_col[gj].u_pe.b_in;
                    v_prev   = dut.g_row[gi].g_col[gj].u_pe.valid_in;
                    clr_prev = dut.g_row[gi].g_col[gj].u_pe.clr_acc;
                    c_prev   = dut.g_row[gi].g_col[gj].u_pe.c_out;
                    rst_prev = rst_n;
                    #1;
                    if (rst_n && rst_prev) begin
                        // ---- A1 forwarding ----
                        assert_checks = assert_checks + 3;
                        if (dut.g_row[gi].g_col[gj].u_pe.a_out !== a_prev)
                            fail(1, gi, gj, "a_out is not last cycle's a_in");
                        if (dut.g_row[gi].g_col[gj].u_pe.b_out !== b_prev)
                            fail(1, gi, gj, "b_out is not last cycle's b_in");
                        if (dut.g_row[gi].g_col[gj].u_pe.valid_out !== v_prev)
                            fail(1, gi, gj, "valid_out is not last cycle's valid_in");

                        // ---- A2 MAC / clear / hold ----
                        if (clr_prev && v_prev)       wide = a_prev * b_prev;
                        else if (clr_prev)            wide = 0;
                        else if (v_prev)              wide = c_prev + a_prev * b_prev;
                        else                          wide = c_prev;
                        c_exp = wide[ACC_WIDTH-1:0];
                        assert_checks = assert_checks + 1;
                        if (dut.g_row[gi].g_col[gj].u_pe.c_out !== c_exp)
                            fail(2, gi, gj, "accumulator update rule violated");
                    end
                end

                // ---- A3 reset: checked on every edge while held low ----
                always @(posedge clk or negedge rst_n) begin
                    #1;
                    if (!rst_n) begin
                        assert_checks = assert_checks + 1;
                        if (dut.g_row[gi].g_col[gj].u_pe.c_out     !== 0 ||
                            dut.g_row[gi].g_col[gj].u_pe.a_out     !== 0 ||
                            dut.g_row[gi].g_col[gj].u_pe.b_out     !== 0 ||
                            dut.g_row[gi].g_col[gj].u_pe.valid_out !== 0)
                            fail(3, gi, gj, "register not zero while rst_n low");
                    end
                end

                // ---- A4 no X/Z, A5 links, A6 edges, A7 output map ----
                // Sampled 1 ns after the falling edge, once testbench drives
                // made on that edge have settled through continuous assigns.
                always @(negedge clk) begin
                    #1;
                    if (rst_n) begin
                        assert_checks = assert_checks + 1;
                        if (^dut.g_row[gi].g_col[gj].u_pe.c_out === 1'bx ||
                            ^dut.g_row[gi].g_col[gj].u_pe.a_out === 1'bx ||
                            ^dut.g_row[gi].g_col[gj].u_pe.b_out === 1'bx)
                            fail(4, gi, gj, "X or Z on a PE output");

                        if (gj < N-1) begin
                            assert_checks = assert_checks + 2;
                            if (dut.g_row[gi].g_col[(gj<N-1)?gj+1:gj].u_pe.a_in !== dut.g_row[gi].g_col[gj].u_pe.a_out)
                                fail(5, gi, gj, "east neighbour a_in != a_out");
                            if (dut.g_row[gi].g_col[(gj<N-1)?gj+1:gj].u_pe.valid_in !== dut.g_row[gi].g_col[gj].u_pe.valid_out)
                                fail(5, gi, gj, "east neighbour valid_in != valid_out");
                        end
                        if (gi < N-1) begin
                            assert_checks = assert_checks + 1;
                            if (dut.g_row[(gi<N-1)?gi+1:gi].g_col[gj].u_pe.b_in !== dut.g_row[gi].g_col[gj].u_pe.b_out)
                                fail(5, gi, gj, "south neighbour b_in != b_out");
                        end
                        if (gj == 0) begin
                            assert_checks = assert_checks + 2;
                            if (dut.g_row[gi].g_col[gj].u_pe.a_in !== dut.a_rows[gi*DATA_WIDTH +: DATA_WIDTH])
                                fail(6, gi, gj, "west edge a_in != a_rows slice");
                            if (dut.g_row[gi].g_col[gj].u_pe.valid_in !== dut.valid_in)
                                fail(6, gi, gj, "west edge valid_in != port");
                        end
                        if (gi == 0) begin
                            assert_checks = assert_checks + 1;
                            if (dut.g_row[gi].g_col[gj].u_pe.b_in !== dut.b_cols[gj*DATA_WIDTH +: DATA_WIDTH])
                                fail(6, gi, gj, "north edge b_in != b_cols slice");
                        end
                        assert_checks = assert_checks + 1;
                        if (dut.c_flat[(gi*N+gj)*ACC_WIDTH +: ACC_WIDTH] !== dut.g_row[gi].g_col[gj].u_pe.c_out)
                            fail(7, gi, gj, "c_flat slice != PE c_out");
                    end
                end
            end
        end
    endgenerate

    task report;
        integer r;
        begin
            $display("[assertions] %0d checks evaluated, %0d failures", assert_checks, assert_fail);
            for (r = 1; r <= 7; r = r + 1)
                if (fail_by_id[r] != 0)
                    $display("[assertions]   A%0d failures: %0d", r, fail_by_id[r]);
        end
    endtask

endmodule
