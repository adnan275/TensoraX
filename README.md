# TensoraX: 2D Systolic Array Matrix Multiplication Accelerator

[![Hardware Description](https://img.shields.io/badge/Language-Verilog%20HDL-blue.svg)](rtl/)
[![Verification](https://img.shields.io/badge/Verification-Simulation%20Tested-brightgreen.svg)](tb/)
[![Course](https://img.shields.io/badge/Course-Modern%20Computer%20Architecture-orange.svg)]()
[![Target](https://img.shields.io/badge/Target-AI%20Hardware%20Acceleration-purple.svg)]()

**TensoraX** is a cycle-accurate, synthesizable 2D mesh systolic array accelerator designed to accelerate General Matrix Multiply (GEMM) computations in Deep Learning and Edge AI workloads.

Inspired by industry AI hardware architectures such as the **Google TPU (Tensor Processing Unit)** and **NVIDIA Tensor Cores**, TensoraX eliminates the Von-Neumann memory-wall bottleneck by rhythmically streaming matrix activations and weights spatially through an interconnected grid of dedicated Processing Elements (PEs).

---

## 👥 Engineering Team & Specializations

| Member | Engineering Role | Core Contributions |
| :--- | :--- | :--- |
| **Adnan Rizvi** | **Lead Microarchitect & Core PE Datapath Engineer** | Designed 16-bit MAC arithmetic engine (`mac_unit.v`), spatial Processing Element (`pe.v`), datapath specifications, Python golden reference model, and PE verification suite. |
| **Praanshu** | **Systolic Interconnect & 2D Grid Architect** | 2D mesh topology routing (`systolic_array_3x3.v`), horizontal activation and vertical weight interconnects, global reset & clear synchronization. |
| **Anurag** | **System Verification & Testbench Lead** | Top-level self-checking verification testbench (`tb_systolic_array_3x3.v`), assertion checkers, corner-case testing, and GTKWave timing waveform validation. |
| **Aditya Pal** | **Hardware Visualization & Prototype Demonstration Lead** | Architectural schematic diagrams, systolic wavefront propagation charts, and 5-minute Prototype Video demonstration production. |
| **Aviral** | **Toolflow, Automation & Technical Documentation Lead** | Automated compilation tooling (`Makefile`, shell runners), IEEE Project Report formulation, and GitHub repository organization. |

---

## 🏛️ System Architecture

### 1. 2D Orthogonal Mesh Grid ($3 \times 3$ Topology)
Matrix $A$ enters horizontally from the West boundary; Matrix $B$ enters vertically from the North boundary. Both input streams are skewed by 1 cycle per row/column to synchronize wavefront arrival times.

```
                  B_col0           B_col1           B_col2
                    |                |                |
                    v                v                v
A_row0 ------> [ PE(0,0) ] ------> [ PE(0,1) ] ------> [ PE(0,2) ]
                    |                |                |
                    v                v                v
A_row1 ------> [ PE(1,0) ] ------> [ PE(1,1) ] ------> [ PE(1,2) ]
                    |                |                |
                    v                v                v
A_row2 ------> [ PE(2,0) ] ------> [ PE(2,1) ] ------> [ PE(2,2) ]
                    |                |                |
                    v                v                v
```

### 2. Processing Element (PE) Microarchitecture
Each PE combines a low-latency signed multiplier, a 32-bit accumulator, and spatial forwarding registers:
$$\text{Acc}_{i,j}[t] = \text{Acc}_{i,j}[t-1] + (A_{\text{in}}[t] \times B_{\text{in}}[t])$$
$$A_{\text{out}}[t+1] = A_{\text{in}}[t], \quad B_{\text{out}}[t+1] = B_{\text{in}}[t]$$

```
                           B_in [15:0] (North)
                                |
                                v
                     +--------------------+
                     |  B_reg (16-bit FF) |
                     +---------+----------+
                               |
                               +-------------------+
                               |                   |
                               v                   v
A_in [15:0] ----------> [ A_reg (16-bit) ]      [ Multiplier ] (16x16 Signed)
(West)                         |                   | (32-bit Product)
                               v                   v
                          A_out [15:0]         [ 32-bit Adder ] <-----+
                          (East)                   |                  |
                                                   v                  |
                                            [ Acc Register ] ---------+
                                                   |
                                                   v
                                              C_out [31:0]
                                                   |
                                                   v
                                              B_out [15:0] (South)
```

---

## ⚡ Hardware Specifications

| Parameter | Specification | Details |
| :--- | :--- | :--- |
| **Array Dimensions** | $3 \times 3$ Grid (9 PEs) | Modular and scalable to $N \times N$ |
| **Input Precision** | 16-bit Signed Fixed-Point | Two's complement (`signed [15:0]`) |
| **Accumulator Width** | 32-bit Signed | Overflow-guarded (`signed [31:0]`) |
| **Dataflow Policy** | Output-Stationary (OS) | Partial sums stay stationary in PEs |
| **GEMM Latency** | **7 Clock Cycles** ($3N - 2$) | Full $3 \times 3$ matrix multiplication |
| **Throughput** | 9 MACs / cycle at peak saturation | High compute density |

---

## 🚀 Quickstart & Simulation Guide

### Prerequisites
- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)
- [GTKWave](https://gtkwave.sourceforge.net/) (for waveform inspection)
- Python 3.8+ (for golden reference verification)

### 1. Clone the Repository
```bash
git clone https://github.com/adnan275/TensoraX.git
cd TensoraX
```

### 2. Run Processing Element (PE) Verification
```bash
./scripts/run_pe_sim.sh
```
Or execute the Python golden model:
```bash
python3 scripts/pe_golden_model.py
```

### 3. Run the $3 \times 3$ Systolic Array Simulations
Requires Icarus Verilog. Run from the repository root:
```bash
mkdir -p sim
# Directed testbench
iverilog -g2012 -I rtl -o sim/array.vvp rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v tb/tb_systolic_array_3x3.v && vvp sim/array.vvp
# Randomized testbench (600 operations)
iverilog -g2012 -I rtl -o sim/random.vvp rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v tb/tb_systolic_array_random.v && vvp sim/random.vvp
# Overflow demonstration
iverilog -g2012 -I rtl -o sim/ovf.vvp rtl/mac_unit.v rtl/pe.v rtl/systolic_array_3x3.v tb/tb_array_overflow_check.v && vvp sim/ovf.vvp
```
To regenerate the randomized test vectors: `python3 scripts/gen_array_vectors.py`.

---

## 📁 Repository Directory Structure

```
TensoraX/
├── README.md                    # Project documentation & specs
├── rtl/                         # Synthesizable Verilog RTL source files
│   ├── tensora_pkg.vh           # Global architectural parameters & precision
│   ├── mac_unit.v               # 16-bit signed MAC arithmetic core
│   ├── pe.v                     # Pipelined Processing Element
│   └── systolic_array_3x3.v     # Top-level 2D systolic mesh grid
├── tb/                          # Self-checking verification testbenches
│   ├── tb_pe.v                  # PE unit testbench
│   ├── tb_systolic_array_3x3.v  # Directed 3x3 array testbench
│   ├── tb_systolic_array_random.v  # Randomized array testbench
│   ├── tb_array_overflow_check.v   # 32-bit accumulator wrap demonstration
│   └── vectors/
│       └── array_rand_vectors.hex  # Randomized test vectors
├── scripts/                     # Automation & reference models
│   ├── auto_sync.sh             # Background git collaboration sync daemon
│   ├── pe_golden_model.py       # Python reference verification model
│   ├── gen_array_vectors.py     # Regenerates the randomized test vectors
│   └── run_pe_sim.sh            # PE unit simulation script
└── docs/                        # Architecture & design documents
    ├── ARCHITECTURE.md          # Detailed microarchitecture spec
    └── PE_MICROARCHITECTURE.md  # Core PE datapath & timing analysis
```

---

## 🎯 Verification Results

All results are from Icarus Verilog RTL simulation. No synthesis, area or timing results exist yet.

| Testbench | Result |
| :--- | :--- |
| `tb_pe.v` (PE unit) | 0 errors |
| `tb_systolic_array_3x3.v` (directed, 4 tests) | 0 errors; outputs settle 7 cycles (3N-2) after the first feed |
| `tb_systolic_array_random.v` | 600 operations, 5,400 output checks, 0 errors |
| `tb_array_overflow_check.v` | All operands -32768: C00 wraps to -1073741824 (see note below) |

Reference case from the directed test: A = [1..9] times B = [9..1] gives C = [30 24 18; 84 69 54; 138 114 90].

**Overflow note:** the 32-bit accumulator wraps when a dot product exceeds the signed 32-bit range (for example 3 x 2^30 with all operands at -32768). Results are correct only while every intermediate and final accumulation stays within the signed 32-bit range [-2^31, 2^31-1].

---

## 📜 License & Academic Integrity
Developed as part of the **Modern Computer Architecture (MCA)** course for B.Tech (Computer Science & Artificial Intelligence). All rights reserved by **Team TensoraX**.
