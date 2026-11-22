# TensoraX Demonstration Runbook — Aditya Pal

## Pre-run Checklist
Run these from the repository root on the machine that has Icarus Verilog and GTKWave installed.

```bash
chmod +x ./scripts/run_all_tests.sh
./scripts/run_all_tests.sh
```

Confirm the regression completes and reports the expected PASS results. The repository's verification document records 6/6 regression items, 13/13 corner cases, 600 randomized operations, 5,400 output checks, and 422,316 assertion checks with zero failures. Treat those as repository-recorded simulation results, not FPGA measurements.

## GTKWave: main wavefront view

```bash
gtkwave sim/tb_systolic_array_3x3.vcd docs/waveforms/tensorax_array.gtkw --script=docs/waveforms/tensorax_markers.tcl
```

Walk through signals in this order:
1. `rst_n`: active-low reset; show the reset interval and release.
2. `valid_in`: identifies meaningful input cycles.
3. `a_rows` and `b_cols`: inputs arrive with row/column skew.
4. PE forwarding: A propagates east and B propagates south.
5. Diagonal wavefront: matching operands reach progressively later PEs.
6. `c_flat`: row-major output bus; point out the completed matrix result.
7. Latency: for the 3×3 prototype, the documented completion bound is 7 cycles.

## GTKWave: reset/corner-case view

```bash
gtkwave sim/tb_array_corner_cases.vcd docs/waveforms/tensorax_reset.gtkw --script=docs/waveforms/tensorax_reset_markers.tcl
```

Show the mid-operation reset, cleared state, and recovery on a subsequent operation. Do not claim formal verification: the repository uses explicit clocked assertion checks in simulation.

## Suggested 5–7 minute speaking order
- 0:00–0:45 — problem: data movement in repeated matrix multiplication.
- 0:45–1:45 — 3×3 systolic mesh, PE datapath, output-stationary accumulation.
- 1:45–2:45 — skewed inputs and diagonal wavefront; explain 7-cycle 3×3 result.
- 2:45–3:45 — run regression and show GTKWave evidence.
- 3:45–5:00 — show utilization and DRAM traffic plots; explain equations and assumptions.
- 5:00–6:00 — Roofline model and what must still be measured.
- 6:00–7:00 — limitations, conclusions, questions.

## Architecture and Design FAQs
**Why skew inputs?** To align the corresponding A row and B column values at each PE despite their different spatial positions.

**Why output-stationary?** Each PE retains its partial sum locally while operands move through the mesh, reducing partial-sum movement.

**Why does utilization fall toward 33.33% for one isolated tile?** The array incurs fill and drain cycles; the single-tile efficiency is `N/(3N−2)`.

**Does 2.33× traffic reduction mean 2.33× faster?** No. It is a byte-count ratio from an idealized traffic model, not an execution-time speedup.

**Is the design proven on FPGA?** The repository documents synthesizable RTL and simulation evidence, but does not report synthesis area, timing closure, or measured FPGA execution time.

## CPU/FPGA speedup: data still required
Do not state a numeric speedup until a controlled benchmark is run. Use the same matrix sizes, precision, input data, and correctness check. Record:
- CPU model, core/thread count, compiler and optimized library (e.g. BLAS), warm-up and repetitions.
- FPGA board, synthesis/implementation toolchain, achieved clock, and whether transfer time is included.
- Median CPU time and median FPGA time for the same workload boundary.

Then calculate:

`Speedup = CPU execution time / TensoraX execution time`

Keep kernel-only and end-to-end measurements separate.
