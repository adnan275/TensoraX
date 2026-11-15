#!/bin/bash
# ==============================================================================
# Script: mutation_check.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Role: System Verification & Testbench Lead
# Description: Checks that the testbenches actually catch bugs. Each mutant
#              copies rtl/ and tb/ to a temp folder, injects one deliberate
#              bug into the RTL, and runs the corner-case suite (with the
#              assertion checker) plus the random suite (with the checker).
#              A mutant counts as KILLED if any test or assertion fails.
#              The real rtl/ is never modified.
# Usage (repo root): ./scripts/mutation_check.sh
# ==============================================================================

cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"
WORK="$(mktemp -d)"
RTL="rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v"
KILLED=0; TOTAL=0

mutant() {
    local id="$1" label="$2" file="$3" expr="$4"
    local d="$WORK/$id"
    mkdir -p "$d/sim"; cp -r "$REPO/rtl" "$REPO/tb" "$d/"
    sed -i "$expr" "$d/$file"
    TOTAL=$((TOTAL+1))
    if cmp -s "$REPO/$file" "$d/$file"; then
        printf '%-32s %s\n' "$label" "NOT APPLIED (sed pattern out of date)"; return
    fi
    (
        cd "$d" || exit
        iverilog -g2012 -I rtl -o c.vvp $RTL tb/array_assertions.v tb/tb_array_corner_cases.v && vvp c.vvp
        iverilog -g2012 -I rtl -DTENSORAX_ASSERT -o r.vvp $RTL tb/array_assertions.v tb/tb_systolic_array_random.v && vvp r.vvp
    ) > "$d/out.txt" 2>&1
    local tests asserts
    tests=$(grep -cE "^\[FAIL\]" "$d/out.txt")
    asserts=$(grep -oE "\[assertions\] [0-9]+ checks evaluated, [0-9]+ failures" "$d/out.txt" | grep -oE "[0-9]+ failures" | awk '{s+=$1} END {print s+0}')
    if grep -qE "FAILURE|\[FAIL\]|ASSERT-FAIL" "$d/out.txt"; then
        KILLED=$((KILLED+1))
        printf '%-32s KILLED  ([FAIL] lines: %s, assertion failures: %s)\n' "$label" "$tests" "$asserts"
    else
        printf '%-32s MISSED\n' "$label"
    fi
}

echo "=================================================================="
echo " [TensoraX] Mutation check: are bugs caught?"
echo "=================================================================="
mutant m1 "a/b forwarding swapped"     rtl/pe.v       's/a_out     <= a_in;/a_out     <= b_in;/'
mutant m2 "clr_acc drops first product" rtl/mac_unit.v "s/acc_out <= product;/acc_out <= {ACC_WIDTH{1'b0}};/"
mutant m3 "mac_en ignored (no hold)"   rtl/mac_unit.v 's/end else if (mac_en) begin/end else begin/'
mutant m4 "valid_out stuck high"       rtl/pe.v       "s/valid_out <= valid_in;/valid_out <= 1'b1;/"
mutant m5 "B columns wired reversed"   rtl/systolic_array_3x3.v 's/assign b_link\[0\]\[j\] = b_cols\[j\*DATA_WIDTH +: DATA_WIDTH\];/assign b_link[0][j] = b_cols[(N-1-j)*DATA_WIDTH +: DATA_WIDTH];/'
mutant m6 "reset does not clear a_out" rtl/pe.v       "0,/a_out     <= {DATA_WIDTH{1'b0}};/s//a_out     <= a_out;/"
mutant m7 "accumulator drops sign bit" rtl/mac_unit.v "s/acc_out <= acc_out + product;/acc_out <= {1'b0, acc_out[30:0]} + product;/"
echo "------------------------------------------------------------------"
echo " $KILLED / $TOTAL mutants killed"
rm -rf "$WORK"
[ "$KILLED" -eq "$TOTAL" ]
