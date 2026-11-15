// ============================================================================
// File: tb_array_corner_cases.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Role: System Verification & Testbench Lead
// Description: Corner-case and timing verification of systolic_array_3x3,
//              with the array_assertions checker watching every PE on every
//              clock. Golden results are computed inside the testbench in
//              64-bit and wrapped to 32 bits, so overflow cases are checked
//              exactly instead of only printed.
//
//   T01 zero matrices                 T08 hold: idle cycles keep results
//   T02 one-hot routing (27 cases)    T09 hold: garbage inputs while valid_in=0
//   T03 single extreme products       T10 garbage on B skew gaps only
//   T04 largest sums without overflow T11 mid-operation reset and recovery
//   T05 overflow wraps (-32768,32767) T12 per-PE wavefront latency (i+j+3)
//   T06 accumulate without clr_acc    T13 back-to-back operations, no gap
//   T07 clr_acc after accumulation    C01 constraint demo: garbage on both
//                                         A and B skew gaps corrupts C
//
// Run (repo root):
//   mkdir -p sim && iverilog -g2012 -I rtl -o sim/corner.vvp rtl/mac_unit.v \
//     rtl/pe.v rtl/systolic_array_3x3.v tb/array_assertions.v \
//     tb/tb_array_corner_cases.v && vvp sim/corner.vvp
// ============================================================================

`timescale 1ns / 1ps

module tb_array_corner_cases;

    localparam N = 3, DW = 16, AW = 32;

    reg clk = 0, rst_n = 0, clr_acc = 0, valid_in = 0;
    reg  signed [N*DW-1:0]   a_rows = 0, b_cols = 0;
    wire signed [N*N*AW-1:0] c_flat;

    systolic_array_3x3 #(.DATA_WIDTH(DW), .ACC_WIDTH(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc), .valid_in(valid_in),
        .a_rows(a_rows), .b_cols(b_cols), .c_flat(c_flat));

    array_assertions #(.N(N), .DATA_WIDTH(DW), .ACC_WIDTH(AW)) u_chk (
        .clk(clk), .rst_n(rst_n));

    always #5 clk = ~clk;

    integer A [0:2][0:2];
    integer B [0:2][0:2];
    reg signed [AW-1:0] M [0:2][0:2];      // golden accumulator model
    reg signed [63:0]   EX [0:2][0:2];     // exact (unwrapped) value of last op
    integer i, j, k, t, n, errors = 0, tests = 0, failed_tests = 0, local_err;
    integer seed = 20261114;
    reg signed [63:0] wide;
    reg signed [AW-1:0] got;

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------
    function signed [AW-1:0] c_at;
        input integer ri, rj;
        c_at = c_flat[(ri*N+rj)*AW +: AW];
    endfunction

    task set_all;            // fill A and B with constants
        input integer av, bv;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin A[i][j] = av; B[i][j] = bv; end
        end
    endtask

    // Update golden model for one operation (clr=1: load, clr=0: accumulate)
    task golden;
        input clr;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    wide = 0;
                    for (k = 0; k < N; k = k + 1) wide = wide + A[i][k] * B[k][j];
                    EX[i][j] = clr ? wide : (M[i][j] + wide);
                    M[i][j]  = EX[i][j][AW-1:0];
                end
        end
    endtask

    // One skewed operation, 3N-2 = 7 cycles. Inputs are driven on the falling
    // edge. gapA/gapB = 1 puts random garbage into the skew gaps (cycles where
    // a row/column carries no data) instead of zeros. timing = 1 checks every
    // PE is NOT final one cycle before i+j+3 and IS final from cycle i+j+3 on.
    task run_op;
        input clr;
        input gapA;
        input gapB;
        input timing;
        begin
            for (t = 0; t <= 3*N-3; t = t + 1) begin
                @(negedge clk);
                valid_in = 1;
                clr_acc  = (t == 0) && clr;
                for (i = 0; i < N; i = i + 1)
                    a_rows[i*DW +: DW] = (t-i >= 0 && t-i < N) ? A[i][t-i] : (gapA ? $random(seed) : 0);
                for (j = 0; j < N; j = j + 1)
                    b_cols[j*DW +: DW] = (t-j >= 0 && t-j < N) ? B[t-j][j] : (gapB ? $random(seed) : 0);
                @(posedge clk);
                #1;
                if (timing)
                    for (i = 0; i < N; i = i + 1)
                        for (j = 0; j < N; j = j + 1) begin
                            if (t + 1 == i + j + 2 && c_at(i, j) === M[i][j]) begin
                                $display("  [timing] PE(%0d,%0d) already final at cycle %0d (expected cycle %0d)", i, j, t+1, i+j+3);
                                local_err = local_err + 1;
                            end
                            if (t + 1 >= i + j + 3 && c_at(i, j) !== M[i][j]) begin
                                $display("  [timing] PE(%0d,%0d) not final at cycle %0d (expected by cycle %0d)", i, j, t+1, i+j+3);
                                local_err = local_err + 1;
                            end
                        end
            end
            @(negedge clk);
            valid_in = 0; clr_acc = 0; a_rows = 0; b_cols = 0;
        end
    endtask

    task idle;
        input integer cycles;
        integer c;
        begin
            for (c = 0; c < cycles; c = c + 1) @(negedge clk);
        end
    endtask

    // Compare all 9 outputs with the golden model
    task compare;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    if (c_at(i, j) !== M[i][j]) begin
                        got = c_at(i, j);
                        $display("  C[%0d][%0d] = %0d, expected %0d", i, j, got, M[i][j]);
                        local_err = local_err + 1;
                    end
        end
    endtask

    task begin_test;
        begin local_err = 0; tests = tests + 1; end
    endtask

    task end_test;
        input [8*48-1:0] name;
        begin
            if (local_err == 0) $display("[PASS] %0s", name);
            else begin
                $display("[FAIL] %0s (%0d mismatches)", name, local_err);
                failed_tests = failed_tests + 1;
                errors = errors + local_err;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // test sequence
    // ------------------------------------------------------------------
    integer oi, ok, oj, hits;
    reg signed [AW-1:0] snap [0:2][0:2];

    initial begin
        $dumpfile("sim/tb_array_corner_cases.vcd");
        $dumpvars(0, tb_array_corner_cases);
        $display("===================================================================");
        $display(" [TensoraX] Corner-case, timing and assertion verification (3x3)");
        $display("===================================================================");
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) M[i][j] = 0;
        #22 rst_n = 1;

        // T01 ---------------------------------------------------------
        begin_test; set_all(0, 0); golden(1); run_op(1, 0, 0, 0); compare;
        end_test("T01 zero matrices give zero output");

        // T02 ---------------------------------------------------------
        // A has a single non-zero at (oi,ok), B a single non-zero at (ok,oj):
        // only C[oi][oj] may change. Catches any row/column mis-wiring.
        begin_test;
        for (oi = 0; oi < N; oi = oi + 1)
            for (ok = 0; ok < N; ok = ok + 1)
                for (oj = 0; oj < N; oj = oj + 1) begin
                    set_all(0, 0);
                    A[oi][ok] = 1 + oi*3 + ok;          // 1..9
                    B[ok][oj] = 11 + ok*3 + oj;         // 11..19
                    golden(1); run_op(1, 0, 0, 0); compare;
                end
        end_test("T02 one-hot routing, 27/27 (i,k,j) cases");

        // T03 ---------------------------------------------------------
        begin_test;
        set_all(0, 0);
        A[0][0] = 32767;  A[1][1] = -32768; A[2][2] = 32767;
        B[0][0] = 32767;  B[0][1] = -32768; B[0][2] = 1;
        B[1][0] = -32768; B[1][1] = -32768; B[1][2] = 0;
        B[2][0] = -1;     B[2][1] = 32767;  B[2][2] = -32768;
        golden(1); run_op(1, 0, 0, 0); compare;
        end_test("T03 single extreme products (+-2^30 range)");

        // T04 ---------------------------------------------------------
        // Largest dot products that still fit in signed 32 bits:
        // (-32768)^2 + 32767^2 = 2147418113 and its negative counterpart.
        begin_test;
        set_all(0, 0);
        A[0][0] = -32768; A[0][1] = 32767;
        A[1][0] = -32768; A[1][1] = -32768;
        A[2][0] = 32767;  A[2][1] = -32768;
        B[0][0] = -32768; B[1][0] = 32767;
        B[0][1] = 32767;  B[1][1] = 32767;
        B[0][2] = -32768; B[1][2] = 32767;
        golden(1); run_op(1, 0, 0, 0); compare;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1)
            if (EX[i][j] !== {{32{M[i][j][31]}}, M[i][j]}) local_err = local_err + 1;
        $display("  C[0][0] = %0d (max representable 2147483647)", M[0][0]);
        end_test("T04 near-limit sums, no overflow");

        // T05 ---------------------------------------------------------
        begin_test;
        set_all(-32768, -32768); golden(1); run_op(1, 0, 0, 0); compare;
        $display("  all -32768: exact %0d -> wrapped %0d", EX[0][0], M[0][0]);
        set_all(32767, 32767); golden(1); run_op(1, 0, 0, 0); compare;
        $display("  all  32767: exact %0d -> wrapped %0d", EX[0][0], M[0][0]);
        end_test("T05 overflow wraps as 32-bit two's complement");

        // T06 ---------------------------------------------------------
        begin_test;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = i*N + j + 1; B[i][j] = 9 - (i*N + j);
        end
        golden(1); run_op(1, 0, 0, 0);
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = (i == j) ? 2 : -1; B[i][j] = i - j;
        end
        golden(0); run_op(0, 0, 0, 0); compare;
        end_test("T06 accumulate on top without clr_acc");

        // T07 ---------------------------------------------------------
        begin_test;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = 3 - i; B[i][j] = j + 2;
        end
        golden(1); run_op(1, 0, 0, 0); compare;
        end_test("T07 clr_acc discards the previous result");

        // T08 ---------------------------------------------------------
        begin_test; idle(12); compare;
        end_test("T08 results hold for 12 idle cycles");

        // T09 ---------------------------------------------------------
        begin_test;
        for (n = 0; n < 16; n = n + 1) begin
            @(negedge clk); valid_in = 0; a_rows = {$random(seed), $random(seed)}; b_cols = {$random(seed), $random(seed)};
        end
        @(negedge clk); a_rows = 0; b_cols = 0;
        compare;
        end_test("T09 garbage inputs ignored while valid_in=0");

        // T10 ---------------------------------------------------------
        begin_test;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = (i*7 + j*5) % 11 - 5; B[i][j] = (i*3 + j*13) % 17 - 8;
        end
        golden(1); run_op(1, 0, 1, 0); compare;
        end_test("T10 garbage on B skew gaps only is harmless");

        // T11 ---------------------------------------------------------
        // Reset in the middle of an operation; the checker (A3) verifies all
        // PE registers read zero while rst_n is low. Then a full operation
        // must still be exact.
        begin_test;
        set_all(5, -7);
        fork
            run_op(1, 0, 0, 0);
            begin
                repeat (3) @(posedge clk);
                #3 rst_n = 0;
                #1;
                for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1)
                    if (c_at(i, j) !== 0) local_err = local_err + 1;
                @(negedge clk); #2 rst_n = 1;
            end
        join
        idle(2);
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = j - i; B[i][j] = i + j + 1;
        end
        golden(1); run_op(1, 0, 0, 0); compare;
        end_test("T11 mid-operation reset clears and recovers");

        // T12 ---------------------------------------------------------
        begin_test;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = i + j + 2; B[i][j] = 2*i - j + 5;   // last terms non-zero
        end
        golden(1); run_op(1, 0, 0, 1); compare;
        end_test("T12 PE(i,j) final exactly at cycle i+j+3");

        // T13 ---------------------------------------------------------
        begin_test;
        set_all(4, 4); golden(1); run_op(1, 0, 0, 0);
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = -i - 1; B[i][j] = j * 6 - 2;
        end
        // next operation starts on the very next edge (run_op ends on a
        // falling edge and the next one drives on the following one)
        golden(1); run_op(1, 0, 0, 0); compare;
        end_test("T13 back-to-back operations");

        // C01 ---------------------------------------------------------
        // Documented interface constraint, not a pass/fail test: when BOTH
        // the A and B skew gaps carry non-zero data, gap values meet inside
        // the array while valid is high and are accumulated.
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1) begin
            A[i][j] = i + 1; B[i][j] = j + 1;
        end
        golden(1); run_op(1, 1, 1, 0);
        hits = 0;
        for (i = 0; i < N; i = i + 1) for (j = 0; j < N; j = j + 1)
            if (c_at(i, j) !== M[i][j]) hits = hits + 1;
        $display("[INFO] C01 garbage on both A and B skew gaps: %0d of 9 outputs corrupted", hits);
        $display("       -> skew gaps must be zero on at least one side (README/tb drive zeros)");

        // summary -----------------------------------------------------
        idle(2);
        $display("-------------------------------------------------------------------");
        u_chk.report;
        if (failed_tests == 0 && u_chk.assert_fail == 0)
            $display(" [SUCCESS] corner-case verification: %0d/%0d tests passed, 0 assertion failures", tests, tests);
        else
            $display(" [FAILURE] %0d/%0d tests failed, %0d assertion failures", failed_tests, tests, u_chk.assert_fail);
        $display("-------------------------------------------------------------------");
        $finish;
    end

endmodule
