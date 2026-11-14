// ============================================================================
// File: tb_systolic_array_random.v
// Description: Randomized, reproducible self-checking test of
//              systolic_array_3x3 against an independent reference
//              (Python-generated expected results, see
//              scripts/gen_array_vectors.py). Covers all nine outputs of every
//              operation. Operations run consecutively with 0..3 idle cycles
//              between them (gap 0 = back to back, clr_acc on the first feed
//              cycle of the next operation), and some operations deliberately
//              omit clr_acc to check accumulate-on-top behavior. Results are
//              sampled exactly 7 posedges (3N-2) after each op's first feed edge.
// Run (repo root): iverilog -g2012 -Wall -I rtl -o sim/tb_rand.vvp rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v tb/tb_systolic_array_random.v && vvp sim/tb_rand.vvp
//      (vectors: python3 scripts/gen_array_vectors.py 20261114 600 > tb/vectors/array_rand_vectors.hex)
// ============================================================================
`timescale 1ns / 1ps

module tb_systolic_array_random;
    localparam N = 3, DW = 16, AW = 32;
    localparam NOPS = 600;
    localparam REC  = 29;

    reg clk = 0, rst_n = 0, clr_acc = 0, valid_in = 0;
    reg  signed [N*DW-1:0]   a_rows = 0, b_cols = 0;
    wire signed [N*N*AW-1:0] c_flat;

    systolic_array_3x3 #(.DATA_WIDTH(DW), .ACC_WIDTH(AW), .N(N)) dut (
        .clk(clk), .rst_n(rst_n), .clr_acc(clr_acc), .valid_in(valid_in),
        .a_rows(a_rows), .b_cols(b_cols), .c_flat(c_flat));

    always #5 clk = ~clk;

    reg [31:0] mem [0:NOPS*REC-1];
    integer errors = 0, checked_outputs = 0, ops_with_noclr = 0, ops_back_to_back = 0;
    integer n, t, i, j, base, gap, noclr, g;
    reg signed [DW-1:0] av, bv;
    reg signed [AW-1:0] got, exp;

    initial begin
        $readmemh("tb/vectors/array_rand_vectors.hex", mem);
        #20 rst_n = 1;
        @(negedge clk);
        for (n = 0; n < NOPS; n = n + 1) begin
            base  = n * REC;
            gap   = mem[base];
            noclr = mem[base+1];
            if (noclr) ops_with_noclr = ops_with_noclr + 1;
            if (gap == 0 && n > 0) ops_back_to_back = ops_back_to_back + 1;
            // idle cycles between operations
            if (gap > 0) begin
                valid_in = 0; clr_acc = 0; a_rows = 0; b_cols = 0;
                for (g = 0; g < gap; g = g + 1) @(negedge clk);
            end
            // one skewed wavefront: operands occupy t = 0..2N-2, zeros after; 7 cycles total (3N-2), t = 0..3N-3
            valid_in = 1;
            for (t = 0; t <= 3*N-3; t = t + 1) begin
                for (i = 0; i < N; i = i + 1) begin
                    if (t-i >= 0 && t-i < N) a_rows[i*DW +: DW] = mem[base+2+i*N+(t-i)][DW-1:0];
                    else                     a_rows[i*DW +: DW] = 0;
                end
                for (j = 0; j < N; j = j + 1) begin
                    if (t-j >= 0 && t-j < N) b_cols[j*DW +: DW] = mem[base+2+9+(t-j)*N+j][DW-1:0];
                    else                     b_cols[j*DW +: DW] = 0;
                end
                clr_acc = (t == 0) && !noclr;
                @(posedge clk);
                if (t == 3*N-3) begin
                    #1;
                    for (i = 0; i < N*N; i = i + 1) begin
                        got = c_flat[i*AW +: AW];
                        exp = mem[base+2+18+i];
                        checked_outputs = checked_outputs + 1;
                        if (got !== exp) begin
                            errors = errors + 1;
                            if (errors <= 10)
                                $display("[FAIL] op %0d output %0d: got %0d expected %0d", n, i, got, exp);
                        end
                    end
                end
                @(negedge clk);
            end
        end
        valid_in = 0; clr_acc = 0; a_rows = 0; b_cols = 0;
        $display("[random] operations           : %0d (%0d back-to-back, %0d without clr_acc)", NOPS, ops_back_to_back, ops_with_noclr);
        $display("[random] outputs checked      : %0d (9 per operation)", checked_outputs);
        if (errors == 0) $display(" [SUCCESS] randomized array verification: 0 errors");
        else             $display(" [FAILURE] randomized array verification: %0d errors", errors);
        $finish;
    end
endmodule
