
# TensoraX — 3×3 Systolic Wavefront Propagation

## 1. Overview

The TensoraX systolic array uses a staggered input schedule to align
activation and weight operands at the correct Processing Elements.

- Activations (A) enter from the West and propagate East.
- Weights (B) enter from the North and propagate South.
- Each PE performs a Multiply-Accumulate (MAC) operation.
- Each PE stores its own partial sum.

## 2. Input Feed Schedule — Test 1

| Feed Cycle | A Rows | B Columns |
|---:|---|---|
| 0 | [1, 0, 0] | [9, 0, 0] |
| 1 | [2, 4, 0] | [6, 8, 0] |
| 2 | [3, 5, 7] | [3, 5, 7] |
| 3 | [0, 6, 8] | [0, 2, 4] |
| 4 | [0, 0, 9] | [0, 0, 1] |

The zeros represent intentional gaps in the skewed input streams.

## 3. MAC Accumulation Wavefront

The table shows the clock cycle in which each PE accumulates
each of its three products.

| Processing Element | k=0 | k=1 | k=2 |
|---|---:|---:|---:|
| PE(0,0) | 1 | 2 | 3 |
| PE(0,1) | 2 | 3 | 4 |
| PE(0,2) | 3 | 4 | 5 |
| PE(1,0) | 2 | 3 | 4 |
| PE(1,1) | 3 | 4 | 5 |
| PE(1,2) | 4 | 5 | 6 |
| PE(2,0) | 3 | 4 | 5 |
| PE(2,1) | 4 | 5 | 6 |
| PE(2,2) | 5 | 6 | 7 |

Cycle numbering begins at the first rising clock edge after the
initial feed edge.

## 4. Wavefront Across the Array

```text
             NORTH: B flows downward
                  ↓       ↓       ↓

              PE(0,0) → PE(0,1) → PE(0,2)
                 ↓         ↓         ↓
WEST: A →     PE(1,0) → PE(1,1) → PE(1,2)
                 ↓         ↓         ↓
              PE(2,0) → PE(2,1) → PE(2,2)

             EAST: A continues right
             SOUTH: B continues down
```

## 5. Matrix Multiplication

Each PE computes:

C(i,j) = Σ A(i,k) × B(k,j), for k = 0, 1, 2

Each PE accumulates its three products locally.

## 6. Verified Output

The Test 1 simulation produced:

| 30 | 24 | 18 |
|---:|---:|---:|
| 84 | 69 | 54 |
| 138 | 114 | 90 |

The testbench verified all nine outputs against its software
golden reference.

## 7. Latency

For a 3×3 array:

3N − 2 = 3(3) − 2 = 7 cycles

The testbench checks that the final result is available at cycle 7.

## 8. Verification Status

- Unsigned ramp test: PASS
- Signed corner-case test: PASS
- Identity matrix test: PASS
- Asynchronous reset test: PASS
- Total verification errors: 0
```
