#!/usr/bin/env python3
"""
File: scaling_analysis.py
Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
Author: Adnan Rizvi (Lead Microarchitect & Scaling Analysis Lead)
Description: Analytical scaling framework for TensoraX systolic computing mesh.
             Evaluates latency, throughput, and hardware efficiency across N x N array dimensions.
"""

import sys

def compute_systolic_latency(n):
    return 3 * n - 2

def compute_total_macs(n):
    return n ** 3

def compute_peak_throughput(n):
    return n ** 2

def compute_effective_throughput(n):
    total_ops = 2 * (n ** 3)
    latency_cycles = compute_systolic_latency(n)
    return total_ops / latency_cycles

def compute_pe_utilization(n):
    active_mac_cycles = n ** 3
    total_pe_cycles = (n ** 2) * compute_systolic_latency(n)
    return (active_mac_cycles / total_pe_cycles) * 100.0

def run_scaling_sweep(min_n=2, max_n=16):
    print("=========================================================================")
    print(" TensoraX Systolic Array Scaling Sweep: N x N Microarchitecture Bounds  ")
    print(" Lead Microarchitect: Adnan Rizvi                                       ")
    print("=========================================================================")
    print(f"{'N':>3} | {'PEs':>5} | {'Latency (cyc)':>13} | {'Total MACs':>10} | {'Peak (MAC/cyc)':>14} | {'Util (%)':>8}")
    print("-" * 73)
    
    for n in range(min_n, max_n + 1):
        num_pes = n * n
        latency = compute_systolic_latency(n)
        macs = compute_total_macs(n)
        peak = compute_peak_throughput(n)
        util = compute_pe_utilization(n)
        print(f"{n:>3} | {num_pes:>5} | {latency:>13} | {macs:>10} | {peak:>14} | {util:>7.2f}%")
        
    print("=========================================================================")

if __name__ == "__main__":
    run_scaling_sweep()
