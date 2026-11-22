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


---

## 3. External Memory Traffic & Bandwidth Savings

In conventional Von-Neumann multi-core processors, computing $C_{i,j} = \sum_{k=0}^{N-1} A_{i,k} \cdot B_{k,j}$ requires repeatedly reading vectors from high-latency external memory (DRAM/L3 Cache) into registers.

### Memory Traffic Comparison Equations:
1. **Naive CPU Implementation (Zero Spatial Reuse):**
   - Each dot-product element $C_{i,j}$ reads a row of $A$ ($N$ elements) and a column of $B$ ($N$ elements).
   - Across $N^2$ elements, total memory reads equal:
     $$\text{Traffic}_{\text{CPU}}(N) = \left(2 N^3 + N^2\right) \times \text{BytesPerElement}$$
2. **TensoraX 2D Systolic Array (Spatial Forwarding Reuse):**
   - Each matrix element $A_{i,k}$ is fetched from memory **exactly once** at the western boundary.
   - Each weight element $B_{k,j}$ is fetched from memory **exactly once** at the northern boundary.
   - Total memory traffic equals:
     $$\text{Traffic}_{\text{TensoraX}}(N) = \left(2 N^2 + N^2\right) \times \text{BytesPerElement} = 3 N^2 \times \text{BytesPerElement}$$

### Traffic Reduction Ratio:
$$\text{Reduction Ratio} = \frac{\text{Traffic}_{\text{CPU}}}{\text{Traffic}_{\text{TensoraX}}} = \frac{2N^3 + N^2}{3N^2} = \frac{2N + 1}{3}$$

| Matrix Dimension ($N$) | Naive CPU Traffic (Bytes) | TensoraX Traffic (Bytes) | Bandwidth Reduction |
| :---: | :---: | :---: | :---: |
| **$N = 2$** | 40 B | 24 B | **1.67x** |
| **$N = 3$** (TensoraX) | 126 B | 54 B | **2.33x** |
| **$N = 4$** | 288 B | 96 B | **3.00x** |
| **$N = 8$** | 2,176 B | 384 B | **5.67x** |
| **$N = 16$** | 16,896 B | 1,536 B | **11.00x** |

This spatial data reuse directly circumvents the Von-Neumann memory-wall bottleneck, yielding massive power and latency reductions.


---

## 4. Roofline Model & Operational Intensity

The Roofline Model provides an architectural framework relating system performance to operational intensity:
$$\text{Attainable Performance [FLOPs/sec]} = \min\left(\text{Peak Performance}, \text{Peak Bandwidth} \times \text{Operational Intensity}\right)$$

### Arithmetic Intensity ($I$):
Operational intensity is defined as the ratio of arithmetic operations to external memory traffic:
$$I(N) = \frac{\text{Total Arithmetic Operations [FLOPs]}}{\text{External Memory Traffic [Bytes]}} = \frac{2 N^3}{3 N^2 \times 2\text{ bytes}} = \frac{N}{3}\text{ FLOPs/Byte}$$

- For $N = 3$:
  $$I(3) = \frac{3}{3} = 1.0\text{ FLOP/Byte}$$
- For $N = 16$:
  $$I(16) = \frac{16}{3} \approx 5.33\text{ FLOPs/Byte}$$
- For $N = 64$:
  $$I(64) = \frac{64}{3} \approx 21.33\text{ FLOPs/Byte}$$

As array dimension $N$ increases, TensoraX transitions rapidly from a memory-bandwidth-bound regime into a compute-bound saturation regime, maximizing silicon efficiency.
