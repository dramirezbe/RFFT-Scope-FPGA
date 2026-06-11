# RFFT Context and Verilog Module Guide (actualizado con implementacion final/)

This document defines the implementation path for a 16-bit, 2048-point real FFT deployed on the Tang Primer 20K FPGA. The project has moved from research code to verified, synthesizable RTL with all 11 testbenches passing.

## Target Design (implemented)

- Input: 2048 real samples, 16-bit signed fixed-point, arriving via UART at 921600 bps from an ESP32+MAX9814 front-end.
- Output: 512 frequency bins (even-indexed, 0..24 kHz) rendered as spectrum bars on an 800×480 RGB LCD.
- Architecture: packed N/2 complex FFT flow, where N=2048 and the internal complex FFT size is 1024.
- Fixed-point style: Q15 arithmetic with saturation for all samples and coefficients.
- Scaling: 1/1024 global (>>1 per stage, 10 stages).

## Design Principle

For a real input sequence, the FFT output is Hermitian symmetric:

```
X[k] = X*[N-k]
```

Only N/2 + 1 bins are unique. The FPGA implementation uses:

1. packing of real samples into complex pairs,
2. a 1024-point complex FFT core,
3. a recombination stage to recover the real-spectrum bins,
4. decimation to even bins (512 values) for LCD display (46.88 Hz/px covering 0–24 kHz).

## Implemented Module Hierarchy

| Module | Location | Purpose |
|---|---|---|
| `rfft_scope_top` | `src/rfft_scope_top.v` | Top-level integration. Connects all submodules, instantiates PLL, handles CDC boundary. Parametrizable `CLK_FREQ` and `BAUD`. |
| `uart_rx` | `src/block1/uart_rx.v` | UART receiver (921600 bps, 8N1, MSB first). Decodes frame header `0xAA 0x55` + length + 2048 Q15 samples. |
| `sample_fifo` | `src/block1/sample_fifo.v` | 64-deep FIFO decoupling UART from buffer. Detects overflow. |
| `sample_buffer` | `src/block1/sample_buffer.v` | Ping-pong buffer capturing 2048 real Q15 samples. Generates `frame_done`/`frame_start`. |
| `pack_real_to_complex` | `src/block1/pack_real_to_complex.v` | Converts 2048 real samples into 1024 complex pairs: even-indexed -> real, odd-indexed -> imag. |
| `block1_i2s_top` | `src/block1/block1_i2s_top.v` | B1 top wrapper: `uart_rx` + `block1_top` (FIFO + buffer + pack). |
| `bit_reverse` | `src/block2/bit_reverse.v` | Computes bit-reversed addresses for indices 0..1023 (10 bits). |
| `dual_port_ram_buffer` | `src/block2/dual_port_ram_buffer.v` | Stores 1024 complex words, natural-order write / bit-reversed read. |
| `permutation_controller` | `src/block2/permutation_controller.v` | FSM managing write/read sequencing. Supports `br_ready` backpressure. |
| `block2_memory_bitreverse_top` | `src/block2/block2_memory_bitreverse_top.v` | B2 top wrapper. |
| `twiddle_rom` | `src/block3/twiddle_rom.v` | Dual synchronous ROM: 512×32 (FFT Wk_1024) + 1025×32 (Recomb Wk_2048). Q15 format, 1-cycle latency. |
| `butterfly_radix2` | `src/block3/butterfly_radix2.v` | Radix-2 DIT complex butterfly: 4 DSP multipliers, saturating Q15, 1-cycle latency. Does NOT apply per-stage shift. |
| `complex_fft_core` | `src/block4/complex_fft_core.v` | Main FFT FSM: 10 DIT stages. Instantiates `twiddle_rom`, `butterfly_radix2`, `fft_stage_controller`, and `working_memory`. 6 fixes applied (FIX-1 to FIX-6). |
| `fft_stage_controller` | `src/block4/fft_stage_controller.v` | Generates read addresses, strides, twiddle indices. Controls butterfly pacing with dual write cycle (Z1+Z2, FIX-4). |
| `working_memory` | `src/block4/working_memory.v` | True Dual-Port RAM: 2 banks × 1024 × 32 bits for ping-pong buffering between FFT stages. |
| `rfft_recombine` | `src/block5/rfft_recombine.v` | Recombination: Z[k] -> Xe/Oo + butterfly = X[k]. Outputs 512 even bins. Reuses `butterfly_radix2`. |
| `spectrum_buffer` | `src/block5/spectrum_buffer.v` | Dual-clock ping-pong RAM for CDC. Gates first frame to black. |
| `spectrum_draw` | `src/block5/spectrum_draw.v` | Renders spectrum bars + static axes (frequency in kHz, magnitude). Magnitude = `max+min/2`. |
| `block5_lcd_drawer` | `src/block5/block5_lcd_drawer.v` | B5 top wrapper: `spectrum_buffer` + `spectrum_draw`, CDC boundary. |
| `lcd_ctrl` | `src/lcd/lcd_ctrl.v` | LCD controller (from Sipeed `sin_lcd` example). Generates sync signals, pixel coordinates. |
| `pll_40m` | `src/lcd/gowin_rpll/pll_40m.v` | Gowin PLL: 27 MHz -> 40.5 MHz (27 × 3 / 2). |

## What Each Module Does

### `uart_rx` (replaces original `sample_buffer` ESP32 GPIO protocol)

Receives UART frames at 921600 bps:
- Header: `0xAA 0x55`
- Length: 2 bytes (big-endian, value = 2048)
- Payload: 2048 Q15 samples, MSB first
- Output: `sample_valid` + `sample_out[15:0]`

The original plan used GPIO toggle (`q15_data` + `q15_clk`). UART was chosen because it uses a single wire, works with standard ESP32 UART peripherals, and avoids timing closure issues with parallel buses.

### `sample_buffer` (ping-pong)

Captures 2048 samples from the FIFO into alternating banks. Generates `frame_done` when a bank is full. Handles `frame_dropped` if the consumer hasn't finished with the previous bank.

### `pack_real_to_complex`

Classic real-FFT packing: sample 0 -> complex real 0, sample 1 -> complex imag 0, etc. 2048 real -> 1024 complex.

### `bit_reverse` + `dual_port_ram_buffer` + `permutation_controller`

Writes 1024 complex samples in natural order (address 0..1023), reads them back in bit-reversed order for the DIT FFT. The `permutation_controller` FSM manages the write/read phases and supports `br_ready` backpressure from Block 4.

### `twiddle_rom`

Two independent synchronous read ports:
- **FFT port:** 512 entries × 32 bits. Addr [8:0], data = `{real[15:0], imag[15:0]}`. Used by Block 4 for butterfly twiddles during FFT stages.
- **Recomb port:** 1025 entries × 32 bits. Addr [10:0]. Used by Block 5 for the recombination butterfly. Passes through Block 4.

1-cycle read latency. Initialized via `$readmemh` in simulation; Gowin EDA maps to BSRAM with `.hex`/`.mi` init.

### `butterfly_radix2`

Arithmetic core: 4 Q15 multiplications -> complex product -> sum/difference with saturation. 1-cycle latency (`en` at T -> `done` at T+1). Does NOT apply per-stage 1-bit shift (Block 4 responsibility). Reused by both B4 (FFT core) and B5 (recombination).

### `fft_stage_controller`

Sequences 1024-point FFT across 10 stages:
- Generates even/odd address pairs based on stage, group, and butterfly index.
- Prefetches twiddle addresses 1 cycle ahead.
- Issues butterflies with dual write cycle (Z1 then Z2, FIX-4).
- Signals `stage_done` when all butterflies in a stage complete.

### `complex_fft_core`

Main FFT engine. FSM states: S_IDLE -> S_LOAD_DATA -> S_INIT_STAGE -> S_PROC_STAGE -> S_CHECK_STAGE -> S_OUTPUT_STREAM. Instantiates B3 modules internally. 6 critical fixes applied:
- FIX-1: `br_ready` deadlock
- FIX-2: off-by-one in load counter
- FIX-3: `wm_rd_data` undriven
- FIX-4: Z2 never written
- FIX-5: last sample not written (mux by signal, not state)
- FIX-6: output shifted by 1 bin (prefetch compensation)

Provides pass-through `tw_addr_recomb`/`tw_data_recomb` ports so B5 can access the recomb twiddle ROM without dual-instantiating it.

### `rfft_recombine`

Key RFFT-specific module. Receives 1024 complex FFT bins Z[k], computes real spectrum X[k]:

```
Xe[k] = (Z[k] + Z*[N-k]) / 2
Xo[k] = -j * (Z[k] - Z*[N-k]) / 2
X[k]  = Xe[k] + W_2048^k * Xo[k]
```

Reuses `butterfly_radix2` from B3 (Xe = E, Xo = O, W = tw). Outputs only even bins (k=0,2..1022 -> 512 values) for LCD display.

### `spectrum_buffer` (CDC)

Dual-clock ping-pong RAM bridging `clk_sys` (27 MHz, write from `rfft_recombine`) and `clk_pix` (40.5 MHz, read by `spectrum_draw`). Bank swap on `g_done` with 2FF synchronizer. First-frame gate keeps LCD black until valid data arrives.

### `spectrum_draw`

Renders on LCD:
- **Bars:** 512 columns × up to 384 px height. Magnitude = `(max+min)/2` (linear approx, error <12%). Height = `mag >> MAG_SHIFT` (shift=7).
- **X-axis:** 0–24 kHz, 3 kHz/div, numeric labels.
- **Y-axis:** Magnitude ticks every 64 px.
- **Color:** White bars on black background.

### `lcd_ctrl`

Standard 800×480 RGB LCD controller (from Sipeed example). Generates `lcd_clk`, `lcd_hsync`, `lcd_vsync`, `lcd_de`, pixel coordinates `lcd_xpos`/`lcd_ypos`. RGB output is 5-6-5 format (R[4:0], G[5:0], B[4:0]).

## Differences from Original Plan

| Planned | Implemented | Reason |
|---|---|---|
| ESP32 GPIO `q15_data`+`q15_clk` | UART 921600 bps | Single wire, standard ESP32 peripheral, simpler PCB |
| `rfft_top` | `rfft_scope_top` | Includes LCD drawer infrastructure |
| Separate `magnitude_calc` module | `max+min/2` inside `spectrum_draw` | Resource-efficient linear approximation, sufficient for visual display |
| 1025 bins output | 512 even bins output | Matches 512 LCD columns at 46.88 Hz/px |
| 50-100 MHz Fclk | 27 MHz board clock | Tang Primer 20K H11 oscillator (unchangeable) |
| All blocks independent | B3 instantiated inside B4 | Avoids dual ROM instantiation; recomb port passes through |
| Block 3 ROM: separate instances | Single dual-port `twiddle_rom` inside B4 | Recomb port passed through to B5 |
| `sample_buffer` as first module | `uart_rx` + `sample_fifo` + `sample_buffer` | UART requires framing/FIFO before sample buffer |
| Common Python golden only | `scripts/gen_e2e_vectors.py` + numpy golden | Unified E2E test vector generation |

## Testbench-First Verification (all PASS)

| # | Testbench | Result | Time |
|---|---|---|---|
| 1 | `tb_uart_rx` | PASS | <1s |
| 2 | `tb_pack` | PASS | <1s |
| 3 | `tb_e2e` (B1: UART->pack) | PASS | <1s |
| 4 | `tb_ram_buffer` | PASS | <1s |
| 5 | `tb_bit_reverse` | PASS | <1s |
| 6 | `tb_permutation` (N=8) | PASS | <1s |
| 7 | `tb_permutation_1024` | PASS | <1s |
| 8 | `tb_permutation_ready_pause` | PASS | <1s |
| 9 | `tb_block1_2_fusion` (B1+B2) | PASS | ~1s |
| 10 | `tb_complex_fft_core` (B4, detects X) | PASS | <1s |
| 11 | `tb_chain_b2b4recomb` (B2->B4->recomb) | PASS | ~1s |
| 12 | `tb_rfft_recombine` (512 bins vs golden, ±4 LSB) | PASS | <1s |
| 13 | `tb_rfft_scope_e2e` (UART->LCD) | PASS | ~2-3 min |

## Known Issues and Risks

| Issue | Severity | Status |
|---|---|---|
| Twiddle ROM init in Gowin synthesis (`$readmemh` path resolution) | High | Documented; `.mi` fallback available |
| CST for `rfft_block1_2.cst` originally used LCD pins — corrected | High | Fixed |
| UART pin `uart_rx` was at M11 (TX line) — corrected to T13 | High | Fixed |
| First frame garbage on LCD | Low | Fixed: `first_done` gate in `spectrum_buffer` |
| B4 saturation with input >0.5 FS | Low | Accepted; tone uses amp 0.5 |
| No backpressure UART->FIFO | Low | 506× margin at 27 MHz |
| PLL stubbed in simulation (CDC not verified) | Medium | Inherent sim limitation |
| E2E tolerance `white_near` ±2px | Low | Complemented by chain test bit-exact |

## Optimization Path

1. Reduce LUT and DSP use in butterflies (already optimal: 4 DSP per butterfly).
2. Tune scaling to avoid overflow while preserving SNR (done: amp 0.5, MAG_SHIFT=7).
3. Replace floating-point reference helpers with ROM-based fixed-point tables (done: `twiddle_rom.v`).
4. Minimize RAM ports and address conflicts (done: True Dual-Port working memory).
5. Pipeline long arithmetic paths if timing fails (not needed at 27 MHz).
