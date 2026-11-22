# TensoraX: Microarchitecture Defense & Design Rationale

**Author:** Adnan Rizvi (Lead Microarchitect & Scaling Analysis Lead)  
**Project:** TensoraX — Systolic Array Matrix Multiplication Accelerator  
**Target:** MCA Phase 2 Architecture Evaluation & Oral Defense  

---

## 1. Architectural Dataflow Paradigm Comparison

A foundational architectural decision in 2D systolic computing is dataflow taxonomy:

| Feature | Output-Stationary (OS) — **TensoraX** | Weight-Stationary (WS) — *Google TPU v1* | Weight-Streaming (IS) |
| :--- | :--- | :--- | :--- |
| **Accumulator Location** | Stationary inside each PE cell | Moves across columns / tree adders | Stationary in output buffers |
| **Partial Sum Energy** | **Minimal** (accumulates locally in register) | High (partial sums stream continuously) | High (partial sums stream) |
| **Register Switching** | Lower dynamic power toggling | Higher clock toggling across array | Moderate |
| **Weight Reload Overhead**| Weights stream alongside activations | Weights must be pre-loaded into PEs | Continuous memory streaming |
| **Tile Scalability** | Excellent for small/medium GEMM tiles | Optimal for large batch inferences | Good for 1D convolution |

### Architectural Rationale for TensoraX:
In TensoraX, we selected the **Output-Stationary (OS)** dataflow:
1. Accumulating intermediate partial products within local 32-bit registers eliminates long inter-PE routing wires for high-precision sums.
2. In typical edge AI inferences ($N \le 16$), pre-loading overheads in Weight-Stationary arrays introduce latency bubbles; Output-Stationary streams both operands simultaneously with zero pre-load cycles.


---

## 2. Critical Path & FPGA DSP48 Slice Mapping

### A. Critical Path Breakdown
The critical path in each TensoraX Processing Element spans the register-to-register path through the arithmetic datapath:
$$T_{\text{clk}} \ge T_{\text{clk-to-Q}} + T_{\text{mult}} + T_{\text{add}} + T_{\text{setup}}$$

On AMD-Xilinx 28nm Artix-7 silicon:
- $T_{\text{clk-to-Q}} \approx 0.35\text{ ns}$ (Slice Flip-Flop)
- $T_{\text{DSP48E1}} \approx 2.40\text{ ns}$ (Integrated $18 \times 25$ multiplier + 48-bit accumulator)
- $T_{\text{routing}} \approx 0.85\text{ ns}$ (Local interconnect)
- $T_{\text{setup}} \approx 0.20\text{ ns}$
- **Total Critical Path Delay:** $T_{\text{critical}} \approx 3.80\text{ ns}$
- **Theoretical Maximum Operating Frequency ($F_{\max}$):**
  $$F_{\max} = \frac{1}{T_{\text{critical}}} \approx \frac{1}{3.80\text{ ns}} \approx 263.15\text{ MHz}$$

### B. DSP Mapping Strategy
Because operands are 16-bit signed integers:
- A single Xilinx DSP48E1 slice natively supports $25 \times 18$ signed multiplication and 48-bit accumulation.
- TensoraX's $16 \times 16 \to 32$ operation maps **one-to-one** into a single DSP48E1 slice without requiring multi-slice cascading or soft-logic LUT multiplier trees.
- For a $3 \times 3$ array, exactly 9 DSP slices are consumed, leaving over 90% of FPGA DSP resources free for system integration.


---

## 3. Accumulator Sizing Proof & Mathematical Bounds

A critical architectural consideration is numerical precision and accumulator sizing:
- **Input range:** Signed 16-bit integer $[-32,768, +32,767]$.
- **Single Product dynamic range:**
  $$P_{\max} = (-32,768) \times (-32,768) = 1,073,741,824 = +2^{30}$$
- **Sum of $K$ products for dimension $N = 3$:**
  $$C_{\max} = \sum_{k=0}^{2} A_{i,k} \cdot B_{k,j} = 3 \times 2^{30} \approx 3,221,225,472$$
- In standard two's-complement arithmetic:
  - Signed 32-bit integer dynamic range: $[-2^{31}, +2^{31}-1] = [-2,147,483,648, +2,147,483,647]$.
  - If all operands simultaneously occupy the worst-case negative boundary ($-32,768$), $3 \times 2^{30}$ exceeds $+2^{31}-1$ and wraps around to negative:
    $$3,221,225,472 \pmod{2^{32}} = -1,073,741,824$$
- **Architectural Rationale:**
  1. In realistic normalized neural network models (e.g. weights in range $[-1.0, +1.0]$ or INT16 activations), values never occupy uniform extreme negative rails simultaneously.
  2. For safety-critical workloads with arbitrary integer inputs, an extended 34-bit accumulator (`ACC_WIDTH = 34`) provides complete numerical headroom without wrap-around.


---

## 4. Interconnect Routing & Clock Tree Considerations

### A. Local Nearest-Neighbor Routing
In a standard crossbar or centralized register file, wire fanout scales as $O(N^2)$, causing routing congestion and capacitive delay spikes. In TensoraX:
- Each Processing Element communicates strictly with its direct **nearest neighbor**:
  - $A_{\text{out}}$ connects only to $PE(i, j+1)$ (Fanout = 1).
  - $B_{\text{out}}$ connects only to $PE(i+1, j)$ (Fanout = 1).
- Because wire fanout is strictly $1$, capacitive wire loading remains bounded and independent of array size $N$.

### B. Global Clock Distribution & Skew Mitigation
- The only global nets are `clk` and `rst_n`.
- Synchronous global clear `clr_acc` is broadcast across the array.
- On FPGA targets, global clock buffers (BUFG) ensure balanced low-skew clock distribution across all 9 PE flip-flop clusters, preventing hold-time violations across neighboring PEs.
