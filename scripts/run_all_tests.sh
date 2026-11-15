#!/bin/bash
# ==============================================================================
# Script: run_all_tests.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Role: System Verification & Testbench Lead
# Description: One-command regression. Compiles and runs every testbench with
#              Icarus Verilog (array testbenches with the array_assertions
#              checker enabled), runs the Python golden model, and prints a
#              PASS/FAIL table. Exit code is non-zero if anything fails.
# Usage (repo root): ./scripts/run_all_tests.sh
# Requires: iverilog/vvp (Icarus Verilog 11+), python3
# ==============================================================================

cd "$(dirname "$0")/.." || exit 1
mkdir -p sim

RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v"
CHK="tb/array_assertions.v"
FLAGS="-g2012 -I rtl"
FAILS=0
RESULTS=()

run_tb() {
    local name="$1" pass_regex="$2" srcs="$3" defs="$4"
    local log="sim/${name}.log"
    if ! iverilog $FLAGS $defs -o "sim/${name}.vvp" $srcs > "$log" 2>&1; then
        RESULTS+=("FAIL | $name | compile error (see $log)"); FAILS=$((FAILS+1)); return
    fi
    vvp "sim/${name}.vvp" >> "$log" 2>&1
    local summary
    summary=$(grep -E "SUCCESS|FAILURE|\[assertions\]|C00=" "$log" | tr -s ' ' | paste -sd ';' -)
    if grep -qE "$pass_regex" "$log" && ! grep -qE "FAILURE|ASSERT-FAIL|\[FAIL\]" "$log"; then
        RESULTS+=("PASS | $name | $summary")
    else
        RESULTS+=("FAIL | $name | $summary (see $log)"); FAILS=$((FAILS+1))
    fi
}

echo "=================================================================="
echo " [TensoraX] Full regression"
echo "=================================================================="

run_tb "pe_unit"       "0 errors"  "rtl/mac_unit.v rtl/pe.v tb/tb_pe.v" ""
run_tb "array_directed" "0 errors" "$RTL $CHK tb/tb_systolic_array_3x3.v" "-DTENSORAX_ASSERT"
run_tb "array_random"   "0 errors" "$RTL $CHK tb/tb_systolic_array_random.v" "-DTENSORAX_ASSERT"
run_tb "array_corner"   "0 assertion failures" "$RTL $CHK tb/tb_array_corner_cases.v" ""
run_tb "array_overflow" "C00=-1073741824 .*wrapped expected -1073741824" "$RTL tb/tb_array_overflow_check.v" ""

if python3 scripts/pe_golden_model.py > sim/golden_model.log 2>&1 && grep -q "VERIFIED" sim/golden_model.log; then
    RESULTS+=("PASS | python_golden | PE reference model")
else
    RESULTS+=("FAIL | python_golden | see sim/golden_model.log"); FAILS=$((FAILS+1))
fi

echo
for r in "${RESULTS[@]}"; do
    IFS='|' read -r st nm rest <<< "$r"
    printf '%-5s %-16s %s\n' "$st" "$nm" "$rest"
done
echo "------------------------------------------------------------------"
if [ "$FAILS" -eq 0 ]; then
    echo " [SUCCESS] all ${#RESULTS[@]} regression items passed"
else
    echo " [FAILURE] $FAILS of ${#RESULTS[@]} regression items failed"
fi
echo " Waveforms: sim/*.vcd  (GTKWave views: docs/waveforms/*.gtkw)"
exit "$FAILS"
