// ============================================================================
// File: tb_array_timing_check.v
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
// Description: Measures two timing properties of systolic_array_3x3 that the
//              performance analysis depends on. Two tiles are fed S cycles
//              apart with the normal skewed schedule and a global clr_acc pulse
//              on the first feed cycle of each tile (the way every other
//              testbench in this repo drives the array).
//
//   1. Latency: a tile's result is complete 3N-2 posedges after its first feed
//      edge, and PE(N-1,N-1) is still incomplete one edge earlier.
//   2. Tile spacing: with the clear broadcast to all PEs at once, the next tile
//      can start no sooner than S = 3N-2 cycles after the previous one. At a
//      smaller S the clear wipes accumulators that are still mid-tile, or the
//      next tile accumulates on top of the previous one. Sustained utilisation
//      of this RTL is therefore N^3 / (N^2 (3N-2)) = N/(3N-2), not the ~100%
//      that back-to-back tiles every N cycles would give.
//
// Parameters (override with iverilog -P): N = array size (2..8), S = tile spacing.
// Output: one line "RESULT N=.. S=.. ..." and a verdict PASS/FAIL that expects
//         correct results exactly when S >= 3N-2.
// Run: scripts/run_timing_checks.sh
// ============================================================================
`timescale 1ns / 1ps

module tb_array_timing_check;
    parameter N  = 3;
    parameter S  = 7;
    localparam DW = 16, AW = 32;
    localparam NN = N * N;

    reg clk = 0, rst_n = 0, clr_acc = 0, valid_in = 0;
    reg  signed [N*DW-1:0]  a_rows = 0, b_cols = 0;
    wire signed [NN*AW-1:0] c_flat;

    systolic_array_3x3 #(.DATA_WIDTH(DW), .ACC_WIDTH(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc), .valid_in(valid_in),
        .a_rows(a_rows), .b_cols(b_cols), .c_flat(c_flat));

    always #5 clk = ~clk;

    integer A [0:1][0:7][0:7];
    integer B [0:1][0:7][0:7];
    integer G [0:1][0:7][0:7];
    integer hist [0:127][0:63];     // hist[e][p]: c_flat slice p just after posedge e

    integer m, i, j, k, tau, tl, p, e;
    integer wrong_t1, wrong_t2, wrong_t2_final, early_done;
    integer ok_expected, ok_actual;

    initial begin
        for (m = 0; m < 2; m = m + 1)
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    // tile 0 is strictly positive so the last product is non-zero;
                    // tile 1 is signed.
                    if (m == 0) begin
                        A[m][i][j] = ((i*7 + j*5 + 3) % 11) + 1;
                        B[m][i][j] = ((i*3 + j*13 + 1) % 9) + 1;
                    end else begin
                        A[m][i][j] = ((i*7 + j*5 + 2) % 11) - 5;
                        B[m][i][j] = ((i*3 + j*13 + 7) % 9) - 4;
                    end
                end
        for (m = 0; m < 2; m = m + 1)
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    G[m][i][j] = 0;
                    for (k = 0; k < N; k = k + 1)
                        G[m][i][j] = G[m][i][j] + A[m][i][k] * B[m][k][j];
                end

        #22 rst_n = 1;
        @(negedge clk);
        valid_in = 1;
        for (tau = 0; tau < S + 3*N + 4; tau = tau + 1) begin
            a_rows = 0; b_cols = 0; clr_acc = 0;
            for (m = 0; m < 2; m = m + 1) begin
                tl = tau - m*S;
                if (tl == 0) clr_acc = 1;
                for (i = 0; i < N; i = i + 1)
                    if (tl - i >= 0 && tl - i < N) a_rows[i*DW +: DW] = A[m][i][tl-i];
                for (j = 0; j < N; j = j + 1)
                    if (tl - j >= 0 && tl - j < N) b_cols[j*DW +: DW] = B[m][tl-j][j];
            end
            @(posedge clk); #1;
            // posedge e = tau+1 is the edge that captures the data driven for feed time tau
            for (p = 0; p < NN; p = p + 1) hist[tau+1][p] = $signed(c_flat[p*AW +: AW]);
            @(negedge clk);
        end

        // Tile m, PE(i,j) takes its last product at posedge m*S + i + j + N.
        wrong_t1 = 0; wrong_t2 = 0; wrong_t2_final = 0;
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                p = i*N + j;
                if (hist[i+j+N][p]      !== G[0][i][j]) wrong_t1       = wrong_t1 + 1;
                if (hist[S+i+j+N][p]    !== G[1][i][j]) wrong_t2       = wrong_t2 + 1;
                if (hist[S+3*N-2][p]    !== G[1][i][j]) wrong_t2_final = wrong_t2_final + 1;
            end
        // One edge before 3N-2 the corner PE must not yet hold tile 0's final value.
        early_done = (hist[3*N-3][NN-1] === G[0][N-1][N-1]) ? 1 : 0;

        ok_expected = (S >= 3*N - 2);
        ok_actual   = (wrong_t1 == 0) && (wrong_t2 == 0) && (wrong_t2_final == 0) && (early_done == 0);
        $display("RESULT N=%0d S=%0d latency=%0d edges (3N-2=%0d) | tile1 per-PE readout wrong %0d/%0d | tile2 per-PE readout wrong %0d/%0d | tile2 read at 3N-2 wrong %0d/%0d | corner PE done one edge early: %0s",
                 N, S, 3*N-2, 3*N-2, wrong_t1, NN, wrong_t2, NN, wrong_t2_final, NN, early_done ? "YES" : "no");
        if (ok_actual == ok_expected)
            $display("VERDICT PASS N=%0d S=%0d (%0s)", N, S,
                     ok_expected ? "S >= 3N-2: both tiles correct" : "S < 3N-2: corruption observed, as predicted");
        else
            $display("VERDICT FAIL N=%0d S=%0d (expected %0s)", N, S, ok_expected ? "correct results" : "corruption");
        $finish;
    end
endmodule
