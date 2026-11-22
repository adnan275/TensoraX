#!/usr/bin/env python3
"""
File: run_cpu_benchmark.py
Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
Author: Praanshu Ranjan (Benchmarking & Final IEEE Report Lead)
Description: Builds and runs the sequential CPU baseline (scripts/cpu_baseline.c),
             checks that it computes exactly what the RTL computes, and compares
             it with TensoraX's 7-cycle 3x3 latency.

What it does
  1. Compiles cpu_baseline.c at -O0, -O2 and -O3 (native) into a temporary folder.
  2. Verifies both kernels against the RTL regression vectors
     (tb/vectors/array_rand_vectors.hex, 600 operations, 5,400 outputs).
  3. Times 3x3 multiplies (throughput and dependent-latency workloads) and an
     N = 2..16 sweep, 9 trials each, reporting the median and the spread.
  4. Reads the post-route Fmax of the committed nextpnr logs and reports
        S      = CPU cycles / 7                      (cycle-count speedup)
        S_time = CPU ns per multiply / (7 / f_hw)    (wall-clock speedup)
  5. Writes docs/benchmark/cpu_benchmark_results.json and cpu_sweep.csv.

The headline configuration was fixed before any measurement was taken:
  generic triple loop (N read at run time), -O2, independent multiplies.
The fastest configuration found is reported next to it as the best case.

Usage (repo root):  python3 scripts/run_cpu_benchmark.py [--quick] [--ghz GHZ]
Requires: a C compiler named by $CC (default cc), python3.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "scripts", "cpu_baseline.c")
VECTORS = os.path.join(ROOT, "tb", "vectors", "array_rand_vectors.hex")
SYNTH_DIR = os.path.join(ROOT, "docs", "synthesis")
OUT_DIR = os.path.join(ROOT, "docs", "benchmark")

HW_CYCLES_N3 = 7                      # 3N - 2 for N = 3 (verified in RTL simulation)
HEADLINE = ("o2", "generic", "throughput")
TARGET_MHZ = 200.0                    # TARGET_FREQ_MHZ in rtl/tensora_pkg.vh (not met on ECP5)


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


def compiler_flags(cc):
    ver = run([cc, "--version"]).splitlines()[0]
    machine = platform.machine().lower()
    native = ["-mcpu=native"] if machine in ("arm64", "aarch64") else ["-march=native"]
    return ver, {"o0": ["-O0"], "o2": ["-O2"], "o3": ["-O3"] + native}


def sh_out(cmd):
    try:
        return run(cmd).strip()
    except Exception:
        return ""


def machine_info(cc_version):
    cpu = sh_out(["sysctl", "-n", "machdep.cpu.brand_string"])
    if not cpu and os.path.exists("/proc/cpuinfo"):
        for line in open("/proc/cpuinfo"):
            if line.startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    rtl = hashlib.sha256()
    for f in ("mac_unit.v", "pe.v", "systolic_array_3x3.v"):
        rtl.update(open(os.path.join(ROOT, "rtl", f), "rb").read())
    return {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cpu": cpu or platform.processor(),
        "os": f"{platform.system()} {platform.release()}",
        "machine": platform.machine(),
        "compiler": cc_version,
        "repo_commit": sh_out(["git", "-C", ROOT, "rev-parse", "HEAD"]),
        "rtl_sha256_combined": rtl.hexdigest(),
    }


def post_route_fmax():
    """Last 'Max frequency for clock' line of each nextpnr log = value after routing."""
    vals = {}
    for seed in (1, 2, 3):
        path = os.path.join(SYNTH_DIR, f"nextpnr_ecp5_seed{seed}.log")
        last = None
        for line in open(path, errors="replace"):
            m = re.search(r"Max frequency for clock 'clk': ([0-9.]+) MHz", line)
            if m:
                last = float(m.group(1))
        if last is None:
            sys.exit(f"no Fmax line found in {path}")
        vals[seed] = last
    return vals


def bench(binary, kernel, workload, n, trials, extra):
    out = run([binary, "--kernel", kernel, "--workload", workload, "--n", str(n),
               "--trials", str(trials)] + extra)
    return json.loads(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="3 trials per point (smoke test)")
    ap.add_argument("--trials", type=int, default=9)
    ap.add_argument("--ghz", type=float, default=0.0, help="use this clock instead of the estimate")
    ap.add_argument("--out-dir", default=OUT_DIR)
    args = ap.parse_args()
    trials = 3 if args.quick else args.trials
    extra = ["--ghz", str(args.ghz)] if args.ghz > 0 else []

    cc = os.environ.get("CC", "cc")
    cc_version, variants = compiler_flags(cc)
    meta = machine_info(cc_version)
    print(f"CPU: {meta['cpu']}   compiler: {cc_version}")

    fmax = post_route_fmax()
    f_min, f_mean = min(fmax.values()), statistics.mean(fmax.values())
    print(f"Hardware reference: 7 cycles; post-route ECP5 Fmax {fmax} MHz (proxy, see docs/SYNTHESIS_REPORT.md)")

    results, verify, sweep = [], {}, []
    with tempfile.TemporaryDirectory() as tmp:
        bins = {}
        for name, flags in variants.items():
            bins[name] = os.path.join(tmp, f"cpu_baseline_{name}")
            run([cc] + flags + ["-Wall", "-o", bins[name], SRC])
            v = json.loads(run([bins[name], "--verify", VECTORS]))["verify"]
            v["vectors"] = os.path.relpath(VECTORS, ROOT)
            verify[name] = v
            if v["mismatches_generic"] or v["mismatches_fixed3"]:
                sys.exit(f"[FAIL] {name}: CPU kernels disagree with RTL vectors: {v}")
        print(f"[PASS] both kernels match the RTL vectors at -O0/-O2/-O3: "
              f"{verify['o2']['outputs_checked_per_kernel']} outputs, 0 mismatches")
        info = json.loads(run([bins["o2"], "--info"]))["info"]

        for name in variants:
            for kernel in ("generic", "fixed3"):
                for workload in ("throughput", "latency"):
                    r = bench(bins[name], kernel, workload, 3, trials, extra)
                    r["variant"], r["flags"] = name, " ".join(variants[name])
                    results.append(r)
        for n in range(2, 17):
            r = bench(bins["o2"], "generic", "throughput", n, trials, extra)
            r["variant"] = "o2"
            sweep.append(r)

    def enrich(r):
        r["hw_cycles"] = HW_CYCLES_N3
        c = r["cycles_per_matmul_median"]
        r["speedup_cycles_S"] = c / HW_CYCLES_N3 if c > 0 else None
        r["speedup_cycles_S_range"] = ([r["cycles_per_matmul_min"] / HW_CYCLES_N3,
                                        r["cycles_per_matmul_max"] / HW_CYCLES_N3] if c > 0 else None)
        ns = r["ns_per_matmul_median"]
        r["hw_ns_at_fmax_min"] = 1000.0 * HW_CYCLES_N3 / f_min
        r["speedup_time_at_fmax_min"] = ns / r["hw_ns_at_fmax_min"]
        r["speedup_time_at_200MHz_target"] = ns / (1000.0 * HW_CYCLES_N3 / TARGET_MHZ)
        r["macs_per_cycle"] = 27.0 / c if c > 0 else None

    for r in results:
        enrich(r)
    for r in sweep:
        n = r["n"]
        r["hw_cycles"] = 3 * n - 2
        r["speedup_cycles_S"] = r["cycles_per_matmul_median"] / (3 * n - 2) if r["cycles_per_matmul_median"] > 0 else None

    headline = next(r for r in results if (r["variant"], r["kernel"], r["workload"]) == HEADLINE)
    best = min((r for r in results if r["cycles_per_matmul_median"] > 0),
               key=lambda r: r["cycles_per_matmul_median"])
    worst = max((r for r in results if r["workload"] == "throughput"),
                key=lambda r: r["cycles_per_matmul_median"])

    print()
    hdr = f"{'variant':>7} {'kernel':>8} {'workload':>10} | {'ns/mm':>7} {'GHz':>5} {'cycles':>8} {'[min..max]':>14} | {'S=cyc/7':>8} | {'t_CPU/t_HW@%.1fMHz' % f_min:>20}"
    print(hdr)
    print("-" * len(hdr))
    for r in results:
        tag = " <- headline" if r is headline else (" <- best case" if r is best else "")
        rng = f"[{r['cycles_per_matmul_min']:.0f}..{r['cycles_per_matmul_max']:.0f}]"
        print(f"{r['variant']:>7} {r['kernel']:>8} {r['workload']:>10} | {r['ns_per_matmul_median']:7.2f} "
              f"{r['est_ghz_median']:5.2f} {r['cycles_per_matmul_median']:8.1f} {rng:>14} | "
              f"{r['speedup_cycles_S']:8.2f} | {r['speedup_time_at_fmax_min']:20.3f}{tag}")
    print("\nS_time < 1 means the CPU finishes one 3x3 multiply sooner than the FPGA prototype at that Fmax.")

    print(f"\n{'N':>3} | {'CPU cycles (O2 generic)':>24} | {'HW cycles 3N-2':>14} | {'S':>7}")
    for r in sweep:
        print(f"{r['n']:>3} | {r['cycles_per_matmul_median']:24.1f} | {r['hw_cycles']:14d} | {r['speedup_cycles_S']:7.2f}")

    os.makedirs(args.out_dir, exist_ok=True)
    doc = {
        "meta": meta,
        "method": {
            "kernel": "C = A x B, int16 operands, 32-bit wrapping accumulate (same arithmetic as the RTL)",
            "cycles": ("estimated: median ns per multiply x clock estimate (chain of dependent adds, measured "
                       "before and after every trial); no user-space cycle counter is available"
                       if not args.ghz else f"ns per multiply x fixed {args.ghz} GHz (--ghz)"),
            "trials_per_point": trials,
            "timer": info,
            "headline_configuration": {"variant": HEADLINE[0], "kernel": HEADLINE[1], "workload": HEADLINE[2]},
            "hardware_cycles_n3": HW_CYCLES_N3,
            "hardware_clock_basis": {
                "ecp5_post_route_fmax_mhz": fmax,
                "note": "Place-and-route proxy on Lattice ECP5 (docs/SYNTHESIS_REPORT.md); Artix-7 timing was not measured.",
                "target_mhz_not_met": TARGET_MHZ,
            },
        },
        "rtl_vector_verification": verify,
        "results_n3": results,
        "headline": headline,
        "best_case": best,
        "slowest_throughput_case": worst,
        "sweep_o2_generic_throughput": sweep,
    }
    with open(os.path.join(args.out_dir, "cpu_benchmark_results.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    with open(os.path.join(args.out_dir, "cpu_sweep.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["N", "cpu_cycles_median", "cpu_cycles_min", "cpu_cycles_max", "cpu_ns_median",
                    "hw_cycles_3N_minus_2", "speedup_cycles_S"])
        for r in sweep:
            w.writerow([r["n"], f"{r['cycles_per_matmul_median']:.3f}", f"{r['cycles_per_matmul_min']:.3f}",
                        f"{r['cycles_per_matmul_max']:.3f}", f"{r['ns_per_matmul_median']:.4f}",
                        r["hw_cycles"], f"{r['speedup_cycles_S']:.3f}"])
    print(f"\nwrote {os.path.relpath(args.out_dir, ROOT)}/cpu_benchmark_results.json and cpu_sweep.csv")


if __name__ == "__main__":
    main()
