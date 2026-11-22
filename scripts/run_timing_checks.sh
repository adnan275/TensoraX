#!/bin/bash
# ==============================================================================
# Script: run_timing_checks.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
# Description: Runs tb/tb_array_timing_check.v in two sweeps and prints a table.
#   A) N = 3, tile spacing S = 3..9: shows the smallest spacing at which the
#      broadcast clr_acc leaves both tiles correct (expected: S = 3N-2 = 7).
#   B) N = 2..8, S = 3N-2: shows that a tile completes exactly 3N-2 posedges
#      after its first feed edge for every array size the RTL generates.
#   Exit code is non-zero if any run disagrees with the prediction.
# Usage (repo root): ./scripts/run_timing_checks.sh [output_file]
# Requires: iverilog/vvp (Icarus Verilog 11+)
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
OUT="${1:-}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v"
FAILS=0

run_case() {  # N S
    local n=$1 s=$2
    iverilog -g2012 -Wall -I rtl -P tb_array_timing_check.N="$n" -P tb_array_timing_check.S="$s" \
        -o "$TMP/t_${n}_${s}.vvp" $RTL tb/tb_array_timing_check.v 2>"$TMP/cc.log" || { cat "$TMP/cc.log"; FAILS=$((FAILS+1)); return; }
    local log
    log=$(vvp "$TMP/t_${n}_${s}.vvp")
    echo "$log" | grep -E "^(RESULT|VERDICT)"
    echo "$log" | grep -q "^VERDICT PASS" || FAILS=$((FAILS+1))
}

report() {
    echo "=================================================================="
    echo " [TensoraX] Timing checks: tile spacing and latency (RTL simulation)"
    echo "=================================================================="
    echo
    echo "--- A) N=3, two tiles S cycles apart, global clr_acc on each tile's first feed cycle"
    for s in 3 4 5 6 7 8 9; do run_case 3 $s; done
    echo
    echo "--- B) latency 3N-2 for N = 2..8 (S = 3N-2)"
    for n in 2 3 4 5 6 7 8; do run_case $n $((3*n-2)); done
    echo
    echo "------------------------------------------------------------------"
    if [ "$FAILS" -eq 0 ]; then echo " [SUCCESS] all timing checks agree with the 3N-2 prediction"
    else echo " [FAILURE] $FAILS timing check(s) disagree with the prediction"; fi
}

# Run in this shell (not in a pipe) so that FAILS survives for the exit code.
report > "$TMP/report.txt"
cat "$TMP/report.txt"
if [ -n "$OUT" ]; then mkdir -p "$(dirname "$OUT")" && cp "$TMP/report.txt" "$OUT"; fi
exit "$FAILS"
