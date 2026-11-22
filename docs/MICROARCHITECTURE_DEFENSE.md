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
