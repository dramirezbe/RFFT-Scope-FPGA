# Diagrams

## General Diagram — Block-Level Interconnections (implementación final/)

```mermaid
flowchart LR
    subgraph PHYS[Physical Front-End]
        mic[MAX9814 Mic] --> esp[ESP32-WROOM-32\nADC1_0 + Q15\n48 kHz]
    end

    subgraph B1[Block 1 — Front-End & Packing]
        uart[uart_rx\n921600 bps] --> fifo[sample_fifo]
        fifo --> buf[sample_buffer\nping-pong]
        buf --> pack[pack_real_to_complex]
    end

    subgraph B2[Block 2 — Memory & Bit-Reverse]
        ctrl[permutation_controller] --> ram[dual_port_ram_buffer]
        br[bit_reverse] --> ctrl
    end

    subgraph B3[Block 3 — Math Unit & Twiddle ROM]
        tfft[twiddle_rom\nFFT: Wk_1024 512×32]
        trec[twiddle_rom\nRecomb: Wk_2048 1025×32]
        bfly[butterfly_radix2\n4 DSP]
    end

    subgraph B4[Block 4 — Complex FFT Core Controller]
        wmem[working_memory\nping-pong RAM\n2×1024×32] --> core[complex_fft_core\nFSM 10 stages DIT]
        stage[fft_stage_controller] --> core
    end

    subgraph B5[Block 5 — RFFT Post-Processing & LCD Drawer]
        recomb[rfft_recombine\nZ→X real, 512 bins] --> sbuf[spectrum_buffer\nCDC ping-pong]
        sbuf --> sdraw[spectrum_draw\nbars + axes]
    end

    subgraph LCD[LCD 800×480]
        ctrl[lcd_ctrl] --> panel[RGB Panel]
        pll[pll_40m\n27→40.5 MHz] --> ctrl
    end

    PHYS -->|"UART 921600\nGPIO17→T13"| B1
    B1 -->|"complex_real[15:0]\ncomplex_imag[15:0]\ncomplex_valid, frame_start"| B2
    B2 -->|"br_real[15:0]\nbr_imag[15:0]\nbr_valid, br_ready"| B4
    B4 <-->|"e_r/i, o_r/i, tw_r/i\nbutterfly_en"| B3
    B3 -->|"z1_r/i, z2_r/i\nbutterfly_done"| B4
    B4 -->|"fft_real[15:0]\nfft_imag[15:0]\nfft_valid, fft_done"| B5
    B4 --->|"tw_addr_recomb[10:0]\ntw_data_recomb[31:0]\n(pass-through)"| B5
    B5 -->|"lcd_data[23:0]"| LCD
    LCD -->|"lcd_xpos/ypos[11:0]"| B5
```

### Architecture Notes

1. **UART input** replaces the original GPIO `q15_data`/`q15_clk` toggle protocol. ESP32 streams frames at 921600 bps with header `0xAA 0x55` + length + 2048 Q15 samples.
2. **B3 is instantiated inside B4** (`complex_fft_core`). The recomb twiddle port passes through B4 to B5 — no separate ROM instantiation.
3. **Two clock domains:** `clk` (27 MHz, H11) for datapath; `clk_pix` (40.5 MHz, PLL) for LCD. CDC via dual-clock ping-pong RAM in `spectrum_buffer`.
4. **Recombination** reuses `butterfly_radix2` from B3. Output is decimated: only even bins (k=0,2..1022 → 512 values).
5. **Magnitude** is linear approximation (`max+min/2`, not `sqrt`) inside `spectrum_draw`.

---

## Clock Domain Diagram

```
             clk (27 MHz, H11 osc)          clk_pix (40.5 MHz, pll_40m)
  ┌─────────────────────────────┐     ┌──────────────────────────────┐
  │  B1 (UART+FIFO+Pack)        │     │                              │
  │  B2 (Bit-Reverse)           │     │  spectrum_buffer (read port) │
  │  B4 (FFT Core + B3 inside)  │     │  spectrum_draw               │
  │  B5 rfft_recombine          │     │  lcd_ctrl                    │
  │  spectrum_buffer (write)    │     │  LCD Panel (800×480)         │
  └──────────────┬──────────────┘     └──────────────┬───────────────┘
                 │                                   │
                 └── spectrum_buffer (CDC) ──────────┘
                    dual-clock ping-pong RAM
                    bank published on g_done
                    2FF synchronizer
```

---

## Data Flow (per frame, 2048 real samples)

| Step | Latency | Output |
|---|---|---|
| 1. ESP32 sends 2048 Q15 samples over UART 921600 | ~42.7 ms (48 kHz) | `uart_rx` → `sample_fifo` |
| 2. B1 packs into 1024 complex pairs | ~1024 cycles | `complex_real/imag` |
| 3. B2 writes to RAM in natural order, reads in bit-reverse | ~2048 cycles | `br_real/imag` |
| 4. B4 loads into working memory, runs 10 stages | ~5120 butterfly ops | `fft_real/imag` Z[k] |
| 5. B5 recomb: Z[k] → X[k] real bins | ~5 cycles/bin × 512 | `g_real/imag` (512 bins) |
| 6. B5 draws on LCD via `spectrum_buffer` CDC | 1 frame (40.5 MHz) | RGB pixels on LCD |

Total digital latency: negligible vs 42.7 ms audio frame time.

---

### Legend

| Block | Owner | Function |
|---|---|---|
| Block 1 | Developer 1 | UART capture (ESP32/MAX9814), FIFO, Q15 packing (2048 real → 1024 complex) |
| Block 2 | Developer 2 | Bit-reverse reordering, dual-port RAM buffer |
| Block 3 | Developer 3 | Twiddle ROM (Wk_1024 + Wk_2048), radix-2 butterfly (4 DSP, saturating Q15) |
| Block 4 | Developer 4 | 10-stage DIT complex FFT core, instantiates B3 internally, ping-pong working memory |
| Block 5 | Developer 5 | RFFT recombination (1024 complex → 512 real bins), CDC spectrum buffer, LCD drawing with static axes |
