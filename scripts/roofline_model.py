#!/usr/bin/env python3
"""
File: roofline_model.py
Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
Author: Adnan Rizvi (Lead Microarchitect & Scaling Analysis Lead)
Description: Analytical Roofline model for TensoraX hardware architecture.
             Calculates arithmetic intensity, attainable throughput, and
             bandwidth crossover thresholds.
"""

import sys

def calculate_arithmetic_intensity(n, bytes_per_element=2):
    total_flops = 2 * (n ** 3)
    memory_traffic_bytes = 3 * (n ** 2) * bytes_per_element
    return total_flops / memory_traffic_bytes

def calculate_attainable_gflops(n, clock_mhz=200, bandwidth_gbps=12.8):
    arithmetic_intensity = calculate_arithmetic_intensity(n)
    peak_gflops = (2 * (n ** 2) * clock_mhz) / 1000.0
    memory_bound_gflops = bandwidth_gbps * arithmetic_intensity
    attainable_gflops = min(peak_gflops, memory_bound_gflops)
    regime = "Compute-Bound" if attainable_gflops == peak_gflops else "Memory-Bound"
    return {
        "intensity": arithmetic_intensity,
        "peak_gflops": peak_gflops,
        "memory_bound_gflops": memory_bound_gflops,
        "attainable_gflops": attainable_gflops,
        "regime": regime
    }

def calculate_crossover_bandwidth(n, clock_mhz=200):
    peak_gflops = (2 * (n ** 2) * clock_mhz) / 1000.0
    intensity = calculate_arithmetic_intensity(n)
    return peak_gflops / intensity

def run_roofline_evaluation():
    print("=========================================================================")
    print(" TensoraX Architectural Roofline Model: Operational Intensity Analysis  ")
    print(" Lead Microarchitect: Adnan Rizvi                                       ")
    print("=========================================================================")
    print(f"Target Clock Frequency: 200 MHz | Memory Bandwidth: 12.8 GB/s (DDR4/LPDDR)")
    print("-" * 73)
    print(f"{'N':>3} | {'Intensity (FLOP/B)':>18} | {'Peak (GFLOPs)':>14} | {'Attainable (GFLOPs)':>20} | {'Regime':>14}")
    print("-" * 73)

    for n in [2, 3, 4, 8, 16, 32, 64]:
        res = calculate_attainable_gflops(n, clock_mhz=200, bandwidth_gbps=12.8)
        print(f"{n:>3} | {res['intensity']:>18.2f} | {res['peak_gflops']:>14.2f} | {res['attainable_gflops']:>20.2f} | {res['regime']:>14}")

    print("=========================================================================")
    print("\nMinimum Memory Bandwidth Required to Avoid Stall (at 200 MHz):")
    for n in [2, 3, 4, 8]:
        req_bw = calculate_crossover_bandwidth(n, clock_mhz=200)
        print(f"  Grid Size {n}x{n}: {req_bw:6.2f} GB/s bandwidth threshold")
    print("=========================================================================")

if __name__ == "__main__":
    run_roofline_evaluation()
