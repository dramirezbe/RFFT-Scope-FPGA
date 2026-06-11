# RFFT Pipeline — Block Assignments (actualizado con implementacion final/)

The design is split into five blocks, each with its Verilog modules, interfaces, testbenches, and verification scripts. A common Python golden model (`rfft_golden.py`) using `numpy.fft.rfft(x, n=2048) / 1024` provides the global scaling reference.

Two clock domains: `clk` (27 MHz, system) and `clk_pix` (40.5 MHz PLL, LCD). CDC is handled by dual-clock ping-pong RAM in `spectrum_buffer`.

---

## Block 1 — Front-End, Packing and Q15

**Owner:** Developer 1

### Physical Front-End

A **MAX9814** electret microphone module with automatic gain control feeds an **ESP32-WROOM-32** that performs ADC sampling (GPIO36/ADC1_0) and sends Q15 samples over UART to the FPGA at 921600 bps, 8N1.

| GPIO ESP32 | Signal | Description |
|---|---|---|
| GPIO17 (U2_TXD) | `uart_rx` | UART TX → FPGA pin T13 |
| GPIO36 (ADC1_0) | — | MAX9814 OUT (analog input) |

**UART frame format:** `0xAA 0x55` + `LEN_HI LEN_LO` (big-endian, 2048) + 2048 Q15 samples of 16 bits each, MSB first, at 48 kHz sample rate. This is decoded by `uart_rx.v`.

### Verilog Modules

| Module | Function |
|---|---|
| `uart_rx` | UART receiver, 921600 baud. Decodes frame header + 2048 Q15 samples, MSB first. Clock divider derived from `CLK_FREQ`/`BAUD` parameters. |
| `sample_fifo` | 64-deep FIFO decoupling UART receiver from the buffer. Asserts `fifo_overflow` if full when a new sample arrives. |
| `sample_buffer` | Ping-pong buffer capturing 2048 real Q15 samples from the FIFO. Generates `frame_done` and `frame_start`. |
| `pack_real_to_complex` | Converts 2048 real samples into 1024 complex pairs: `z[m] = x[2m] + j * x[2m+1]`. |
| `block1_top` | Integrates `sample_fifo` + `sample_buffer` + `pack_real_to_complex`. |
| `block1_i2s_top` | Top wrapper: instantiates `uart_rx` + `block1_top`. Preserves the `i2s_*` port names from the original plan for backward compatibility. |

### Input Interface (top-level pins)

| Signal | Description |
|---|---|
| `clk` | System clock, 27 MHz (Tang Primer 20K H11) |
| `rst_n` | Active-low reset (T10, onboard button) |
| `uart_rx` | UART RX from ESP32 GPIO17 (T13) |

### Output Interface (to Block 2)

| Signal | Description |
|---|---|
| `complex_real[15:0]`, `complex_imag[15:0]` | Complex pair in Q15 |
| `complex_valid` | Valid strobe for each complex pair (1024 per frame) |
| `frame_start` | Marks the first valid sample of a new frame |
| `fifo_overflow` | Status: FIFO overflow occurred (L16 LED) |
| `frame_dropped` | Status: frame dropped due to buffer conflict (L14 LED) |

### Testbenches and Scripts

| File | Description |
|---|---|
| `tb_uart_rx.v` | UART receiver unit test (header + payload framing) |
| `tb_pack.v` | Verifies complex packing formula |
| `tb_e2e.v` | End-to-end B1: UART stimulus → complex output |
| `scripts/gen_e2e_vectors.py` | Generates stimulus and golden numpy vectors |

---

## Block 2 — Memory and Bit-Reverse Reordering

**Owner:** Developer 2

### Verilog Modules

| Module | Function |
|---|---|
| `bit_reverse` | Computes bit-reversed addresses for indices 0..1023 (10 bits). |
| `dual_port_ram_buffer` | Stores 1024 complex words in natural order and reads them back in bit-reversed order. |
| `permutation_controller` | FSM managing write/read sequencing of the permutation buffer. Supports `br_ready` backpressure from Block 4. |
| `block2_memory_bitreverse_top` | Top wrapper instantiated by `rfft_scope_top`. |

### Input Interface (from Block 1)

| Signal | Description |
|---|---|
| `complex_real[15:0]`, `complex_imag[15:0]` | Complex data from Block 1 |
| `complex_valid`, `frame_start` | Handshake from Block 1 |

### Output Interface (to Block 4 — FFT Core)

| Signal | Description |
|---|---|
| `br_real[15:0]`, `br_imag[15:0]` | Data in bit-reversed order |
| `br_valid` | Pulse per complex word (1024 per frame) |
| `br_ready` | Handshake from Block 4 (prevents data overwrite) |

### Testbenches

| File | Description |
|---|---|
| `tb_bit_reverse.v` | Bit-reverse address check (N=8, 16, 1024) |
| `tb_ram_buffer.v` | Sequential write + bit-reversed read vs Python |
| `tb_permutation.v` | FSM verification (N=8) |
| `tb_permutation_1024.v` | FSM verification (N=1024) |
| `tb_permutation_ready_pause.v` | Backpressure corner cases |
| `tb_block1_2_fusion.v` | B1+B2 integration test |

---

## Block 3 — Math Unit and Twiddle ROM

**Owner:** Developer 3

### Verilog Modules

| Module | Function |
|---|---|
| `twiddle_rom` | Dual synchronous ROM: 512 entries × 32 bits (FFT: Wk_1024) + 1025 entries × 32 bits (Recomb: Wk_2048). Each word = `{real[15:0], imag[15:0]}` in Q15. 1-cycle read latency (BSRAM). Initialized via `$readmemh` from `.hex` files; `.mi` files available for Gowin IP Catalog fallback. |
| `butterfly_radix2` | Complex butterfly using 4 DSP multipliers. 1-cycle latency. Applies saturation to 0x7FFF/0x8000. Does NOT apply per-stage shift (that is Block 4's responsibility). |

### ROM Ports

| Port | Consumer | Size | Address |
|---|---|---|---|
| `tw_addr_fft[8:0]` / `tw_data_fft[31:0]` | Block 4 (FFT core) | 512×32 | 9-bit, k=0..511 |
| `tw_addr_recomb[10:0]` / `tw_data_recomb[31:0]` | Block 5 (recombination) | 1025×32 | 11-bit, k=0..1024 |

**Important:** `twiddle_rom` is instantiated **inside** `complex_fft_core` (Block 4). The `tw_addr_recomb` / `tw_data_recomb` port passes through Block 4 to Block 5 to avoid dual instantiation of the same ROM.

### Butterfly Interface (connected by Block 4)

| Input | Output |
|---|---|
| `e_real/imag`, `o_real/imag` (operands) | `z1_real/imag` (E + W*O) |
| `tw_real/imag` (twiddle factor) | `z2_real/imag` (E - W*O) |
| `butterfly_en` (1-cycle pulse) | `butterfly_done` (T+1) |

### Testbenches

| File | Description |
|---|---|
| `gen_twiddles.py` | Generates Wk_1024 and Wk_2048 tables in Q15; produces `.mi` and `.hex` files. |
| `tb_butterfly.v` | Q15 output vs Python model (multiply-and-shift routine). |

---

## Block 4 — Complex FFT Core Controller

**Owner:** Developer 4

### Verilog Modules

| Module | Function |
|---|---|
| `complex_fft_core` | Main FSM (S_IDLE → S_LOAD_DATA → S_INIT_STAGE → S_PROC_STAGE → S_CHECK_STAGE → S_OUTPUT_STREAM) iterating 10 radix-2 DIT stages. Instantiates `twiddle_rom`, `butterfly_radix2`, `fft_stage_controller`, and `working_memory` internally. |
| `fft_stage_controller` | Generates read addresses, strides, and twiddle indices per stage. Controls butterfly sequencing (including a 2-cycle write: Z1 then Z2). |
| `working_memory` | Two dual-port RAM banks (True Dual-Port) for ping-pong buffering between stages. Each bank: 1024 × 32 bits. |

### Input Interface (from Block 2)

| Signal | Description |
|---|---|
| `br_real[15:0]`, `br_imag[15:0]` | Bit-reversed data |
| `br_valid` | Data valid |
| `br_ready` | Ready for data (held high during S_LOAD_DATA; drops on frame complete) |

### Output Interface (to Block 5)

| Signal | Description |
|---|---|
| `fft_real[15:0]`, `fft_imag[15:0]` | Complex spectrum Z[k], scaled by 1/1024 (>>1 per stage) |
| `fft_valid` | Pulse when each bin is ready (1024 total) |
| `fft_done` | End of frame |
| `tw_addr_recomb[10:0]` | Pass-through from Block 5 to internal `twiddle_rom` |
| `tw_data_recomb[31:0]` | Pass-through from internal `twiddle_rom` to Block 5 |

### Critical Fixes Applied (FIX-1 to FIX-6)

| Fix | Problem | Resolution |
|---|---|---|
| FIX-1 | Deadlock: `br_ready` dropped in S_IDLE, never re-raised | `br_ready=1` in S_IDLE and S_LOAD_DATA; drops only on frame complete |
| FIX-2 | Off-by-one: data 0 overwritten by data 1 | First sample captured in S_IDLE at addr=0; S_LOAD_DATA starts at cnt=1 |
| FIX-3 | `wm_rd_data` undriven (X on output) | Added assign `wm_rd_data = sc_rd_data_e` |
| FIX-4 | `z2` never written to memory | Added second write cycle (ST_T2_Z2) in stage controller |
| FIX-5 | Last sample (addr 1023) not written | Mux selects by `load_wr_en` signal, not FSM state |
| FIX-6 | Output shifted by 1 bin | Prefetch cycle before first `fft_valid` to compensate BSRAM 1-cycle latency |

### Testbenches

| File | Description |
|---|---|
| `tb_complex_fft_core.v` | B4 unit test: complex tone k=64, detects X, vs golden numpy (±5 LSB) |
| `tb_chain_b2b4recomb.v` | Chain B2→B4→recomb vs golden numpy (bit-exact) |

---

## Block 5 — RFFT Post-Processing, Spectrum Buffer, and LCD Drawing

**Owner:** Developer 5

### Verilog Modules

| Module | Function |
|---|---|
| `rfft_recombine` | Implements recombination: Z[k] → X[k] = Xe[k] + W_2048^k * Xo[k]. Reuses `butterfly_radix2` from Block 3. Outputs only even bins (k=0,2..1022 → 512 values) for LCD display (46.88 Hz/px, 0–24 kHz). |
| `spectrum_buffer` | Dual-clock ping-pong RAM: writes spectrum bins in `clk_sys` domain, publishes completed bank to `clk_pix` domain via 2FF synchronizer. Gates `first_done` to keep LCD black until first valid frame. |
| `spectrum_draw` | Renders spectrum bars + static axes (X: frequency in kHz, Y: magnitude) from `spectrum_buffer` data. Magnitude approximated as `max+min/2` (error <12%). Uses `MAG_SHIFT=7` for bar height scaling. |
| `block5_lcd_drawer` | Top wrapper integrating `spectrum_buffer` + `spectrum_draw`. CDC boundary between `clk_sys` and `clk_pix` domains. |

### Input Interface (from Block 4)

| Signal | Description |
|---|---|
| `fft_real[15:0]`, `fft_imag[15:0]` | FFT output (from `rfft_recombine` input stage) |
| `fft_valid`, `fft_done` | Handshake from Block 4 |
| `tw_addr_recomb[10:0]` | Drives recomb twiddle port (→ B4 → B3 ROM) |
| `tw_data_recomb[31:0]` | Receives Wk_2048 from ROM (via B4 pass-through) |

### Output Interface (to LCD controller)

| Signal | Description |
|---|---|
| `lcd_data[23:0]` | RGB pixel (R[7:3], G[7:2], B[7:3] → 5-6-5 format) |
| `lcd_xpos[11:0]`, `lcd_ypos[11:0]` | Pixel coordinates from `lcd_ctrl` |

### Display Layout

- **X-axis:** 0–24 kHz, 3 kHz/division (fs=48 kHz, Nyquist=24 kHz). 512 columns at 46.88 Hz/px.
- **Y-axis:** Linear magnitude, 384 px max bar height. 1 px = 128 LSB (MAG_SHIFT=7).
- **Eje estatico:** ticks and numeric labels in kHz on X, magnitude ticks on Y.

### Testbenches

| File | Description |
|---|---|
| `tb_rfft_recombine.v` | Recombination unit test (512 bins vs golden, ±4 LSB) |
| `tb_rfft_scope_e2e.v` | E2E: UART tone (3 kHz) → pixels on LCD, checked against golden numpy. Dumps `rfft_scope_frame.pgm` (800×480, 771 KB). |

---

## Top-Level Integration

| Module | File | Description |
|---|---|---|
| `rfft_scope_top` | `src/rfft_scope_top.v` | Full pipeline top: instantiates B1→B2→B4→B5a(recomb)→B5b(drawer) + `lcd_ctrl` + `pll_40m`. Parametrizable `CLK_FREQ` and `BAUD`. |
| `rfft_block1_2_top` | `src/rfft_block1_2_top.v` | Milestone: B1+B2 fusion only (standalone bring-up). |

### Build Scripts

| Script | Target | Output |
|---|---|---|
| `build_rfft_scope.tcl` | Full pipeline | `rfft_scope/impl/pnr/rfft_scope.fs` |
| `build_block1_2.tcl` | B1+B2 milestone | `block1_2_fusion/impl/pnr/block1_2_fusion.fs` |

### Clock Domains

| Domain | Frequency | Source | Modules |
|---|---|---|---|
| `clk` | 27 MHz | H11 (board oscillator) | B1, B2, B3, B4, B5 `rfft_recombine`, `spectrum_buffer` (write) |
| `clk_pix` | 40.5 MHz | `pll_40m` (27 × 3 / 2) | `spectrum_buffer` (read), `spectrum_draw`, `lcd_ctrl` |

### Pin Assignments (Tang Primer 20K Dock)

See `final/PINOUT_GUIDE.md` for full wiring diagram.
