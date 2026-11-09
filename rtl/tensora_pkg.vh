// ============================================================================
// File: tensora_pkg.vh
// Project: TensoraX - Systolic Array Matrix Multiplication Accelerator
// Author: Adnan Rizvi (Lead Microarchitect & Core PE Datapath Engineer)
// Description: Global hardware parameters, bit-width quantizations, and 
//              control definitions for the TensoraX systolic computing grid.
// ============================================================================

`ifndef TENSORA_PKG_VH
`define TENSORA_PKG_VH

// Numerical Precision Specifications
`define DATA_WIDTH      16      // 16-bit signed operands (Q8.8 fixed-point or INT16)
`define ACC_WIDTH       32      // 32-bit signed accumulator to avoid overflow

// Systolic Array Dimensions
`define ARRAY_SIZE      3       // 3x3 Processing Element Grid
`define NUM_PES         (`ARRAY_SIZE * `ARRAY_SIZE) // 9 Processing Elements

// Timing & Latency Configuration
`define COMPUTE_CYCLES  (3 * `ARRAY_SIZE - 2) // 7 cycles for 3x3 systolic wavefront

`endif // TENSORA_PKG_VH
