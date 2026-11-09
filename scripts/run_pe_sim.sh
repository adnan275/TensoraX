#!/bin/bash
# ==============================================================================
# Script: run_pe_sim.sh
# Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
# Author: Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)
# Description: Compiles and runs the Processing Element unit testbench using
#              Icarus Verilog and generates VCD waveforms.
# ==============================================================================

set -e

mkdir -p sim

echo "=========================================================="
echo " [TensoraX] Compiling Processing Element (PE) with Icarus "
echo "=========================================================="

iverilog -Wall -I rtl -o sim/tb_pe.vvp rtl/mac_unit.v rtl/pe.v tb/tb_pe.v

echo "Compilation successful. Executing simulation..."
vvp sim/tb_pe.vvp

echo "=========================================================="
echo " Simulation Complete. Waveform generated at: sim/tb_pe.vcd"
echo " To inspect with GTKWave: gtkwave sim/tb_pe.vcd"
echo "=========================================================="
