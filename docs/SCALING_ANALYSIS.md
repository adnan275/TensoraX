# TensoraX: Architectural Scaling & Performance Bounds

**Author:** Adnan Rizvi (Lead Microarchitect & Scaling Analysis Lead)  
**Project:** TensoraX — Systolic Array Matrix Multiplication Accelerator  
**Target:** Modern Computer Architecture (MCA) Phase 2 Specifications  

---

## 1. Mathematical Derivation of Systolic Latency

For an arbitrary $N \times N$ orthogonal mesh systolic array multiplying two $N \times N$ matrices ($C = A \times B$):

### A. Boundary Skewing Latency
To synchronize matching row and column wavefronts at the spatial intersections, matrix inputs are skewed:
- Row $i$ of Matrix $A$ is injected with delay $i$ cycles: $\Delta t_{A}(i) = i$, for $i \in [0, N-1]$.
- Column $j$ of Matrix $B$ is injected with delay $j$ cycles: $\Delta t_{B}(j) = j$, for $j \in [0, N-1]$.

### B. Spatial Propagation Latency
The last element of the computation corresponds to the southeastern-most Processing Element, $PE(N-1, N-1)$:
1. The last element of Row $N-1$ ($A_{N-1, N-1}$) enters the array at cycle:
   $$t_{\text{inject}} = (N - 1) + (N - 1) = 2N - 2$$
2. This operand propagates through $N - 1$ horizontal registers before reaching $PE(N-1, N-1)$:
   $$t_{\text{prop}} = N - 1$$
3. Therefore, the final accumulation completes at clock cycle:
   $$T_{\text{latency}} = t_{\text{inject}} + t_{\text{prop}} = (2N - 2) + (N - 1) + 1 = 3N - 2$$

For our primary implementation with $N = 3$:
$$T_{\text{latency}} = 3(3) - 2 = 7\text{ clock cycles}$$

---

## 2. Hardware Compute Density & Utilization Efficiency

### Single-Tile Wavefront Efficiency:
During execution of a single isolated $N \times N$ matrix multiplication:
- Total Multiply-Accumulate operations performed: $N^3$
- Total available PE slots over execution time: $N^2 \times (3N - 2)$
- Single-tile hardware utilization efficiency $\eta_{\text{single}}$:
  $$\eta_{\text{single}}(N) = \frac{N^3}{N^2(3N - 2)} = \frac{N}{3N - 2}$$

As $N \to \infty$:
$$\lim_{N \to \infty} \eta_{\text{single}}(N) = \lim_{N \to \infty} \frac{N}{3N - 2} = \frac{1}{3} \approx 33.33\%$$

### Pipelined Batch Streaming Efficiency:
When streaming consecutive matrix tiles back-to-back (e.g. processing batches in Deep Learning inference), the latency overhead is amortized:
$$T_{\text{batch}}(K) = (3N - 2) + (K - 1) \cdot N$$
$$\eta_{\text{batch}}(K) = \frac{K \cdot N^3}{N^2 \cdot \left((3N - 2) + (K - 1) \cdot N\right)} \xrightarrow{K \gg 1} \frac{K \cdot N^3}{K \cdot N^3} = 100.0\%$$
