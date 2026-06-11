# AGENTS.md — RFFT Scope FPGA

## Project map

| Dir | Purpose |
|---|---|
| `final/` | Production pipeline: UART (ESP32/MAX9814) → FFT → LCD |
| `final_debug/` | HIL debug: ROM-based self-running test vectors, no external HW |
| `context/` | Design docs, integration rules, block assignment specs |
| `examples/` | Reference designs (Sipeed sin_lcd, Block1_MAX9814, etc.) |

Top modules: `final/src/rfft_scope_top.v` (UART) and `final_debug/src/debug_rfft_scope_top.v` (HIL).

## Build

### gw_sh alias

```bash
source ~/.zshrc   # gw_sh alias is defined in zshrc
gw_sh final_debug/build_debug_rfft_scope.tcl
```

The alias runs `/home/javastral/GIT/UNAL/GowinResearchDebian13/deploy/gw_sh_run.sh` which sets LD_LIBRARY_PATH + QT_OPENGL=software before executing Gowin IDE's gw_sh.

### Simulation (Icarus Verilog)

```bash
cd final
# B4 unit test
iverilog -g2012 -o tb_b4 tb/tb_complex_fft_core.v src/block4/*.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v && vvp tb_b4

# E2E complete (2-3 min)
python3 scripts/gen_e2e_vectors.py
iverilog -g2012 -o tb_e2e_scope tb/tb_rfft_scope_e2e.v src/rfft_scope_top.v \
         src/block1/*.v src/block2/*.v src/block3/butterfly_radix2.v \
         src/block3/twiddle_rom.v src/block4/*.v src/block5/*.v src/lcd/lcd_ctrl.v
vvp tb_e2e_scope
```

Run iverilog/vvp from `final/` or `final_debug/` to resolve `$readmemh` relative paths.

### Flash

```bash
openFPGALoader -b tangprimer20k final_debug/debug_rfft_scope/impl/pnr/debug_rfft_scope.fs
```

## BSRAM inference (critical gotcha)

Gowin EDA maps memory to BSRAM only when ALL of these hold:

1. **`(* ram_style = "block" *)`** attribute on the reg array
2. **Synchronous (registered) read** — `always @(posedge clk) data <= mem[addr]`, NOT combinational `assign` or `always @(*)`
3. **Hex files accessible** — `$readmemh` path must resolve. Gowin tries (1) project dir, then (2) .v file dir. Copy `.hex` files into the project tree before synthesis.

**DO NOT use pROM IP** — it needs init data via IP generator GUI (not portable via `defparam`). The `$readmemh` + `ram_style` + synchronous read pattern works for all ROM sizes.

**Combinational reads cause LUT4/DFF inference** and will fail with resource limit errors on large arrays (>2K entries).

**Large hex files present during synthesis can trigger DFF fallback** even with ram_style. If this happens, split the ROM into smaller chunks (< 4096 entries each).

## Pipeline latency bug pattern

When adding a new synchronous ROM read to a state machine: the data arrives **1 cycle after** the address is set. The FSM must NOT emit `rom_data` on the same cycle it sets the address. Use a prefetch state:

```
S0: set addr=0, frame_start  → S1
S1: no output (prefetch)      → S2
S2: emit rom_data (from prev addr), advance addr → S2 (loop)
```

## CST pinout

Banks 1 and 3 on the Tang Primer 20K Dock are **1.8V**. Use `IO_TYPE=LVCMOS18` for pins in those banks (T10 rst_n, L16/L14 LEDs, N14/M11/R3 GPIO). LCD pins use `IO_TYPE=LVCMOS18` (the LCD connector bank is also 1.8V on this board variant).

## Test vector generation

```bash
python3 final_debug/scripts/gen_debug_vectors.py
```

Outputs `src/debug_hex/debug_vectors.hex` (concatenated, for `$readmemh`) and `.mi` (backup, not used).

## Known project issues

- **Twiddle ROM swept in optimization**: warning is benign when hex files ARE present (the ROM is used by DSP). If hex files are missing, twiddle_rom gets swept and DSP drops to 0.5 (FFT output incorrect).
- **bit_reverse swept**: `permutation_controller` computes addresses internally; the standalone `bit_reverse` module is unused but kept for documentation.
- **PLL stubbed in simulation**: `pll_40m` is a Gowin rPLL primitive. TBs use a free-running oscillator stub. CDC timing not verified in sim.
- **`$readmemh` path**: GowinSynthesis >=1.9.8 supports it, but resolve order is project dir → .v dir. Always copy hex files into project tree in build script.

## File ownership

- `final/src/block4/complex_fft_core.v` instantiates B3 internally (twiddle_rom + butterfly_radix2). The recomb twiddle port passes through to B5. Do NOT change the instantiation without coordinating B3/B5.
- `final/src/block5/spectrum_buffer.v` handles the CDC boundary (clk → clk_pix) via dual-clock ping-pong RAM + 2FF sync. Do not add combinational paths between the two clock domains.
- `final/src/block1/uart_rx.v` is ONLY for production (ESP32 input). The debug variant uses `debug_test_rom_player.v` which has the same output interface (sample_valid, sample_out, frame_start).
