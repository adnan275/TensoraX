# TensoraX: Systolic Array Matrix Multiplication Accelerator
## Microarchitecture & Hardware Specification Document

**Project Code:** TensoraX  
**Architecture Type:** 2D Mesh Systolic Array (Output-Stationary Architecture)  
**Target Application:** Deep Learning GEMM (General Matrix Multiply) & Edge AI Acceleration  
**Lead Architect:** Adnan Rizvi (Core Microarchitecture & PE Datapath Lead)  

---

## 1. Executive Architectural Summary

TensoraX is a high-throughput, energy-efficient hardware accelerator designed to overcome the memory-wall bottleneck in deep learning inference. Matrix multiplication ($C = A \times B$) accounts for $>80\%$ of arithmetic operations in Convolutional Neural Networks (CNNs), Transformers, and Multi-Layer Perceptrons (MLPs).

Traditional Von-Neumann architectures incur massive memory bandwidth overheads fetching intermediate partial sums from cache/DRAM. TensoraX employs a **2D Systolic Array** paradigm:
- **Spatial Data Reuse:** Matrix inputs are pumped rhythmically through a 2D grid of interconnected Processing Elements (PEs).
- **Zero Intermediate Memory Access:** Once an activation ($A$) or weight ($B$) enters the array, it is forwarded horizontally and vertically to neighboring PEs across clock cycles without accessing main memory.
- **Pipelined MAC Pipeline:** Each PE computes a local Multiply-Accumulate (MAC) operation per clock cycle.

---

## 2. Microarchitecture Specifications

| Parameter | Specification | Hardware Rationale |
| :--- | :--- | :--- |
| **Array Topology** | $3 \times 3$ Orthogonal 2D Grid (9 PEs) | Modular, synthesizable, optimal for FPGA demonstration |
| **Input Operand Width** | 16-bit Signed Two's Complement (`signed [15:0]`) | Balances dynamic range for neural activations/weights |
| **Accumulator Width** | 32-bit Signed (`signed [31:0]`) | Holds any single product; extreme dot products can wrap (see PE_MICROARCHITECTURE.md) |
| **Dataflow Paradigm** | Output-Stationary / Wavefront Propagation | Partial sums remain stationary in PEs, minimizing routing capacitance |
| **Clocking & Timing** | Synchronous Single-Clock, Active-Low Reset (`rst_n`) | Standard synthesizable ASIC/FPGA digital design |
| **Latency for $3 \times 3$ GEMM** | $3N - 2 = 7$ active computation cycles | Theoretical minimum for 2D systolic wavefront |

---

## 3. Core Processing Element (PE) Datapath

Each PE $(i, j)$ in the $3 \times 3$ grid consists of:
1. **Arithmetic Multiplier:** $16\text{-bit} \times 16\text{-bit} \to 32\text{-bit}$ signed multiplier.
2. **Arithmetic Accumulator:** 32-bit adder with clear/reset control.
3. **Pipeline Registers (Spatial Forwarding):**
   - $A_{\text{reg}}$: Registers activation $A_{\text{in}}$ and forwards it to the right neighbor $PE(i, j+1)$ on the next clock edge.
   - $B_{\text{reg}}$: Registers weight $B_{\text{in}}$ and forwards it to the bottom neighbor $PE(i+1, j)$ on the next clock edge.
   - $V_{\text{reg}}$: Propagates control/valid signals synchronously.

```
                  B_in [15:0] (From North / PE[i-1,j])
                       |
                       v
                 +------------+
                 |   B_reg    |
                 +-----+------+
                       |
                       +----------------+
                       |                |
                       v                v
A_in [15:0] ------> [A_reg] ------> [ Multiplier ]
(From West / PE[i,j-1]) |                | 32-bit
                        v                v
                   A_out [15:0]      [  Adder   ] <---+
                   (To East / PE[i,j+1]) |            |
                                         v            |
                                   [ Accumulator ]----+
                                         |
                                         v
                                    C_out [31:0]
                                         |
                                         v
                                    B_out [15:0]
                               (To South / PE[i+1,j])
```

---

## 4. Systolic Wavefront Dataflow (Skewed Feeding)

To synchronize the spatial arrival of matching row and column entries, inputs are skewed by 1 cycle per row/column:

### Matrix A (West Boundary - Row by Row):
- **Row 0 ($A_{0,k}$):** Fed at $t = 0, 1, 2$
- **Row 1 ($A_{1,k}$):** Fed at $t = 1, 2, 3$ (1-cycle delay)
- **Row 2 ($A_{2,k}$):** Fed at $t = 2, 3, 4$ (2-cycle delay)

### Matrix B (North Boundary - Column by Column):
- **Col 0 ($B_{k,0}$):** Fed at $t = 0, 1, 2$
- **Col 1 ($B_{k,1}$):** Fed at $t = 1, 2, 3$ (1-cycle delay)
- **Col 2 ($B_{k,2}$):** Fed at $t = 2, 3, 4$ (2-cycle delay)

---

## 5. Team TensoraX Engineering Roles

- **Adnan Rizvi:** Lead Microarchitect — Core PE Datapath & MAC Mathematical Engine Design
- **Praanshu:** Array Interconnect & 2D Grid Architect
- **Anurag:** System Verification & Automated Testbench Lead
- **Aditya Pal:** Hardware Visualization & Prototype Video Producer
- **Aviral:** Toolflow, Automation & IEEE Report Documentation Lead
