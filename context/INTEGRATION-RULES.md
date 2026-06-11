# Integration Rules — RFFT Pipeline (actualizado con implementacion final/)

Rules and conventions that all five blocks follow for correct integration on the Tang Primer 20K (Gowin GW2A-LV18PG256C8/I7).

---

## 1. Global Parameters

| Parameter | Value | Description |
|---|---|---|
| Clock | `clk`, 27 MHz | Board oscillator (H11). TBs use 50 MHz for faster simulation. |
| Pixel clock | `clk_pix`, 40.5 MHz | PLL `pll_40m` (27 × 3 / 2). LCD 800×480. |
| Reset | `rst_n` | Active-low, asynchronous. Pull-up on T10 (`btn_n0`). |
| Data format | Q15, 16-bit, two's complement | Range: [-1.0, +1.0 - 2^-15] -> [0x8000, 0x7FFF] |
| Handshake protocol | `valid` / `ready` | Single handshake format across all blocks. B4→B3 uses 1-cycle `butterfly_en`/`done` instead. |
| Global scale factor | 1/1024 | Applied across the 10 FFT stages (`>>1` per stage by B4 stage controller). |
| UART baud rate | 921600 | 8N1, MSB first. Error ~2.3% at 27 MHz (acceptable). Adjustable via `CLK_FREQ`/`BAUD` top parameters. |
| UART frame format | `0xAA 0x55` + `LEN_HI LEN_LO` + 2048 samples | 16-bit Q15 samples, MSB first. Total payload: 4100 bytes/frame. |
| Sample rate | 48 kHz | ESP32 ADC sampling. Nyquist = 24 kHz. |

---

## 2. Signal Naming Conventions

| Convention | Example | Notes |
|---|---|---|
| Real / imaginary suffix | `complex_real`, `complex_imag` | Full word preferred; `_r` / `_i` also accepted |
| Valid strobe | `_valid` | e.g. `br_valid`, `fft_valid`, `complex_valid` |
| Ready / backpressure | `_ready` | e.g. `br_ready` |
| Enable / trigger | `_en` | e.g. `butterfly_en` |
| Done / completion | `_done` | e.g. `butterfly_done`, `fft_done` |
| Frame boundary | `frame_start` | Marks beginning of a new 2048-sample frame |
| Data bus width | `[15:0]` | All Q15 sample buses |
| Packed twiddle bus | `[31:0]` | `{real[15:0], imag[15:0]}` |

---

## 3. Inter-Block Signal Connections

| Connection | Signals | Handshake Type |
|---|---|---|
| **ESP32 -> B1** | `uart_rx` | UART 921600 8N1 (via T13) |
| **B1 -> B2** | `complex_real[15:0]`, `complex_imag[15:0]`, `complex_valid`, `frame_start` | Streaming (B2 accepts full frame unconditionally in WRITE state) |
| **B2 -> B4** | `br_real[15:0]`, `br_imag[15:0]`, `br_valid`, `br_ready` | Standard `valid` / `ready` |
| **B4 -> B3** | `e_real[15:0]`, `e_imag[15:0]`, `o_real[15:0]`, `o_imag[15:0]`, `tw_real[15:0]`, `tw_imag[15:0]`, `butterfly_en` | 1-cycle enable / done (B4 controls pacing) |
| **B3 -> B4** | `z1_real[15:0]`, `z1_imag[15:0]`, `z2_real[15:0]`, `z2_imag[15:0]`, `butterfly_done` | 1-cycle enable / done |
| **B4 -> B5 (data)** | `fft_real[15:0]`, `fft_imag[15:0]`, `fft_valid`, `fft_done` | `valid` / `done` (1024 complex bins Z[k]) |
| **B5 -> B4 -> B3 (twiddle)** | `tw_addr_recomb[10:0]` (B5 output, B4 pass-through) | B3 ROM: `tw_data_recomb[31:0]` (B3 output, B4 pass-through to B5). 1-cycle latency. |
| **B5 -> LCD** | `lcd_data[23:0]` | Pixel data in `clk_pix` domain, coordinates from `lcd_ctrl` |

### Block 3 Internal Connections (instantiated inside B4)

| Consumer | ROM Port | Address Bus | Data Bus | Note |
|---|---|---|---|---|
| Block 4 (FFT core) | `tw_addr_fft[8:0]` | 9-bit, k=0..511 | `tw_data_fft[31:0]` (Wk_1024) | Connected inside `complex_fft_core` |
| Block 5 (Recomb) | `tw_addr_recomb[10:0]` | 11-bit, k=0..1024 | `tw_data_recomb[31:0]` (Wk_2048) | Pass-through via B4 top ports |

---

## 4. Handshake Protocol

All blocks use the same handshake format.

```
Producer asserts valid when data is stable.
Consumer asserts ready when it can accept data.
Transfer occurs when valid && ready are both high in the same cycle.
```

- **B1->B2**: Streaming (no backpressure). B2 absorbs the full 1024-sample frame into RAM. B1 does not check `br_ready`. Safe because the consumer always catches up during the ~42.7 ms audio frame gap.
- **B2->B4**: Full `valid` / `ready` handshake. `br_ready` is held high during `S_LOAD_DATA`; drops on frame complete.
- **B4->B3 (Butterfly)**: 1-cycle `butterfly_en` / `butterfly_done` pulse pair. No backpressure from the butterfly; Block 4 controls the pacing.
  - `butterfly_en` asserted in cycle T -> `butterfly_done` asserted + `z1`/`z2` valid in cycle T+1.
- **B4->B5**: `fft_valid` + `fft_done`. B5 captures all 1024 values into internal RAM (`zmem`), then processes. No backpressure needed.
- **B5 (recomb) -> B5 (buffer)**: Streaming with gaps (5 cycles/bin). `spectrum_buffer` accepts any `g_valid` pattern.

---

## 5. Reset Policy

- Signal: `rst_n`, **active-low**, **asynchronous**.
- Every module must include `rst_n` as an input port.
- On reset: all outputs must be driven to 0.
- Simulation reset sequence: hold `rst_n = 0` for at least 3 clock cycles, then release to `1`.
- Board: `rst_n` on T10 (`btn_n0`), internal pull-up. Pull low to reset.

---

## 6. Saturation Policy

**Every arithmetic operation** (multiplication, addition, subtraction) must saturate individually.

### Saturation Range

| Value | Hex |
|---|---|
| Maximum positive | `0x7FFF` (+1.0 - 2^-15) |
| Maximum negative | `0x8000` (-1.0) |

### Multiplication + Saturation Procedure

1. Multiply two Q15 operands -> 32-bit intermediate product (Q30).
2. Arithmetic right-shift by 15 bits (preserving sign).
3. Saturate the result to [0x8000, 0x7FFF].
4. Produce a 16-bit Q15 output.

### Per-Stage Shift

- The butterfly module itself does **NOT** apply any per-stage 1-bit shift.
- The 1-bit-per-stage shift is the responsibility of **Block 4** (the FFT controller), applied outside the butterfly before or after each stage as needed.
- Total scaling after 10 stages: `/1024` (matches Python golden model `rfft(x)/1024`).

### Known Saturation Behavior (B4)

The butterfly saturates **before** the `>>1` per stage. With input > ~0.5 FS, stage 0 clips and the peak loses height (frequency stays correct). Test tone uses amplitude 0.5; `MAG_SHIFT=7` in the drawer. A very strong tone clips bar height but not position -- acceptable for a visual spectrometer.

---

## 7. Latency Rules

| Module | Latency | Rule |
|---|---|---|
| `butterfly_radix2` | 1 cycle | `butterfly_en` at T -> outputs valid + `butterfly_done` at T+1. Outputs hold value until next `butterfly_en`. |
| `twiddle_rom` | 1 cycle | BSRAM synchronous read. Address at T -> data at T+1. Consumers **must prefetch addresses 1 cycle ahead**. |
| `working_memory` (BSRAM) | 1 cycle | Same 1-cycle read latency. B4 compensates with prefetch in `S_OUTPUT_STREAM` (FIX-6). |
| `fft_stage_controller` | 5 cycles/butterfly | 2 reads + 1 butterfly + 1 write Z1 + 1 write Z2 (FIX-4). |
| `rfft_recombine` | 5 cycles/bin | SET -> WAIT(ram+rom) -> LATCH -> BF -> OUT. 512 bins × 5 cycles ~= 2560 cycles total. |
| `spectrum_buffer` | 1 cycle | BRAM read on `clk_pix` side. `spectrum_draw` compensates with `xq`/`yq` pipeline registers. |

### Twiddle ROM Data Extraction

```verilog
// Inside complex_fft_core (Block 4)
twiddle_rom u_twiddle_rom (
    .clk             (clk),
    .tw_addr_fft     (tw_addr_fft[8:0]),   // 9-bit, prefetched 1 cycle ahead
    .tw_data_fft     (tw_data_fft_w),      // {real[31:16], imag[15:0]}
    .tw_addr_recomb  (tw_addr_recomb),     // from B5, pass-through
    .tw_data_recomb  (tw_data_recomb)      // to B5, pass-through
);
// Butterfly connection:
butterfly_radix2 u_butterfly (
    .tw_real (tw_data_fft_w[31:16]),
    .tw_imag (tw_data_fft_w[15:0])
);
```

---

## 8. Common Python Golden Model

All blocks share the same golden reference:

```python
import numpy as np

def rfft_golden(x):
    """x: 2048 real samples (float). Returns 1025 unique bins."""
    return np.fft.rfft(x, n=2048) / 1024
```

- Block-specific Python scripts import from or replicate the same arithmetic as the golden model.
- Block 3's `butterfly_golden.py` provides the canonical `mul_q15`, `add_sat`, `sub_sat` implementations.
- E2E vectors are generated by `scripts/gen_e2e_vectors.py` with `AMP=0.5` and `MAG_SHIFT=7`.

---

## 9. Verification Tolerances

| Module | Tolerance | Notes |
|---|---|---|
| Butterfly | ±2 LSB | 4 multiplies + 2 add/subs accumulate rounding errors |
| Twiddle ROM | ±1 LSB | Q15 quantization of sin/cos values |
| Full FFT (1024-point) | SNR > 40 dB | Measured against Python golden model |
| Chain B2->B4->recomb | ±5 LSB | Bit-exact against numpy, detects X explicitly |
| RFFT recombine | ±4 LSB | 512 bins vs golden |
| E2E (UART->LCD) | white_near ±2px | Checks peak at correct frequency bin, 3 spurious frequencies |

---

## 10. Clock Domain Crossing (CDC)

The only clock domain crossing is at `spectrum_buffer`:

- **Write side:** `clk_sys` (27 MHz) -- Block 5 `rfft_recombine` writes spectrum bins.
- **Read side:** `clk_pix` (40.5 MHz) -- `spectrum_draw` reads bin magnitudes.
- **Mechanism:** Dual-clock ping-pong RAM. One bank written, one bank displayed. Bank swap on `g_done` with 2FF synchronizer from `clk_sys` to `clk_pix`.
- **First frame gate:** LCD stays black until `first_done` asserts (prevents garbage on power-up).

**Simulation limitation:** `pll_40m` is stubbed as a free-running oscillator in TBs. CDC timing is not verified in simulation.

---

## 11. Build and Toolchain

| Tool | Use |
|---|---|
| Gowin EDA (>= v1.9.8) | Synthesis, place & route, bitstream generation |
| Icarus Verilog 12.0 | Simulation |
| Python 3 + NumPy | Golden model and test vector generation |
| `scripts/gen_e2e_vectors.py` | Generates stimulus + golden for E2E TB |
| `build_rfft_scope.tcl` | Gowin Tcl build script for full pipeline |
| `build_block1_2.tcl` | Gowin Tcl build script for B1+B2 milestone |

### Build Commands

```bash
# Synthesis (full pipeline)
gw_sh final/build_rfft_scope.tcl

# Flash
openFPGALoader -b tangprimer20k final/rfft_scope/impl/pnr/rfft_scope.fs
```

### Simulation Commands

```bash
# B4 unit test
iverilog -g2012 -o tb_b4 tb/tb_complex_fft_core.v src/block4/*.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v && vvp tb_b4

# Chain B2->B4->recomb
iverilog -g2012 -o tb_chain tb/tb_chain_b2b4recomb.v src/block2/*.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v \
         src/block4/*.v src/block5/rfft_recombine.v && vvp tb_chain

# E2E complete
iverilog -g2012 -o tb_e2e_scope tb/tb_rfft_scope_e2e.v src/rfft_scope_top.v \
         src/block1/*.v src/block2/*.v src/block3/butterfly_radix2.v \
         src/block3/twiddle_rom.v src/block4/*.v src/block5/*.v src/lcd/lcd_ctrl.v
vvp tb_e2e_scope
```

### Memory Initialization

| File | Format | Used By |
|---|---|---|
| `twiddles_fft.hex` | `$readmemh` (512 lines, 32-bit hex) | Simulation (Icarus) |
| `twiddles_recomb.hex` | `$readmemh` (1025 lines, 32-bit hex) | Simulation (Icarus) |
| `twiddles_fft.mi` | Gowin memory init (with `#depth`, `#width` headers) | Synthesis fallback (IP Catalog) |
| `twiddles_recomb.mi` | Gowin memory init | Synthesis fallback (IP Catalog) |

GowinSynthesis >= 1.9.8 supports `$readmemh` for BSRAM init. If the tool reports "cannot open file", copy `.hex` files next to `.gprj` or use the `.mi` files via IP Catalog.
