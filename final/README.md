# final/ — RFFT Scope completo (Bloques 1–5)

Workspace de síntesis del pipeline RFFT completo sobre la Tang Primer 20K
(Gowin GW2A-LV18PG256C8/I7): audio por UART → FFT → espectro en LCD.

```
                       dominio clk (27 MHz placa)
ESP32/MAX9814 ─UART 921600─▶ B1 (uart+pack) ─complex_*─▶ B2 (bit-reverse)
  ─br_*⇄ B4 complex_fft_core (B3: butterfly + twiddle ROM) ─fft_*─▶
  B5 rfft_recombine ─g_*─▶ B5 spectrum_buffer (escritura)
                       dominio clk_pix (40.5 MHz PLL)
  spectrum_buffer (lectura) ─▶ spectrum_draw ─▶ lcd_ctrl ─▶ LCD 800×480
```

Top completo: [src/rfft_scope_top.v](src/rfft_scope_top.v) (`rfft_scope_top`).
Se conserva el hito intermedio B1+B2 (`rfft_block1_2_top` /
`build_block1_2.tcl`).

## Estructura

| Ruta | Contenido |
|---|---|
| `build_rfft_scope.tcl` | Build Gowin del pipeline completo (top `rfft_scope_top`) |
| `build_block1_2.tcl` | Build del hito B1+B2 (se mantiene) |
| `src/block1/` | UART RX, FIFO, ping-pong, packing (`CLK_FREQ`/`BAUD` parametrizables) |
| `src/block2/` | Bit-reverse (con los 3 fixes de integración B1→B2) |
| `src/block3/` | Butterfly + twiddle ROM **del submódulo** `examples/twiddle_butterfly` + tablas `.hex`/`.mi` |
| `src/block4/` | `complex_fft_core` + stage controller + working memory (con FIX-5/FIX-6, ver abajo) |
| `src/block5/` | **`rfft_recombine.v` (nuevo)** + spectrum_buffer/draw + drawer top |
| `src/lcd/` | `lcd_ctrl` + PLL 40.5 MHz (de `examples/sin_lcd`) |
| `src/rfft_scope.cst` | Pines: LCD (verificados) + `uart_rx`/`rst_n`/LEDs (placeholders, ¡ajustar!) |
| `scripts/gen_e2e_vectors.py` | Genera estímulo y golden bit-exacto (numpy) |
| `tb/` | TB unitarios + `tb_rfft_recombine.v` + `tb_rfft_scope_e2e.v` |

## La pieza nueva: recombinación RFFT (`src/block5/rfft_recombine.v`)

El B4 entrega la FFT compleja Z[k] de la señal empaquetada
`z[n] = x[2n] + j·x[2n+1]` — **no** es el espectro del audio. La
recombinación lo desempaqueta al espectro real:

```
Xe[k] = (Z[k] + Z*[N−k])/2          Xo[k] = −j·(Z[k] − Z*[N−k])/2
X[k]  = Xe[k] + W₂₀₄₈ᵏ · Xo[k]
```

- Usa el puerto pass-through `tw_addr/data_recomb` del B4 (tabla
  `twiddles_recomb`, 1025×32 b, ya prevista en el diseño del B3).
- **Reutiliza `butterfly_radix2` del Bloque 3**: `z1 = Xe + W·Xo = X[k]`
  (misma saturación Q15 del proyecto).
- Emite los **bins pares** (k=0,2,…,1022 → 512 salidas): así las 512
  columnas del LCD cubren 0–24 kHz y el eje estático del drawer
  (64 px = 3 kHz) queda exactamente calibrado (46.88 Hz/px).

## Bugs reales del B4 corregidos (en `src/block4/`)

El testbench original del B4 daba un **falso PASS**: su checker solo
comparaba `error > tolerancia`, y como en Verilog `X > 2` evalúa falso, los
valores indefinidos (memoria sin escribir) pasaban como OK. Eso ocultó dos
bugs reales que solo afloraron al integrar la cadena completa:

1. **[FIX-5] Última muestra no escrita:** el mux de escritura seleccionaba
   por `state == S_LOAD_DATA`, pero `load_wr_en` es registrado y la FSM ya
   había saltado a `S_INIT_STAGE` → la muestra 1023 nunca llegaba a la
   working memory y `mem[1023]` quedaba en X, propagándose a toda la FFT
   (LCD en negro/basura). El mux ahora selecciona por `load_wr_en`.
2. **[FIX-6] Salida corrida un bin:** `S_OUTPUT_STREAM` no compensaba la
   latencia de 1 ciclo de la BSRAM: `fft[k] = mem[k−1]`, el pico caía en el
   bin equivocado y `fft[0]` era basura. Ahora hay un ciclo de prefetch
   antes del primer `fft_valid`.

Ambos fixes están **verificados** por el TB unitario del B4
(`tb/tb_complex_fft_core.v`), que ahora **detecta los X explícitamente** y
usa un tono de amplitud 0.5 (no satura) comparado contra el golden numpy.

**Saturación (limitación conocida del B4, no un bug de integración):** la
mariposa satura *antes* del `>>1` por etapa, así que con entrada > ~0.5 FS
la etapa 0 recorta y el pico pierde altura (sin moverse de frecuencia). Por
eso el tono de prueba usa amplitud 0.5 y el drawer mantiene `MAG_SHIFT=7`.
En hardware, un tono muy fuerte recorta la **altura** de la barra pero no su
posición — aceptable para un espectrómetro visual.

> Los archivos de `examples/block4_coreFFT` quedaron intactos: los fixes
> viven en `final/src/block4/`. Vale la pena retroportarlos.

## Relojes

- `clk` placa = **27 MHz** (H11). El divisor UART se deriva del parámetro
  `CLK_FREQ` del top (27 MHz por defecto; los TB usan 50 MHz).
- `clk_pix` = 27 × 3 ÷ 2 = **40.5 MHz** (PLL `pll_40m`), LCD 800×480.
- CDC: RAM ping-pong de doble reloj del `spectrum_buffer` (banco publicado
  en `g_done`) + sincronizador 2FF. El display arranca en **negro** hasta el
  primer frame completo (gate `first_done`), evitando basura inicial en placa.

## Verificación (todo PASS con Icarus Verilog)

```bash
cd final
python3 scripts/gen_e2e_vectors.py          # requiere numpy

# B4 unitario: tono complejo k=64, detecta X, vs golden (±5 LSB)
iverilog -g2012 -o tb_b4 tb/tb_complex_fft_core.v src/block4/*.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v && vvp tb_b4

# Cadena de procesamiento B2->B4->recomb vs golden numpy (~1 s)
iverilog -g2012 -o tb_chain tb/tb_chain_b2b4recomb.v src/block2/*.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v \
         src/block4/*.v src/block5/rfft_recombine.v && vvp tb_chain

# Recombinación unitaria (512 bins vs golden, ±4 LSB)
iverilog -g2012 -o tb_rec tb/tb_rfft_recombine.v src/block5/rfft_recombine.v \
         src/block3/butterfly_radix2.v src/block3/twiddle_rom.v && vvp tb_rec

# E2E completo: UART (tono 3 kHz) -> ... -> pixeles del LCD (~2-3 min)
iverilog -g2012 -o tb_e2e_scope tb/tb_rfft_scope_e2e.v src/rfft_scope_top.v \
         src/block1/*.v src/block2/*.v src/block3/butterfly_radix2.v \
         src/block3/twiddle_rom.v src/block4/*.v src/block5/*.v src/lcd/lcd_ctrl.v
vvp tb_e2e_scope
# PASS: pico en la columna del bin golden (x≈128, etiqueta "3 kHz"), sin
# espurios; vuelca rfft_scope_frame.pgm para inspección visual
```

El E2E verifica la cadena completa contra un golden numpy bit-cercano:
tono de 3 kHz por UART → barra única bajo la etiqueta "3 kHz" del eje.
Los TB unitarios de B1/B2 y el de fusión B1+B2 siguen pasando.

## Compilar y flashear

```bash
gw_sh final/build_rfft_scope.tcl
openFPGALoader -b tangprimer20k final/rfft_scope/impl/pnr/rfft_scope.fs
```

**Pinout y cableado completos en [PINOUT_GUIDE.md](PINOUT_GUIDE.md)** (FPGA +
ESP32-WROOM-32 + MAX9814, todos los pines verificados contra el repo oficial
de Sipeed). Resumen: `clk=H11` (27 MHz), `uart_rx=T13` (← ESP32 GPIO17),
`rst_n=T10` (botón), LEDs `L16/L14`, LCD en su conector dedicado.

Notas de síntesis:
- Los `.hex` de twiddles se cargan con `$readmemh`. GowinSynthesis (≥1.9.8)
  **sí** soporta `$readmemh` para inicializar BSRAM (ver `twiddle_rom.v`); si
  no resuelve la ruta, copiar los `.hex` junto al `.gprj` o usar los `.mi`
  (en `src/block3/`) vía IP de BSRAM.
- Salidas de build (`**/impl/`, `*.gprj.user`) están git-ignoradas.

## Eje del display

- **X:** frecuencia, 0–24 kHz, 3 kHz/división (fs = 48 kHz del ESP32,
  2048 muestras reales → Nyquist 24 kHz), etiquetas en kHz.
- **Y:** magnitud lineal `max+min/2` (aprox de |X|, error < 12 %),
  1 px = 128 LSB (`MAG_SHIFT=7`). El tono de prueba (amp 0.5) mide ≈127 px
  de los 384 disponibles.
