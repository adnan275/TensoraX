#!/bin/sh
# Core-only timing on Lattice ECP5 (open-source flow), 3 placer seeds.
# Needs: yosys 0.71 and nextpnr-ecp5 0.11.1 (YoWASP builds: set YOSYS=yowasp-yosys NEXTPNR=yowasp-nextpnr-ecp5).
# Run in a folder containing mac_unit.v pe.v systolic_array_3x3.v tensora_pkg.vh synth_ecp5.ys
# (check them against the SHA-256 values in MANIFEST.txt first).
# nextpnr exits non-zero when the 200 MHz target is not met. That is the expected result here,
# so the failure is tolerated explicitly with "|| echo" and the Fmax is read from each log.
YOSYS=${YOSYS:-yosys}
NEXTPNR=${NEXTPNR:-nextpnr-ecp5}
sha256sum -c MANIFEST.txt 2>/dev/null | grep -v "^repo\|^Tools" 
$YOSYS -s synth_ecp5.ys || exit 1
for sd in 1 2 3; do
  $NEXTPNR --85k --speed 6 --package CABGA381 --json core_ecp5.json \
    --out-of-context --freq 200 --seed $sd --log nextpnr_ecp5_seed$sd.log \
    || echo "seed $sd: target not met (expected), see log"
  grep "Max frequency" nextpnr_ecp5_seed$sd.log | tail -1
done
