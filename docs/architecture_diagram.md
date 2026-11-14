
# TensoraX — 3×3 Systolic Array Architecture

## Overview

TensoraX uses a 3×3 systolic array consisting of nine Processing Elements (PEs).

- Activation values (A) enter from the West and move horizontally.
- Weight values (B) enter from the North and move vertically.
- Each PE contains a Multiply-Accumulate (MAC) unit.
- Each PE maintains its own local accumulator.
- The nine accumulated results form the output matrix C.

## Architecture Diagram

```mermaid
flowchart TB
    B0["B Column 0"]
    B1["B Column 1"]
    B2["B Column 2"]

    subgraph ARRAY["3×3 Systolic Array"]
      direction TB
      subgraph R0["Row 0"]
        P00["PE (0,0)"] --> P01["PE (0,1)"] --> P02["PE (0,2)"]
      end
      subgraph R1["Row 1"]
        P10["PE (1,0)"] --> P11["PE (1,1)"] --> P12["PE (1,2)"]
      end
      subgraph R2["Row 2"]
        P20["PE (2,0)"] --> P21["PE (2,1)"] --> P22["PE (2,2)"]
      end
    end

    A0["A Row 0"] --> P00
    A1["A Row 1"] --> P10
    A2["A Row 2"] --> P20

    B0 --> P00
    B1 --> P01
    B2 --> P02

    P00 --> P10
    P01 --> P11
    P02 --> P12
    P10 --> P20
    P11 --> P21
    P12 --> P22

    P00 --> C00["C(0,0)"]
    P01 --> C01["C(0,1)"]
    P02 --> C02["C(0,2)"]
    P10 --> C10["C(1,0)"]
    P11 --> C11["C(1,1)"]
    P12 --> C12["C(1,2)"]
    P20 --> C20["C(2,0)"]
    P21 --> C21["C(2,1)"]
    P22 --> C22["C(2,2)"]
```

## Processing Element

Each PE performs the following operation:

C(i,j) = C(i,j) + A(i,k) × B(k,j)

The PE forwards activation data to its right neighbour and weight data to its bottom neighbour.

## Verified Test Result

The directed simulation produced:

C =

| 30 | 24 | 18 |
|---:|---:|---:|
| 84 | 69 | 54 |
| 138 | 114 | 90 |

All nine outputs matched the golden reference.

## Simulation Status

- Test 1: Unsigned ramp — PASS
- Test 2: Signed corner cases — PASS
- Test 3: Identity weights — PASS
- Test 4: Reset — PASS

Total verification errors: 0
