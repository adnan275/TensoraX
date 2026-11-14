# TensoraX: Processing Element (PE) Microarchitecture & Datapath Analysis

**Author:** Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)  
**Project:** TensoraX — Systolic Array Matrix Multiplication Accelerator  
**Target:** Modern Computer Architecture (MCA) RTL Project  

---

## 1. Architectural Overview & Design Objectives

The Processing Element (PE) constitutes the fundamental arithmetic building block of the TensoraX systolic computing fabric. In high-density General Matrix Multiply (GEMM) hardware, the PE microarchitecture dictates:
1. Maximum operating frequency ($F_{\max}$) via the critical timing path.
2. Area and gate-count scaling across the 2D grid.
3. Power consumption, particularly dynamic switching power dissipated during continuous inner-product accumulation.

TensoraX's PE implements an **Output-Stationary (OS)** datapath tailored for signed 16-bit fixed-point numerical formats.

```
                           B_in [15:0] (from North PE)
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
(from West PE)                 |                   | (32-bit Product)
                               v                   v
                          A_out [15:0]         [ 32-bit Adder ] <-----+
                          (to East PE)             |                  |
                                                   v                  |
                                            [ Acc Register ] ---------+
                                                   |
                                                   v
                                              C_out [31:0]
                                                   |
                                                   v
                                              B_out [15:0] (to South PE)
```

---

## 2. Arithmetic Bounds & Overflow Prevention

### Numerical Range Analysis:
- **Input Operands ($A, B$):** 16-bit signed two's complement integers:
  $$-2^{15} \le A, B \le 2^{15} - 1 \quad \implies \quad [-32,768, +32,767]$$
- **Intermediate Product ($P = A \times B$):**
  $$P_{\max} = (-32,768)^2 = 1,073,741,824 = 2^{30}$$
  A minimum of 32 signed bits is required to hold this product ($2^{30}$ needs 31 magnitude bits plus a sign bit).
- **Dot-Product Accumulation ($C_{i,j} = \sum_{k=0}^{K-1} A_{i,k} \cdot B_{k,j}$):**
  For an $N \times N$ matrix ($N = 3$), the maximum accumulator value:
  $$\text{Acc}_{\max} = 3 \times 2^{30} \approx 3.22 \times 10^9 > 2^{31} - 1 = 2,147,483,647$$
  TensoraX provisions a **32-bit signed accumulator**. A single product always fits, but the worst-case dot product (all operands at $-32,768$) exceeds the 32-bit signed range and wraps in two's-complement arithmetic (simulated: $-1,073,741,824$). The accumulator is correct only while every intermediate and final accumulation stays within the signed 32-bit range $[-2^{31}, 2^{31}-1]$; inputs that can exceed it need a wider accumulator or saturation.

---

## 3. Timing Path & Critical Path Budget

The critical path of the PE determines the cycle time $T_{\text{clk}}$:
$$T_{\text{critical}} = T_{\text{clk-to-Q}} + T_{\text{multiplier}} + T_{\text{adder}} + T_{\text{setup}}$$

1. **Multiplier Latency ($T_{\text{mult}}$):** $16 \times 16$ signed multiplier (combinatorial Booth-Wallace tree or dedicated FPGA DSP48 slice: $\approx 2.4\text{ ns}$).
2. **Adder Latency ($T_{\text{add}}$):** 32-bit carry-lookahead accumulator: $\approx 1.1\text{ ns}$.
3. **Flip-Flop Overheads ($T_{\text{clk-to-Q}} + T_{\text{setup}}$):** $\approx 0.5\text{ ns}$.

$$\implies T_{\text{critical}} \approx 4.0\text{ ns} \quad \implies \quad F_{\max} \approx 250\text{ MHz}$$
On modern 28nm/16nm FPGA nodes (e.g., AMD-Xilinx Artix-7 or UltraScale+), TensoraX can readily achieve clock frequencies beyond $200\text{ MHz}$.

---

## 4. Hardware Resource Footprint (Per PE Cell)

| Component | Logic Primitive | Quantity | Purpose |
| :--- | :--- | :--- | :--- |
| **Multiplier** | DSP48E1 / Logic LUTs | 1 DSP slice (or ~220 LUTs) | Signed 16x16 integer multiplication |
| **Accumulator** | Slice Registers / Adders | 32 Flip-Flops + 32 LUTs | Running dot-product sum |
| **Spatial Forwarding Regs** | D-Flip-Flops | 32 Flip-Flops ($A_{\text{reg}} + B_{\text{reg}}$) | Systolic wave propagation |
| **Control Registers** | D-Flip-Flops | 2 Flip-Flops | Valid signal propagation |
| **Total per PE** | — | **~66 FFs, 1 DSP / ~250 LUTs** | Extremely compact silicon area |

---

## 5. Architectural Comparison

| Architectural Feature | TensoraX PE (This Work) | Google TPU v1 PE | Conventional SIMD (AVX-512) |
| :--- | :--- | :--- | :--- |
| **Dataflow** | Output-Stationary | Weight-Stationary | Register-File Memory Bound |
| **Operand Precision** | 16-bit Signed Fixed-Point | 8-bit Integer (INT8) | 32-bit Single Precision (FP32) |
| **Accumulator Width** | 32-bit Signed | 24-bit Integer | 32-bit Float |
| **Intermediate Memory Access** | **Zero (Spatial Routing)** | Zero (Spatial Routing) | High (Cache Hierarchy Traversal) |
| **RTL Modularity** | Fully Synthesizable Verilog | Custom ASIC | Fixed Instruction Set Architecture |
