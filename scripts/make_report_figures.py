#!/usr/bin/env python3
"""
File: make_report_figures.py
Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
Description: Draws the four figures of the final report (docs/report/figures/*.pdf
             and *.png) from data that already exists in the repository:
               - docs/benchmark/cpu_benchmark_results.json  (measured, run_cpu_benchmark.py)
               - scripts/scaling_analysis.py                (Adnan Rizvi's analytical model)
             Nothing is typed in by hand. Colours are the validated blue / orange /
             aqua slots of the reference categorical palette; every series also has
             its own line style and marker so the figures survive greyscale print.
Usage (repo root): python3 scripts/make_report_figures.py
Requires: matplotlib
"""
import json
import os
import sys

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if os.path.join(ROOT, "scripts") not in sys.path:
    sys.path.insert(0, os.path.join(ROOT, "scripts"))

try:
    from scripts import scaling_analysis as sa
except ImportError:
    import scaling_analysis as sa

OUT = os.path.join(ROOT, "docs", "report", "figures")
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(ROOT, "docs", "benchmark", "cpu_benchmark_results.json"), "r") as fh:
    data = json.load(fh)
sweep = data["sweep_o2_generic_throughput"]
fmax = data["method"]["hardware_clock_basis"]["ecp5_post_route_fmax_mhz"]
F_MEAS = min(fmax.values())          # slowest of the three seeds, MHz
F_TARGET = data["method"]["hardware_clock_basis"]["target_mhz_not_met"]

BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#dcdcd8"

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Times New Roman", "Times", "DejaVu Serif"],
    "font.size": 7.5, "axes.labelsize": 7.5, "xtick.labelsize": 7, "ytick.labelsize": 7,
    "legend.fontsize": 6.8, "axes.edgecolor": MUTED, "axes.linewidth": 0.6,
    "axes.labelcolor": INK, "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.5,
    "axes.spines.top": False, "axes.spines.right": False,
    "figure.dpi": 150, "savefig.dpi": 300, "pdf.fonttype": 42,
})
W, H = 3.4, 2.25
Ns = [r["n"] for r in sweep]


def finish(fig, ax, name, legend_loc="upper left"):
    ax.set_xlim(2, 16)
    ax.set_xticks([2, 4, 6, 8, 10, 12, 14, 16])
    ax.legend(loc=legend_loc, frameon=False, handlelength=2.6)
    fig.tight_layout(pad=0.4)
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(OUT, f"{name}.{ext}"))
    plt.close(fig)


cpu_cyc = [r["cycles_per_matmul_median"] for r in sweep]
hw_cyc = [3 * n - 2 for n in Ns]
fig, ax = plt.subplots(figsize=(W, H))
ax.plot(Ns, cpu_cyc, color=BLUE, lw=1.4, marker="o", ms=3.2, label="CPU, sequential C (measured)")
ax.plot(Ns, hw_cyc, color=ORANGE, lw=1.4, ls="--", marker="s", ms=3.0, label=r"TensoraX, $3N-2$ cycles")
ax.set_yscale("log")
ax.set_xlabel("Matrix size $N$ ($N\\times N$ product)")
ax.set_ylabel("Clock cycles per product")
ax.annotate("$N$=3 (this prototype)", xy=(3, cpu_cyc[1]), xytext=(3.4, 650),
            fontsize=6.8, color=INK, arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.6))
finish(fig, ax, "fig_cycles")

cpu_ns = [r["ns_per_matmul_median"] for r in sweep]
t_meas = [1000.0 * (3 * n - 2) / F_MEAS for n in Ns]
t_targ = [1000.0 * (3 * n - 2) / F_TARGET for n in Ns]
fig, ax = plt.subplots(figsize=(W, H))
ax.plot(Ns, cpu_ns, color=BLUE, lw=1.4, marker="o", ms=3.2, label="CPU, Apple M3 (measured)")
ax.plot(Ns, t_meas, color=ORANGE, lw=1.4, ls="--", marker="s", ms=3.0,
        label=f"TensoraX at {F_MEAS:.1f} MHz (routed ECP5 proxy)")
ax.plot(Ns, t_targ, color=AQUA, lw=1.4, ls=":", marker="^", ms=3.2,
        label=f"TensoraX at {F_TARGET:.0f} MHz (target, not met)")
ax.set_yscale("log")
ax.set_xlabel("Matrix size $N$")
ax.set_ylabel("Time per product (ns)")
ax.text(15.8, 22, "Hardware for $N\\neq3$ is a projection at the\n$N$=3 clock; only $N$=3 was synthesized.",
        fontsize=6.2, color=MUTED, ha="right", va="bottom")
finish(fig, ax, "fig_walltime")

adnan = [sa.compute_dram_traffic(n, 2)[2] for n in Ns]
c32 = [(n + 1) / 2.0 for n in Ns]
fig, ax = plt.subplots(figsize=(W, H))
ax.plot(Ns, adnan, color=BLUE, lw=1.4, marker="o", ms=3.2, label=r"16-bit $C$ write-back: $(2N{+}1)/3$")
ax.plot(Ns, c32, color=ORANGE, lw=1.4, ls="--", marker="s", ms=3.0, label=r"32-bit $C$ write-back: $(N{+}1)/2$")
ax.axhline(1.0, color=MUTED, lw=0.8, ls=":")
ax.text(15.8, 1.25, "ideal-cache CPU: 1.0 (compulsory traffic only)", fontsize=6.2, color=MUTED, ha="right")
ax.set_xlabel("Matrix size $N$")
ax.set_ylabel("Traffic, cache-less CPU / TensoraX")
ax.set_ylim(0, 12.5)
finish(fig, ax, "fig_traffic")

single = [sa.compute_pe_utilization(n) for n in Ns]
pipe = [sa.compute_streaming_efficiency(n, num_batches=100) for n in Ns]
fig, ax = plt.subplots(figsize=(W, H))
ax.plot(Ns, single, color=BLUE, lw=1.4, marker="o", ms=3.2,
        label=r"As built: one tile per $3N{-}2$ cycles, $N/(3N{-}2)$")
ax.plot(Ns, pipe, color=ORANGE, lw=1.4, ls="--", marker="s", ms=3.0,
        label="Bound for 100 tiles, one per $N$ cycles (needs skewed clear)")
ax.set_xlabel("Matrix size $N$")
ax.set_ylabel("PE utilisation $\\eta$ (%)")
ax.set_ylim(0, 108)
finish(fig, ax, "fig_util", legend_loc="center right")

print("wrote", sorted(os.listdir(OUT)))
