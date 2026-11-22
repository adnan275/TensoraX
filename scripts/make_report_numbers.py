#!/usr/bin/env python3
"""
File: make_report_numbers.py
Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
Description: Writes docs/report/numbers.tex, the only place where measured numbers enter
             the final report. Every value is read from a tool output that is committed
             in this repository:
               docs/benchmark/cpu_benchmark_results.json   (scripts/run_cpu_benchmark.py)
               docs/synthesis/yosys_stat_raw.txt           (Yosys, Artix-7 family)
               docs/synthesis/yosys_ecp5_stat.txt          (Yosys, ECP5)
               docs/synthesis/nextpnr_ecp5_seed{1,2,3}.log (nextpnr-ecp5, routed Fmax)
               scripts/scaling_analysis.py                 (analytical model, Adnan Rizvi)
             The report text uses \\macros (each ends in \\xspace) from numbers.tex, so a number in the PDF can
             not drift from its source.
Usage (repo root): python3 scripts/make_report_numbers.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if os.path.join(ROOT, "scripts") not in sys.path:
    sys.path.insert(0, os.path.join(ROOT, "scripts"))

try:
    from scripts import scaling_analysis as sa
except ImportError:
    import scaling_analysis as sa

with open(os.path.join(ROOT, "docs", "benchmark", "cpu_benchmark_results.json"), "r") as fh:
    D = json.load(fh)
res = {(r["variant"], r["kernel"], r["workload"]): r for r in D["results_n3"]}
sweep = D["sweep_o2_generic_throughput"]
fmax = D["method"]["hardware_clock_basis"]["ecp5_post_route_fmax_mhz"]
F_MIN, F_MAX = min(fmax.values()), max(fmax.values())
F_TARGET = D["method"]["hardware_clock_basis"]["target_mhz_not_met"]
HW = D["method"]["hardware_cycles_n3"]
head, best = D["headline"], D["best_case"]

out = []


def mac(name, value):
    out.append(f"\\newcommand{{\\{name}}}{{{value}\\xspace}}")


def f0(x): return f"{x:.0f}"
def f1(x): return f"{x:.1f}"
def f2(x): return f"{x:.2f}"


hw_ns_min = 1000.0 * HW / F_MIN
hw_ns_target = 1000.0 * HW / F_TARGET
ver_ok = all(v["mismatches_generic"] == 0 and v["mismatches_fixed3"] == 0 for v in D["rtl_vector_verification"].values())
v = D["rtl_vector_verification"]["o2"]

mac("CpuName", D["meta"]["cpu"])
cc = re.search(r"(Apple clang version [0-9.]+|clang version [0-9.]+|gcc[^(]*[0-9.]+)", D["meta"]["compiler"])
mac("CompilerName", cc.group(1) if cc else D["meta"]["compiler"])
mac("BenchDate", D["meta"]["date_utc"][:10])
mac("Trials", D["method"]["trials_per_point"])
mac("TimerNs", f0(D["method"]["timer"]["timer_resolution_ns"]))
ghz = [r["est_ghz_median"] for r in D["results_n3"]]
mac("GhzLo", f1(min(ghz))); mac("GhzHi", f1(max(ghz)))
mac("MatmulsPerTrialM", f1(head["matmuls_per_trial"] / 1e6))
mac("VecOutputs", f"{v['outputs_checked_per_kernel']:,}".replace(",", "{,}"))
mac("VecRecords", v["records"])
mac("VecMismatches", v["mismatches_generic"] + v["mismatches_fixed3"])

mac("HeadCyc", f0(head["cycles_per_matmul_median"]))
mac("HeadCycLo", f0(head["cycles_per_matmul_min"])); mac("HeadCycHi", f0(head["cycles_per_matmul_max"]))
mac("HeadNs", f1(head["ns_per_matmul_median"]))
mac("HeadS", f1(head["speedup_cycles_S"]))
mac("HeadMacCyc", f2(27.0 / head["cycles_per_matmul_median"]))
mac("BestCyc", f0(best["cycles_per_matmul_median"]))
mac("BestNs", f1(best["ns_per_matmul_median"]))
mac("BestS", f1(best["speedup_cycles_S"]))
mac("BestMacCyc", f2(27.0 / best["cycles_per_matmul_median"]))
o0 = res[("o0", "generic", "throughput")]
mac("OzeroCyc", f0(o0["cycles_per_matmul_median"])); mac("OzeroS", f1(o0["speedup_cycles_S"]))
mac("OzeroNs", f0(o0["ns_per_matmul_median"]))
hl = res[("o2", "generic", "latency")]; bl = res[("o2", "fixed3", "latency")]
mac("HeadLatCyc", f0(hl["cycles_per_matmul_median"])); mac("HeadLatS", f1(hl["speedup_cycles_S"]))
mac("BestLatCyc", f0(bl["cycles_per_matmul_median"])); mac("BestLatS", f1(bl["speedup_cycles_S"]))
s_vals = [r["speedup_cycles_S"] for r in D["results_n3"]]
mac("SLo", f1(min(s_vals))); mac("SHi", f1(max(s_vals)))
mac("HwMacCyc", f2(27.0 / HW))

mac("FmaxLo", f2(F_MIN)); mac("FmaxHi", f2(F_MAX))
mac("FmaxLoShort", f1(F_MIN))
mac("FTarget", f0(F_TARGET))
mac("HwNsMeasured", f1(hw_ns_min)); mac("HwNsTarget", f1(hw_ns_target))
mac("CpuFasterHead", f1(hw_ns_min / head["ns_per_matmul_median"]))
mac("CpuFasterBest", f1(hw_ns_min / best["ns_per_matmul_median"]))
mac("CpuFasterOzero", f1(hw_ns_min / o0["ns_per_matmul_median"]))
mac("CpuFasterHeadTarget", f1(hw_ns_target / head["ns_per_matmul_median"]))
mac("CpuFasterBestTarget", f1(hw_ns_target / best["ns_per_matmul_median"]))
mac("GflopsCpuHead", f1(54.0 / head["ns_per_matmul_median"]))
mac("GflopsCpuBest", f1(54.0 / best["ns_per_matmul_median"]))
mac("GflopsHwMeasured", f2(54.0 / hw_ns_min))
mac("GflopsHwTarget", f2(54.0 / hw_ns_target))
mac("ClockRatio", f0(1000.0 * head["est_ghz_median"] / F_MIN))


def crossover(f_mhz):
    for r in sweep:
        n = r["n"]
        if r["ns_per_matmul_median"] >= 1000.0 * (3 * n - 2) / f_mhz:
            return n
    return None


mac("CrossN", crossover(F_MIN)); mac("CrossNTarget", crossover(F_TARGET))
s16 = sweep[-1]
mac("SixteenCyc", f0(s16["cycles_per_matmul_median"])); mac("SixteenS", f1(s16["speedup_cycles_S"]))
mac("SixteenHw", s16["hw_cycles"])
mac("SweepThreeCyc", f0(sweep[1]["cycles_per_matmul_median"]))
mac("SweepThreeS", f1(sweep[1]["speedup_cycles_S"]))

mac("EtaThree", f1(sa.compute_pe_utilization(3)))
mac("EtaLimit", f1(100.0 / 3))
mac("EtaBatchHundred", f1(sa.compute_streaming_efficiency(3, 100)))
mac("EtaBatchTen", f1(sa.compute_streaming_efficiency(3, 10)))
t3 = sa.compute_dram_traffic(3, 2)
t16 = sa.compute_dram_traffic(16, 2)
mac("TrafficRatioThree", f2(t3[2])); mac("TrafficRatioSixteen", f2(t16[2]))
mac("TrafficRatioThreeBit", f1((3 + 1) / 2)); mac("TrafficRatioSixteenBit", f1((16 + 1) / 2))

def parse_stat(path):
    counts, inside = {}, False
    for line in open(path, errors="replace"):
        if re.search(r"\bcells\b", line) and re.match(r"\s+\d+\s+cells", line):
            inside = True
            continue
        if inside:
            m = re.match(r"\s+(\d+)\s+(\S+)\s*$", line)
            if m:
                counts[m.group(2)] = int(m.group(1))
            elif line.strip() == "" or line.startswith("end"):
                if counts:
                    break
    return counts


x7 = parse_stat(os.path.join(ROOT, "docs", "synthesis", "yosys_stat_raw.txt"))
ec = parse_stat(os.path.join(ROOT, "docs", "synthesis", "yosys_ecp5_stat.txt"))
luts = x7["LUT2"] + x7["LUT4"] + x7["LUT5"]
mac("XDsp", x7["DSP48E1"]); mac("XLut", luts); mac("XCarry", x7["CARRY4"]); mac("XFF", x7["FDCE"])
mac("XIbuf", x7["IBUF"]); mac("XObuf", x7["OBUF"]); mac("XBufg", x7["BUFG"])
mac("XLutTwo", x7["LUT2"]); mac("XLutFour", x7["LUT4"]); mac("XLutFive", x7["LUT5"])
mac("EMult", ec["MULT18X18D"]); mac("ECarry", ec["CCU2C"]); mac("ELut", ec["LUT4"]); mac("EFF", ec["TRELLIS_FF"])
mac("FmaxSeedOne", f2(fmax["1"])); mac("FmaxSeedTwo", f2(fmax["2"])); mac("FmaxSeedThree", f2(fmax["3"]))

rows = []
for variant, vl in (("o0", "-O0"), ("o2", "-O2"), ("o3", "-O3")):
    for kernel, kl in (("generic", "generic"), ("fixed3", "fixed-3")):
        t, l = res[(variant, kernel, "throughput")], res[(variant, kernel, "latency")]
        tag = r" \textbf{(headline)}" if (variant, kernel) == ("o2", "generic") else ""
        rows.append(f"{vl} {kl}{tag} & {t['cycles_per_matmul_median']:.0f} & {t['speedup_cycles_S']:.1f} & "
                    f"{l['cycles_per_matmul_median']:.0f} & {l['speedup_cycles_S']:.1f} \\\\")
out.append("\\newcommand{\\TableCpuRows}{" + "\n".join(rows) + "}")

rows = []
for n in (2, 3, 4, 8, 16):
    cpu_b, sys_b, ratio = sa.compute_dram_traffic(n, 2)
    rows.append(f"{n} & {cpu_b:,} & {sys_b:,} & {ratio:.2f} & {(n + 1) / 2:.2f} & {n / 3:.2f} \\\\".replace(",", "{,}"))
out.append("\\newcommand{\\TableTrafficRows}{" + "\n".join(rows) + "}")

path = os.path.join(ROOT, "docs", "report", "numbers.tex")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as fh:
    fh.write("% Generated by scripts/make_report_numbers.py - do not edit by hand.\n")
    fh.write("\n".join(out) + "\n")
print(f"wrote {os.path.relpath(path, ROOT)} ({len(out)} macros); vector check ok={ver_ok}")
print(f"headline {head['cycles_per_matmul_median']:.1f} cyc S={head['speedup_cycles_S']:.2f}; best {best['cycles_per_matmul_median']:.1f} cyc S={best['speedup_cycles_S']:.2f}; "
      f"crossover N={crossover(F_MIN)} @ {F_MIN} MHz, N={crossover(F_TARGET)} @ {F_TARGET} MHz; synth {x7}")
