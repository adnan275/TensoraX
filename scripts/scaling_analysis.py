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

def compute_dram_traffic(n, bytes_per_elem=2):
    naive_cpu_bytes = (2 * (n ** 3) + (n ** 2)) * bytes_per_elem
    systolic_bytes = (2 * (n ** 2) + (n ** 2)) * bytes_per_elem
    traffic_reduction_ratio = naive_cpu_bytes / systolic_bytes
    return naive_cpu_bytes, systolic_bytes, traffic_reduction_ratio

def compute_streaming_efficiency(n, num_batches=10):
    total_ops = num_batches * (n ** 3)
    first_tile_latency = compute_systolic_latency(n)
    steady_state_latency = first_tile_latency + (num_batches - 1) * n
    total_pe_cycles = (n ** 2) * steady_state_latency
    return (total_ops / total_pe_cycles) * 100.0

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

def run_bandwidth_sweep(min_n=2, max_n=8):
    print("\n=========================================================================")
    print(" External Memory Bandwidth & Traffic Analysis (16-bit Operands)         ")
    print("=========================================================================")
    print(f"{'N':>3} | {'CPU Traffic (B)':>15} | {'Systolic Traffic (B)':>20} | {'Reduction Ratio':>16}")
    print("-" * 65)
    for n in range(min_n, max_n + 1):
        cpu_b, sys_b, ratio = compute_dram_traffic(n, bytes_per_elem=2)
        print(f"{n:>3} | {cpu_b:>15,} | {sys_b:>20,} | {ratio:>15.2f}x")
    print("=========================================================================")

def run_streaming_sweep(n=3):
    print(f"\nPipelined Batch Streaming Efficiency (Grid Size N={n}):")
    print(f"{'Batches':>7} | {'Pipelined Cycles':>16} | {'Effective Utilization':>22}")
    print("-" * 50)
    for b in [1, 5, 10, 50, 100]:
        eff = compute_streaming_efficiency(n, num_batches=b)
        cyc = compute_systolic_latency(n) + (b - 1) * n
        print(f"{b:>7} | {cyc:>16} | {eff:>21.2f}%")

if __name__ == "__main__":
    run_scaling_sweep()
    run_bandwidth_sweep()
    run_streaming_sweep(3)
