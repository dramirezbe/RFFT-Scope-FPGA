# Integration Rules — RFFT Pipeline

Rules and conventions that all five blocks must follow to ensure correct integration on the Tang Primer 20K (Gowin GW2A).

---

## 1. Global Parameters

| Parameter | Value | Description |
|---|---|---|
| Clock | `clk`, 50–100 MHz | Common to all blocks |
| Reset | `rst_n` | Active-low, asynchronous |
| Data format | Q15, 16-bit, two's complement | Range: [-1.0, +1.0 - 2⁻¹⁵] → [0x8000, 0x7FFF] |
| Handshake protocol | `valid` / `ready` | Single handshake format across all blocks |
| Global scale factor | 1/1024 | Applied across the full 10-stage FFT and matched in the Python golden model |

---

## 2. Signal Naming Conventions

| Convention | Example | Notes |
|---|---|---|
| Real / imaginary suffix | `complex_real`, `complex_imag` | Full word preferred; abbreviated `_r` / `_i` also accepted |
| Valid strobe | `_valid` | e.g. `br_valid`, `fft_valid`, `bin_valid` |
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
| **B1 → B2** | `complex_real[15:0]`, `complex_imag[15:0]`, `complex_valid`, `frame_start` | `valid` / `ready` |
| **B2 → B4** | `br_real[15:0]`, `br_imag[15:0]`, `br_valid`, `br_ready` | Standard `valid` / `ready` |
| **B4 → B3** | `e_real[15:0]`, `e_imag[15:0]`, `o_real[15:0]`, `o_imag[15:0]`, `tw_real[15:0]`, `tw_imag[15:0]`, `butterfly_en` | 1-cycle enable / done |
| **B3 → B4** | `z1_real[15:0]`, `z1_imag[15:0]`, `z2_real[15:0]`, `z2_imag[15:0]`, `butterfly_done` | 1-cycle enable / done |
| **B4 → B5** | `fft_real[15:0]`, `fft_imag[15:0]`, `fft_valid`, `fft_done` | `valid` / `done` |

### Block 3 Internal Connections

| Consumer | ROM Port | Address Bus | Data Bus |
|---|---|---|---|
| Block 4 (FFT core) | `tw_addr_fft[8:0]` | 9-bit, k = 0..511 | `tw_data_fft[31:0]` (Wk_1024) |
| Block 5 (Recomb) | `tw_addr_recomb[10:0]` | 11-bit, k = 0..1024 | `tw_data_recomb[31:0]` (Wk_2048) |

---

## 4. Handshake Protocol

All blocks must use the **same handshake format**: `valid` / `ready` with a registered output.

```
Producer asserts valid when data is stable.
Consumer asserts ready when it can accept data.
Transfer occurs when valid && ready are both high in the same cycle.
```

- **B1→B2** and **B2→B4**: full `valid` / `ready` handshake (AXI-stream–style backpressure).
- **B4→B3 (Butterfly)**: 1-cycle `butterfly_en` / `butterfly_done` pulse pair instead of `valid`/`ready`. No backpressure from the butterfly; Block 4 controls the pacing.
  - `butterfly_en` asserted in cycle T → `butterfly_done` asserted + `z1`/`z2` valid in cycle T+1.
- **B4→B5**: `fft_valid` + `fft_done`.

---

## 5. Reset Policy

- Signal: `rst_n`, **active-low**, **asynchronous**.
- Every module must include `rst_n` as an input port (even ROMs, for interface consistency).
- On reset: all outputs must be driven to 0.
- Simulation reset sequence: hold `rst_n = 0` for at least 3 clock cycles, then release to `1`.

---

## 6. Saturation Policy

**Every arithmetic operation** (multiplication, addition, subtraction) must saturate individually. The same saturation function must be used across all blocks.

### Saturation Range

| Value | Hex |
|---|---|
| Maximum positive | `0x7FFF` (+1.0 − 2⁻¹⁵) |
| Maximum negative | `0x8000` (−1.0) |

### Multiplication + Saturation Procedure

1. Multiply two Q15 operands → 32-bit intermediate product (Q30).
2. Arithmetic right-shift by 15 bits (preserving sign).
3. Saturate the result to [0x8000, 0x7FFF].
4. Produce a 16-bit Q15 output.

**Critical rule:** Saturation must be applied to the full 32-bit intermediate result **before** truncating to 16 bits. This prevents false saturation cases where the 32-bit value is within range but the truncated 16-bit value would appear to overflow.

### Per-Stage Shift

- The butterfly module itself does **NOT** apply any per-stage 1-bit shift.
- The 1-bit-per-stage shift is the responsibility of **Block 4** (the FFT controller), applied outside the butterfly before or after each stage as needed.

---

## 7. Latency Rules

| Module | Latency | Rule |
|---|---|---|
| `butterfly_radix2` | 1 cycle | `butterfly_en` at T → outputs valid + `butterfly_done` at T+1. Outputs hold value until next `butterfly_en`. |
| `twiddle_rom` | 1 cycle | BSRAM synchronous read. Address at T → data at T+1. Consumers **must prefetch addresses 1 cycle ahead**. |

### Twiddle ROM Data Extraction

```verilog
twiddle_rom rom_inst (
    .clk               (clk),
    .rst_n             (rst_n),
    .tw_addr_fft       (addr_prefetch),   // 1 cycle ahead
    .tw_data_fft       (tw_data_bus)
);
assign tw_real = tw_data_bus[31:16];   // upper 16 bits = real
assign tw_imag = tw_data_bus[15:0];    // lower 16 bits = imag
```

### Pipelining Option

If timing fails above 100 MHz, the butterfly can be pipelined to 2 cycles by inserting a register between the product and sum stages, delaying `butterfly_done` by one extra cycle. This must be coordinated with Block 4.

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
- Block 3's `butterfly_golden.py` provides the canonical `mul_q15`, `add_sat`, `sub_sat` implementations that all blocks should reference.

---

## 9. Verification Tolerances

| Module | Tolerance | Notes |
|---|---|---|
| Butterfly | ±2 LSB | 4 multiplies + 2 add/subs accumulate rounding errors |
| Twiddle ROM | ±1 LSB | Q15 quantization of sin/cos values |
| Full FFT (1024-point) | SNR > 40 dB | Measured against Python golden model |

---

## 10. Toolchain

| Tool | Use |
|---|---|
| Gowin EDA (≥ v1.9.8) | Synthesis, place & route, bitstream generation |
| Icarus Verilog | Simulation (note: ROMs are combinational in simulation; BSRAM latency is synthesis-only) |
| Python + NumPy | Golden model and test vector generation |
| `.mi` files | Memory initialization for Gowin synthesis (includes `#depth`, `#width` headers) |
| `.hex` files | Memory initialization for `$readmemh` in simulation (no headers) |
