# final_debug/ — RFFT Scope HIL Debug Pipeline

Self-running Hardware-in-the-Loop testbench for the RFFT Scope FPGA pipeline.
No UART, no ESP32, no buttons — power on and the FPGA auto-cycles through
8 pre-computed test vectors (5 kHz sine + gaussian noise) displaying each
on the LCD for ~3 seconds before advancing.

```
                    dominio clk (27 MHz placa)
 debug_test_rom_player → B1 (FIFO+pack) → B2 (bit-reverse)
   → B4 complex_fft_core (B3: butterfly + twiddle ROM inside)
   → B5 rfft_recombine → B5 spectrum_buffer (escritura)
                    dominio clk_pix (40.5 MHz PLL)
 spectrum_buffer (lectura) → spectrum_draw → lcd_ctrl → LCD 800×480
```

No external MCU. The `debug_test_rom_player` replaces `uart_rx` entirely.

## Quick Start

```bash
# 1. Generate test vectors (requires numpy)
python3 scripts/gen_debug_vectors.py

# 2. Synthesize (requires Gowin EDA)
gw_sh final_debug/build_debug_rfft_scope.tcl

# 3. Flash
openFPGALoader -b tangprimer20k final_debug/debug_rfft_scope/impl/pnr/debug_rfft_scope.fs

# 4. Watch — no interaction needed
#    LCD cycles V0 → V1 → ... → V7 → V0 every ~24 seconds
```

## Synthesis Status (verified 2026-06-11)

Gowin EDA synthesis, place & route, and bitstream generation all pass:

| Resource | Used | Available | % |
|---|---|---|---|
| Logic (LUT+ALU) | 1,021 | 20,736 | 5% |
| Registers (FF) | 689 | 15,552 | 5% |
| BSRAM | 15 | 46 | 33% |
| DSP | 0.5 | 24 | 3% |
| rPLL | 1 | 4 | 25% |
| Bitstream | 7.2 MB | — | — |

### ROM Initialization (IMPORTANT)

The `twiddle_rom.v` and `debug_test_rom_player.v` use `$readmemh` for
initialization. GowinSynthesis >=1.9.8 supports `$readmemh` but **loading
large hex files can prevent BSRAM inference**, causing the synthesis to
fail with "number of DFF exceeds resource limit."

**Workaround used for this verified build:** the hex files are NOT copied
into the project directory. Gowin synthesizes the ROMs as zero-initialized
BSRAM (inference succeeds). The DSP count drops from ~4 to 0.5 because
zero twiddle factors simplify the butterfly to addition — the bitstream
is valid but the FFT output will be incorrect.

**To get correct FFT output on hardware**, use one of these methods:

1. **IP Catalog (recommended):** replace `twiddle_rom.v` and the `rom`
   array in `debug_test_rom_player.v` with BSRAM IP instances from the
   Gowin IP Catalog, loading content from the provided `.mi` files.
   
2. **Copy hex files into the project tree AFTER synthesis:** copy
   `src/block3/twiddles_*.hex` and `src/debug_hex/debug_vectors.hex`
   to `debug_rfft_scope/src/block3/` and `debug_rfft_scope/src/debug_hex/`
   respectively, then re-run only P&R (not synthesis):
   ```bash
   # After gw_sh completes successfully:
   cp src/block3/twiddles_fft.hex debug_rfft_scope/src/block3/
   cp src/block3/twiddles_recomb.hex debug_rfft_scope/src/block3/
   cp src/debug_hex/debug_vectors.hex debug_rfft_scope/src/debug_hex/
   # Re-open project in Gowin IDE and run P&R
   ```

## Test Vectors

| Vector | SNR | Description |
|---|---|---|
| V0 | inf dB | Clean 5 kHz sine, narrow peak |
| V1 | 41.4 dB | Tiny noise, bar slightly broader |
| V2 | 35.4 dB | Light noise |
| V3 | 29.1 dB | Moderate noise |
| V4 | 23.5 dB | Visible noise floor |
| V5 | 17.5 dB | High noise |
| V6 | 11.2 dB | Very noisy, broad peak |
| V7 | 5.2 dB | Near-white noise, wide bar |

All vectors use 5 kHz tone at amplitude 0.5 FS (avoids B4 saturation).
Sample rate: 48 kHz, 2048 samples per frame. Display shows 0–24 kHz
with the peak at column ~107 (5 kHz / 46.88 Hz/px ≈ 107).

## Simulation

```bash
cd final_debug

# Debug ROM player unit test
iverilog -g2012 -o tb/tb_debug_player.vvp \
    tb/tb_debug_player.v src/debug_test_rom_player.v && vvp tb/tb_debug_player.vvp

# Full pipeline check (compilation only, PLL is Gowin primitive)
# Use final/tb/ for full E2E with UART stimulus
```

## File Structure

| File | Purpose |
|---|---|
| `src/debug_test_rom_player.v` | **New.** ROM-based autonomous sample injector, auto-cycles 8 vectors |
| `src/debug_block1_i2s_top.v` | **Modified.** B1 top with ROM player instead of UART |
| `src/debug_rfft_scope_top.v` | **Modified.** Full pipeline top, no uart_rx port |
| `src/debug_rfft_scope.cst` | **New.** Pin constraints (no uart_rx, current_vector on spare GPIOs) |
| `src/block1/*.v` | Copied from `final/` (except `block1_i2s_top.v` which is replaced by debug variant) |
| `src/block2-5/*.v` | Copied from `final/` (identical). B5 files have optional `current_vector` overlay |
| `src/lcd/` | Copied from `final/` (identical) |
| `src/block3/` | Copied from `final/` (identical — twiddle ROMs + butterfly) |
| `src/debug_hex/` | Generated test vector files (`debug_vectors.hex`, metadata) |
| `scripts/gen_debug_vectors.py` | **New.** Python generator for test vectors |
| `tb/tb_debug_player.v` | **New.** Testbench for ROM player |
| `build_debug_rfft_scope.tcl` | **New.** Gowin build script |

## Differences from final/

| `final/` | `final_debug/` |
|---|---|
| UART input from ESP32 | ROM-based test vectors |
| `uart_rx` → `sample_fifo` | `debug_test_rom_player` → `sample_fifo` |
| `rfft_scope_top` with `uart_rx` port | `debug_rfft_scope_top` without UART |
| CSC with `uart_rx` pin | CSC with `current_vector[2:0]` monitor pins |
| External ESP32+MAX9814 required | Self-running, no external hardware |
| Manual test vector selection | Auto-cycles V0→V7 every ~3s |

## Regenerating Test Vectors

```bash
# Change amplitude, frequency, noise levels in the script:
python3 scripts/gen_debug_vectors.py

# Edit gen_debug_vectors.py to tune:
#   FS, F_TONE, N_SAMPLES, AMPLITUDE, NUM_VECTORS, NOISE_SIGMAS[]
#   Then re-run synthesis.
```

## LCD Overlay

The top-left corner shows "V0" through "V7" indicating the current test vector.
This is implemented in `src/block5/spectrum_draw.v` (modified copy with
`current_vector` input port and 5×7 font overlay).

## Pin Assignments (Tang Primer 20K Dock)

| Signal | Pin | Note |
|---|---|---|
| `clk` | H11 | Board oscillator 27 MHz |
| `rst_n` | T10 | Onboard button (active-low) |
| `fifo_overflow` | L16 | LED (should stay off) |
| `frame_dropped` | L14 | LED (should stay off) |
| `current_vector[2]` | N14 | Debug monitor pin |
| `current_vector[1]` | M11 | Debug monitor pin |
| `current_vector[0]` | R3 | Debug monitor pin |
| `uart_rx` | — | **Not connected** (T13 free) |
| LCD pins | (same as final/) | 800×480 RGB panel |

If `current_vector[*]` pins conflict with your Dock, remove those lines
from `debug_rfft_scope.cst` — the overlay still works on LCD.
