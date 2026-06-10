# Block5_LCD_drawer — Espectro RFFT en LCD (blanco y negro)

Bloque 5 del pipeline: toma el buffer de salida del **Bloque 4**
(`complex_fft_core`: `fft_real/imag`, `fft_valid`, `fft_done`) y dibuja el
espectro en el LCD RGB 800×480 del Tang Primer 20K Dock, reutilizando el
`lcd_ctrl` + PLL 40 MHz del ejemplo `examples/sin_lcd`.

```
Bloque 4 ──fft_*──▶ spectrum_buffer ──mag──▶ spectrum_draw ──▶ lcd_ctrl ──▶ LCD
           clk_sys   (|·| + ping-pong RAM      clk_pix          800x480@60
                      de doble reloj)
```

Render (un frame del testbench, picos sintéticos en 3, 9 y 16.5 kHz):

- Barras blancas sobre fondo negro, 1 px por bin, 512 bins.
- **Eje X estático: frecuencia en kHz** — ticks y etiquetas numéricas
  `0 3 6 9 12 15 18 21 24` (cada 64 px = 3 kHz, asumiendo fs = 48 kHz como
  muestrea el ESP32 del Bloque 1; 2048 reales → Nyquist 24 kHz).
- **Eje Y estático: magnitud** lineal — ticks cada 64 px (= 8192 LSB de
  magnitud; 1 px = 128 LSB).

## Estructura

| Ruta | Contenido |
|---|---|
| `src/spectrum_buffer.v` | Captura el stream del B4, magnitud aprox `max+min/2` (sin sqrt, error <12 %), RAM ping-pong de doble reloj (CDC clk_sys→clk_pix, sin tearing: el banco se publica en `fft_done`) |
| `src/spectrum_draw.v` | Por pixel (xpos,ypos): barras + ejes + ticks + etiquetas (fuente 5×7 de dígitos) |
| `src/block5_lcd_drawer.v` | Núcleo integrable del Bloque 5 (buffer + draw) |
| `src/fft_stim_gen.v` | Solo demo: emula frames del Bloque 4 con 3 picos |
| `src/top.v` | Top de demo: PLL + lcd_ctrl + stim + Bloque 5 |
| `src/lcd_ctrl.v`, `src/gowin_rpll/` | Copiados de `examples/sin_lcd` |
| `src/block5_lcd.cst` | Pines (idénticos a `sin_rgb.cst`: LCD + clk H11) |
| `block5_lcd.tcl` | Build Gowin EDA (`gw_sh examples/Block5_LCD_drawer/block5_lcd.tcl`) |
| `tb/tb_block5_lcd.v` | TB auto-verificado + volcado de imagen PGM |

## Simular

```bash
cd examples/Block5_LCD_drawer
iverilog -g2012 -o tb_b5 tb/tb_block5_lcd.v src/block5_lcd_drawer.v \
         src/spectrum_buffer.v src/spectrum_draw.v src/lcd_ctrl.v
vvp tb_b5
# Esperado: "TB BLOCK5: PASS (ejes, barras, ticks y etiquetas OK)"
# Genera block5_frame.pgm (frame completo 800x480, abrir con un visor)
```

El TB inyecta un frame estilo Bloque 4, escanea un frame completo del LCD y
verifica: ejes en su sitio, altura de las 3 barras (`mag >> 7` px), ticks y
presencia de etiquetas; además vuelca la imagen a `block5_frame.pgm`.

## Compilar y flashear (demo standalone)

```bash
gw_sh examples/Block5_LCD_drawer/block5_lcd.tcl
openFPGALoader -b tangprimer20k examples/Block5_LCD_drawer/block5_lcd/impl/pnr/block5_lcd.fs
```

Muestra el espectro sintético del `fft_stim_gen` (picos en 3/9/16.5 kHz) —
sirve para validar LCD, ejes y calibración sin el pipeline completo.

## Integración con el Bloque 4 real

En `top.v`, eliminar `fft_stim_gen` y conectar:

```verilog
complex_fft_core u_fft ( ...,
    .fft_real (fft_real), .fft_imag (fft_imag),
    .fft_valid(fft_valid), .fft_done (fft_done), ... );

block5_lcd_drawer u_block5 (
    .clk_sys(clk), ...        // mismo clk de sistema que el B4
    .clk_pix(clk_pix), ... ); // 40 MHz del PLL
```

Notas de diseño:
- Solo se capturan los bins 0..511 (mitad inferior del espectro, 0..fs/2);
  los bins 512..1023 del frame del B4 se descartan.
- El cruce de dominios de reloj lo resuelve la BRAM de doble puerto +
  sincronizador 2FF del bit de banco; el LCD siempre lee un frame estable.
- La salida de dibujo está pipelined (lectura BRAM + registro de salida):
  la imagen completa queda corrida 1 px, irrelevante visualmente.
- Layout parametrizable en `spectrum_draw.v`: `X0` (inicio del plot),
  `Y_AXIS` (fila del eje X), `MAG_SHIFT` (escala de magnitud).
