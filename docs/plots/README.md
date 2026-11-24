# TensoraX visualization assets — Aditya Pal

All plots are generated from the equations in `scripts/scaling_analysis.py`,
`scripts/roofline_model.py`, and `docs/SCALING_ANALYSIS.md` in the repository.

## Files
- `dram_traffic_cpu_vs_tensorax.png`: analytical bytes per GEMM tile, 16-bit elements.
- `dram_traffic_reduction_ratio.png`: analytical ratio `(2N + 1) / 3`.
- `utilization_efficiency_n2_to_n16.png`: single-tile PE utilization `N / (3N - 2)`.
- `roofline_assumed_platform.png`: illustrative roofline using 200 MHz and 12.8 GB/s assumptions.
- `scaling_plot_data.csv`: data behind the N=2..16 plots.

## Important interpretation
The CPU traffic model assumes a naive CPU implementation with no cache blocking
or reuse. It is not a measurement of a modern optimized CPU. The TensoraX traffic
model counts A, B, and C tile traffic under the documented spatial-reuse model.
These are analytical external-memory traffic estimates, not physical DRAM bus
measurements.

The single-tile utilization is `N/(3N-2)`. This is not the same as the
multi-tile streaming utilization, which amortizes fill/drain overhead.

CPU baseline benchmarking and cycle speedup measurements are reported separately in `docs/benchmark/cpu_benchmark_results.json` and the final IEEE report.

## How to reproduce in the project
From the repository root:
```bash
python3 scripts/scaling_analysis.py
python3 scripts/roofline_model.py
```
The scripts print analytical tables. This deliverable's plotting script/data
can be used to regenerate the figures; no synthesis result is implied.

## Required benchmark to claim speedup
1. Fix matrix dimensions, precision, input values, and output validation.
2. Measure a CPU baseline with an optimized implementation (e.g. BLAS) and
   document CPU model, thread count, compiler/library and warm-up policy.
3. Measure TensoraX on actual FPGA hardware after synthesis/implementation,
   reporting clock, board, toolchain, transfer overhead and kernel-only time.
4. Repeat enough runs; report median and variability.
5. Compute speedup = CPU time / TensoraX time using the same workload boundary.
