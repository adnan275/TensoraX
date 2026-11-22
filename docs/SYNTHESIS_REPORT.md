# TensoraX Phase 2: FPGA Synthesis and Timing Report

Workstream 02, Aviral Mishra (FPGA Synthesis & Timing Lead)

## 1. Scope

This report covers the TensoraX 3x3 systolic array (`systolic_array_3x3.v`, `pe.v`, `mac_unit.v`). It gives (a) Artix-7 resource utilization from synthesis and (b) measured timing from a place-and-route run on a different FPGA family, because Artix-7 static timing was not run. Section 4 explains exactly what that does and does not show.

## 2. Setup

| Item | Value |
|---|---|
| Source | https://github.com/adnan275/TensoraX, commit `3661845b01591364cc6989550dda01cc93228279` (main, 22 Nov 2026) |
| Top module | `systolic_array_3x3` (N = 3, DATA_WIDTH = 16, ACC_WIDTH = 32) |
| RTL files | `rtl/systolic_array_3x3.v`, `rtl/pe.v`, `rtl/mac_unit.v` (+ `tensora_pkg.vh`); SHA-256 in `MANIFEST.txt` |
| Ports | clk, rst_n, clr_acc, valid_in (1 bit each); a_rows 48 bits; b_cols 48 bits; c_flat 288 bits |
| Resource run | Yosys 0.71, `synth_xilinx -family xc7 -flatten`, synthesis only |
| Timing run | Yosys `synth_ecp5` + nextpnr-ecp5 0.11.1, device LFE5U-85F, speed grade 6, out-of-context |

Reproduction scripts, the source manifest, resource summaries, all three nextpnr timing logs and both full synthesis logs are in [`synthesis/`](synthesis/). Copy `rtl/*.v`, `rtl/tensora_pkg.vh` and `docs/synthesis/*` from this repository into an empty working folder. In that folder, run `yosys -s synth_yosys.ys` for Artix-7 resource synthesis, or `sh run_ecp5_timing.sh` for the ECP5 timing test.

`yosys_full_synth.log` (2,060,532 bytes) and `yosys_ecp5_synth.log` (112,072 bytes) are the complete synthesis tool outputs, committed byte-identical to the original runs (SHA-256 in `synthesis/MANIFEST.txt`). The committed resource summaries and nextpnr timing logs preserve every recorded result; blank lines at their file boundaries may differ.

## 3. Resource utilization (Artix-7 family, Yosys)

| Resource | Count | Notes |
|---|---|---|
| DSP48E1 | 9 | One per PE. The 16x16 signed multiply fits one DSP48E1. |
| LUT (total) | 576 | LUT2: 288, LUT4: 9, LUT5: 279 |
| CARRY4 | 72 | 8 per PE, for the 32-bit accumulator adders |
| Registers (FDCE) | 482 | Async-clear flip-flops |
| IBUF | 100 | 48 (a_rows) + 48 (b_cols) + clr_acc + valid_in + rst_n + clk |
| OBUF | 288 | 9 x 32-bit `c_flat` |
| BUFG | 1 | Clock |

- **DSP48:** 9 matches the architecture (one DSP per PE).
- **Registers:** Without trimming, 9 PEs would hold 585 flip-flops (32 accumulator + 16 `a_out` + 16 `b_out` + 1 valid, per PE). Synthesis reports 482 because the forwarding outputs on the east and south array edges are not connected to anything and are removed. I did not break down the remaining difference further.
- **LUTs:** Mostly accumulator logic (288 LUT2 with 72 CARRY4 is 9 PEs x 32 bits). No block RAM is used.
- **I/O:** `c_flat` is 288 bits, so the core has 388 I/O buffers. The array is treated as a core, not a standalone top level. No board or package has been selected, and a board design would need a wrapper (for example a register or BRAM interface). These are core numbers, not a pin-level result.

These counts come from synthesis only. The design has not been placed on an Artix-7.

## 4. Timing

### What was measured

Artix-7 WNS and Fmax were **not** measured. I measured timing on a Lattice ECP5 instead, using the open-source nextpnr place-and-route flow. This is a different device family, so it is a proxy, not an Artix-7 number.

Setup: same RTL, `synth_ecp5` (9 MULT18X18D, 144 CCU2C carry cells, 292 LUT4, 482 flip-flops), nextpnr-ecp5 on LFE5U-85F, speed grade 6, out-of-context (no I/O buffers, so the 388 I/O bits do not matter), single clock `clk`, target 200 MHz (`TARGET_FREQ_MHZ` in `tensora_pkg.vh`), no input or output delays. Only register-to-register paths are timed. I ran three placer seeds.

| Seed | Max frequency after routing | Result at 200 MHz target |
|---|---|---|
| 1 | 93.32 MHz | fail |
| 2 | 92.97 MHz | fail |
| 3 | 93.68 MHz | fail |

### Critical path

In the seed 1 log the worst path is register to multiplier to 32-bit accumulator. It goes from a register at the multiplier input, through the MULT18X18D (about 3.9 ns of logic), over routing (about 2.1 ns), then through the carry chain into the accumulator flip-flop. This matches the structure: the product is computed and added in the same cycle.

### What it means

- On ECP5, this core does not reach 200 MHz and closes at about 93 MHz.
- The ECP5 result does not predict Artix-7 speed. The Artix-7 DSP48E1 and carry logic are different, and the Artix-7 Fmax could be higher or lower. The accumulator add after the multiply is the likely limit on both, which is a structural expectation, not an Artix-7 measurement.
- Adnan's estimate of about 263 MHz (`MICROARCHITECTURE_DEFENSE.md`) is an architecture estimate, not a tool result. This run does not confirm it for ECP5.
- Yosys also reports a longest topological path of 140 cells for the Artix-7 mapping. That is logic depth, not a delay.

### Gap

| Metric | Artix-7 | ECP5 proxy |
|---|---|---|
| WNS | not measured | negative at 200 MHz (Fmax about 93 MHz) |
| Fmax | not measured | 92.97 to 93.68 MHz across 3 seeds |

An Artix-7 WNS and Fmax would need Xilinx timing tools. They are not in this report.

## 5. Implementation summary

- Yosys infers 9 DSP48E1 slices, carry-chain adders and 482 flip-flops for the core on the Artix-7 family. This is synthesis only.
- Measured on ECP5 (proxy): about 93 MHz after routing, below the 200 MHz target, limited by the multiply-then-accumulate path.
- Limitations: no Artix-7 place-and-route or timing, no board or package, I/O paths unconstrained, one clock only.
- A likely improvement is to register the multiplier output before the accumulate. That changes the RTL and the 7-cycle latency, so it was not applied or tested.

## 6. Viva notes

- Resources inferred: 9 DSP48E1, 72 CARRY4, 576 LUTs, 482 FFs (Yosys, Artix-7 family).
- Timing: say it was measured on ECP5, not Artix-7, about 93 MHz, and that 200 MHz was not met there. Do not present 263 MHz as measured.
- Why 482 registers and not 585: unused edge-forwarding outputs are removed.
