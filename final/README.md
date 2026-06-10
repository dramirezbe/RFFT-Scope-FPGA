# final/ — Fusión Bloque 1 + Bloque 2

Workspace de síntesis para la fusión de los dos primeros bloques del pipeline
RFFT sobre la Tang Primer 20K (Gowin GW2A-LV18PG256C8/I7).

```
ESP32/MAX9814 ──UART 921600──▶ Bloque 1 ──complex_*/frame_start──▶ Bloque 2 ──br_*──▶ (futuro Bloque 4)
                               (uart_rx, FIFO,                     (bit-reverse,
                                ping-pong, packing)                 RAM dual-port)
```

Top de la fusión: [src/rfft_block1_2_top.v](src/rfft_block1_2_top.v)
(`rfft_block1_2_top`). Expone el stream bit-reversed (`br_real/imag/valid`,
entrada `br_ready`) como puertos para que el Bloque 4 se conecte después, más
LEDs de estado (`fifo_overflow`, `frame_dropped`).

## Plan y trabajo realizado

Plan ejecutado para esta fusión (junio 2026):

1. **Exploración:** lectura de todo el repo (`context/HW-CONTEXT.md`,
   `context/INTEGRATION-RULES.md`, READMEs y RTL de todos los bloques en
   `examples/`). Nota: `examples/twiddle_butterfly` (Bloque 3) está vacío; el
   butterfly y la ROM de twiddles viven en `examples/block4_coreFFT/verilog/`.
2. **Workspace `final/`:** copia del RTL del Bloque 1
   (`examples/Block1_MAX9814/src/`) y del Bloque 2
   (`examples/block2_memory_bitreverse/rtl/`) más sus testbenches.
3. **Top de fusión** (`src/rfft_block1_2_top.v`): cableado directo
   B1→B2 según las convenciones de `INTEGRATION-RULES.md` §3, exponiendo el
   stream `br_*` y el `br_ready` para el futuro Bloque 4.
4. **Script de compilación** (`build_block1_2.tcl`): proyecto Gowin EDA
   modelado sobre `examples/sin_lcd/sin_rgb.tcl` (mismo device, mismas
   opciones de bitstream), con constraints en `src/rfft_block1_2.cst`.
5. **Verificación:** nuevo testbench E2E (`tb/tb_block1_2_fusion.v`): frame
   UART de 2048 muestras rampa → 1024 salidas complejas verificadas en orden
   bit-reversed exacto. La simulación expuso **tres bugs reales de
   integración** en el Bloque 2 (detallados abajo), que se corrigieron en
   `src/block2/` y se retroportaron a `examples/`.

Resultado: testbench de fusión y los 8 testbenches unitarios copiados pasan
con Icarus Verilog; el `.tcl` queda listo para `gw_sh`.

## Estructura

| Ruta | Contenido |
|---|---|
| `build_block1_2.tcl` | Script Gowin EDA: proyecto, fuentes, device, bitstream |
| `src/rfft_block1_2_top.v` | Top de fusión + adaptador de protocolo B1→B2 |
| `src/rfft_block1_2.cst` | Constraints de pines (¡placeholders, ajustar al cableado!) |
| `src/block1/` | RTL copiado de `examples/Block1_MAX9814/src/` |
| `src/block2/` | RTL copiado de `examples/block2_memory_bitreverse/rtl/` (con fixes, ver abajo) |
| `tb/` | Testbenches copiados + `tb_block1_2_fusion.v` (smoke test E2E) |

## Compilar (síntesis + P&R + bitstream)

```bash
gw_sh final/build_block1_2.tcl
```

Genera `final/impl/pnr/block1_2_fusion.fs` (formato bin, comprimido, CRC).

## Flashear

```bash
openFPGALoader -b tangprimer20k final/impl/pnr/block1_2_fusion.fs
```

## Simular

```bash
cd final

# Smoke test de la fusión: frame UART de 2048 muestras rampa ->
# 1024 muestras complejas en orden bit-reversed verificadas
iverilog -o tb_fusion tb/tb_block1_2_fusion.v src/rfft_block1_2_top.v src/block1/*.v src/block2/*.v
vvp tb_fusion
# Esperado: "TB FUSION: PASS (1024 samples, bit-reversed order verified)"
```

Los testbenches unitarios copiados (Bloque 1 y Bloque 2) también corren desde
`final/` con las fuentes de `src/block1/` y `src/block2/`; todos pasan.

## Pines (`src/rfft_block1_2.cst`)

Solo `clk = H11` es una asignación verificada (misma que los ejemplos
`lcd`/`sin_lcd`). `rst_n`, `uart_rx`, `br_ready` y los LEDs de estado usan
pines GPIO conocidos del conector LCD del Dock como **placeholders**: muévelos
al header donde realmente cablees el ESP32. Para bring-up sin Bloque 4,
puentea `br_ready` a 3V3. Los buses `br_real/br_imag` quedan sin constraint
(Gowin los auto-asigna); fíjalos solo si vas a sondearlos.

## Fixes de integración B1→B2 (en `src/block2/`, retroportados a `examples/`)

La fusión con el stream real del Bloque 1 expuso tres bugs en
`permutation_controller.v` que los testbenches originales enmascaraban
(su estímulo tenía off-by-ones compensatorios):

1. **Handshake `br_valid`:** en `OUTPUT_VALID` se hacía `br_valid <= 1` y
   `br_valid <= 0` en el mismo flanco cuando `br_ready` ya estaba alto, así
   que con un consumidor siempre listo `br_valid` nunca se observaba. Ahora el
   dato se presenta con `br_valid = 1` durante un ciclo completo antes de
   evaluar `br_ready`.
2. **Dato de escritura sin registrar:** `wr_en`/`wr_addr` eran registrados
   pero la RAM recibía `complex_real/imag` en vivo, por lo que con un stream
   continuo cada escritura capturaba la muestra siguiente (+1). Ahora el dato
   se registra junto con la dirección.
3. **Protocolo de `frame_start`:** el Bloque 1 emite `frame_start` junto con
   la primera muestra válida, pero la FSM del Bloque 2 estaba en IDLE en ese
   ciclo y perdía la muestra 0 (se quedaba colgada esperando la 1024ª). Ahora
   IDLE captura la muestra 0 si `complex_valid` acompaña a `frame_start`, y
   sigue aceptando también `frame_start` un ciclo antes del dato. Con esto la
   conexión B1→B2 en el top de fusión es cableado directo, sin adaptadores.

Los testbenches `tb_permutation.v`, `tb_permutation_1024.v` y
`tb_permutation_ready_pause.v` se corrigieron para alinear `complex_valid`
con su dato (protocolo valid/ready de `context/INTEGRATION-RULES.md` §4);
`tb_permutation.v` ejercita además el estilo del Bloque 1 (`frame_start`
alineado con la muestra 0).

Los mismos fixes están retroportados a
`examples/block2_memory_bitreverse/` (RTL y testbenches), donde toda la
suite vuelve a pasar.

> Nota: el `Makefile` de `examples/block2_memory_bitreverse` usa
> `.RECIPEPREFIX`, que requiere GNU make ≥ 4.0 (el make 3.81 de macOS falla
> con "missing separator"); los comandos `iverilog`/`vvp` equivalentes corren
> bien a mano.
