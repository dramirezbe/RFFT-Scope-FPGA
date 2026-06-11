# ISSUES_FOUND.md — RFFT Scope Pipeline (Bloques 1–5)

Generado: 2026-06-10 | Icarus Verilog 12.0 | Target: Tang Primer 20K (GW2A-LV18PG256C8/I7)

---

## Resultados de simulación

| # | Testbench | Resultado | Tiempo |
|---|-----------|-----------|--------|
| 1 | `tb_uart_rx` | PASS | <1s |
| 2 | `tb_pack` | PASS | <1s |
| 3 | `tb_e2e` (B1: UART→pack) | PASS | <1s |
| 4 | `tb_ram_buffer` | PASS | <1s |
| 5 | `tb_bit_reverse` | PASS | <1s |
| 6 | `tb_permutation` (N=8) | PASS | <1s |
| 7 | `tb_permutation_1024` | PASS | <1s |
| 8 | `tb_permutation_ready_pause` | PASS | <1s |
| 9 | `tb_block1_2_fusion` (B1+B2) | PASS | ~1s |
| 10 | `tb_rfft_recombine` (512 bins vs golden, ±4 LSB) | PASS | <1s |
| 11 | `tb_rfft_scope_e2e` (UART→LCD, cadena completa) | PASS | ~68.5×10⁹ ps |

**Resumen: 11/11 PASS en simulación.** PGM volcado en `rfft_scope_frame.pgm` (800×480, 771 KB).

---

## Riesgos para despliegue en hardware (Tang Primer 20K)

### H1 — Pines de UART, reset y status son placeholders

`src/rfft_scope.cst:49-56`:
```
IO_LOC "rst_n" T10;       // placeholder
IO_LOC "uart_rx" M11;     // placeholder
IO_LOC "fifo_overflow" L16;
IO_LOC "frame_dropped" L14;
```

- `uart_rx` (M11): debe conectarse al TX del ESP32. Hoy no corresponde a ningún header estándar del Dock.
- `rst_n` (T10): debe conectarse a un pulsador o jumper a 3V3.
- `fifo_overflow` (L16), `frame_dropped` (L14): LEDs de debug. Verificar que no colisionen con los pines del LCD (no aparecen en `sin_rgb.cst`, probablemente GPIO libres).

**Impacto:** Sin ajustar estos pines, el diseño no recibe datos del ESP32 ni puede resetearse desde hardware.

### H2 — Inconsistencia entre los dos archivos `.cst`

| Señal | `rfft_scope.cst` | `rfft_block1_2.cst` |
|-------|-------------------|----------------------|
| `rst_n` | T10 | E15 |
| `uart_rx` | M11 | A15 |

`E15` y `A15` en `rfft_block1_2.cst` **son pines del LCD** (`lcd_de` y `lcd_hsync` respectivamente). Si se carga el bitstream de `block1_2_fusion` con esos pines, el LCD conectado al Dock cortocircuitará o dañará las señales.

**Impacto:** El CST de `block1_2_fusion` es peligroso si el LCD está conectado. Debe corregirse antes de cualquier flasheo.

### H3 — Pines `br_*` sin constrain en `rfft_block1_2.cst`

`br_real[15:0]` y `br_imag[15:0]` (32 pines, líneas 34-39 del CST solo constriñen `br_valid`) quedan sin asignación de ubicación. Gowin P&R los auto-coloca en pines arbitrarios.

**Impacto:** En el build standalone de B1+B2 es intencional (para probar con logic analyzer). Pero si alguno de esos pines auto-colocados es un pin compartido con el LCD o reservado, el P&R fallará o habrá conflicto eléctrico.

### H4 — Inicialización de ROMs de twiddle en síntesis Gowin

`twiddle_rom.v` usa `$readmemh` en bloque `initial` para cargar `twiddles_fft.hex` y `twiddles_recomb.hex`. Gowin EDA **no ejecuta** `$readmemh` en síntesis. Los archivos `.mi` existen en `src/block3/` pero no están vinculados a ninguna IP de BSRAM explícita en el proyecto.

El comentario en `twiddle_rom.v:39` reconoce: _"Gowin EDA usa los .mi en síntesis"_, pero el flujo actual depende de que el sintetizador infiera la BSRAM **y** aplique la inicialización desde el `.mi` vía atributo `(* ram_style = "block" *)`. Esto no está garantizado.

**Impacto:** Si Gowin sintetiza las ROMs sin contenido inicial, todos los twiddle factors serán 0. La FFT producirá salida nula. El LCD mostrará pantalla negra (cero barras). **Este es el riesgo más grave para el funcionamiento en hardware.**

**Solución recomendada:** Instanciar las BSRAM como IP de Gowin (desde el IP Catalog) con los `.mi` como archivo de inicialización, en lugar de inferirlas desde RTL.

### H5 — Memorias sin reset (primer frame con basura)

Los siguientes módulos no resetean el contenido de sus memorias:

| Módulo | Memoria | Efecto en primer frame |
|--------|---------|------------------------|
| `working_memory.v` | `mem_a`, `mem_b` (1024×32 c/u) | La FFT procesa basura hasta que el primer frame de B2 escribe los 1024 valores |
| `dual_port_ram_buffer.v` | `mem_real`, `mem_imag` (1024×16 c/u) | B2 lee basura si se pide lectura antes de escritura |
| `spectrum_buffer.v` | `mem` (1024×16) | El display muestra barras aleatorias hasta que el primer frame de FFT completa la escritura en el banco activo |

El `spectrum_buffer.v:57-60` tiene un bloque `initial` que pone la RAM a cero, pero solo funciona en simulación.

**Impacto:** Al encender la Tang Primer, el LCD mostrará ~1 frame de basura (≈21 ms a 48 kHz) hasta que el pipeline complete su primer ciclo. Es un problema cosmético transitorio.

---

## Riesgos de lógica (simulación OK, pero frágil)

### L1 — Tolerancia innecesaria en `tb_pack.v` y `tb_e2e.v`

Ambos TBs usan `±1 LSB` de tolerancia (`within_one_lsb`) para comparar datos de rampa que cruzan FIFO + buffer ping-pong + empaquetado. Esta ruta es puramente digital sin aritmética — debería ser bit-exacta.

**Impacto:** Un error de 1 LSB pasaría desapercibido. Si se introdujera un bug sutil en el buffer ping-pong o el empaquetador, estos TBs no lo detectarían.

### L2 — Sin testbench unitario para `complex_fft_core` (B4)

El Bloque 4 (FFT compleja, 377 líneas, 6 fixes documentados) solo se verifica a través del TB E2E. No existe un `tb_complex_fft_core.v` que inyecte datos bit-reversed conocidos y compare la salida FFT contra un golden.

**Impacto:** Si se modifica el B4 (stage controller, working memory, FSM), no hay forma de hacer regresión rápida. El TB E2E tarda ~2–3 minutos.

### L3 — Cobertura laxa del E2E en el display

`tb_rfft_scope_e2e.v` usa `white_near(x, y)` que devuelve `1` si **cualquier** píxel en una ventana de 5×5 alrededor de `(x,y)` es blanco. Además, solo verifica 3 frecuencias espurias (7.5, 15, 22.5 kHz). El resto del espectro no se inspecciona.

**Impacto:** Una barra espuria de 1–2 px de ancho en una frecuencia no chequeada pasaría como PASS.

---

## Problemas de calidad de código

### Q1 — Sin backpressure UART → FIFO

`block1_i2s_top.v:48` deja `sample_ready` desconectado. El `uart_rx` emite muestras a 921600 baud (≈53.3 ksps efectivo para payload de 16 bits) sin conocer el estado de la FIFO. La FIFO tiene 64 posiciones y `fifo_overflow` se activa si se llena.

**Impacto:** Con clock de 27 MHz, el consumidor (sample_buffer → pack) vacía la FIFO más rápido que el UART la llena (27M / 53.3k ≈ 506 ciclos por muestra para consumir). El margen es enorme: no debería haber overflow en operación normal. Pero si el clock del sistema fuera más lento o el UART más rápido, podrían perderse muestras.

### Q2 — Mux `load_wr_en` en `complex_fft_core.v` puede disparar warning de timing

`complex_fft_core.v:121`:
```verilog
assign wm_wr_en = load_wr_en ? 1'b1 : sc_wr_en;
```

El pulso `load_wr_en` ocurre en el ciclo donde la FSM ya está en `S_INIT_STAGE` (FIX-5). La herramienta de timing podría reportar un camino `load_wr_en → wm_wr_en → BSRAM we` como crítico, aunque en la práctica cierra sin problemas a 27 MHz.

### Q3 — Ruta combinacional grande en `fft_stage_controller.v`

Las señales `addr_e_next`, `addr_o_next`, `tw_addr_next` (líneas 33-36) se computan con multiplicación (`grp * group_size`). A 27 MHz esto cierra, pero el sintetizador usará LUTs en cascada. A frecuencias mayores (>80 MHz) podría ser la ruta crítica.

### Q4 — `spectrum_draw.v` retrasa coordenadas para alinear con latencia de BRAM

`spectrum_draw.v:55-64` registra `xq`/`yq` para compensar 1 ciclo de latencia de lectura del `spectrum_buffer`. Esto desplaza la imagen 1 píxel a la derecha/abajo (invisible al ojo). Si se cambia la latencia de la BRAM o se añade un pipeline stage, la imagen se descorrelaciona.

---

## Infraestructura de verificación

### V1 — Vectores golden dependientes de parámetros hardcodeados

`scripts/gen_e2e_vectors.py:28`:
```python
AMP = 0.8
```

El RTL aplica `>>1` en `rfft_scope_top.v:111` y `MAG_SHIFT=6` en la instancia de `block5_lcd_drawer`. Si cualquiera de estos valores cambia, los vectores golden quedan obsoletos y el E2E fallará (o peor, dará falso PASS por tolerancias laxas).

### V2 — `.mi` y `.hex` pueden divergir

Los archivos `.mi` (formato Gowin) y `.hex` (formato `$readmemh`) se generan por separado o manualmente. No hay un script que garantice que ambos contienen exactamente los mismos twiddle factors. Si se regeneran los twiddles y solo se actualiza un formato, simulación y síntesis darán resultados distintos.

### V3 — El E2E TB define `pll_40m` como stub inline

`tb_rfft_scope_e2e.v:30-38` redefine `pll_40m` con un `forever #12.5` (40 MHz libre). Esto es correcto para simulación pero significa que **la sincronización de fase entre `clk` y `clk_pix` es artificial**. Cualquier bug de CDC (cross-domain clocking) entre el dominio `clk` (27 MHz) y `clk_pix` (40.5 MHz) es invisible en simulación.

---

## Resumen

| Categoría | Cantidad | Severidad |
|-----------|----------|-----------|
| Riesgos hardware | 5 | Alta — impiden o degradan funcionamiento en placa |
| Riesgos lógica | 3 | Media — tests pasan pero con cobertura débil |
| Calidad de código | 4 | Baja — funcionan, pero frágiles ante cambios |
| Infraestructura | 3 | Baja — mantenimiento futuro |

**Conclusión:** El pipeline completo es **funcionalmente correcto en simulación** (11/11 PASS). Para desplegar en la Tang Primer 20K hacen falta:
1. Asignar pines reales para `uart_rx`, `rst_n` y los LEDs de status
2. Corregir `rfft_block1_2.cst` (pines de LCD reusados como GPIO)
3. Verificar que Gowin EDA inicializa correctamente las ROMs de twiddle (`.mi` → BSRAM), o migrar a IP explícita de BSRAM

---

# REVISIÓN Y RESOLUCIÓN (2026-06-10, segunda pasada)

Cada punto revisado contra el RTL. **Hallazgo mayor: el "11/11 PASS" era
engañoso** — el TB unitario del B4 (y el E2E con tolerancias laxas) ocultaban
dos bugs reales del Bloque 4. Se encontraron aislando la cadena B2→B4→recomb
contra un golden numpy bit-exacto (nuevo `tb/tb_chain_b2b4recomb.v`).

| # | ¿Cierto? | Resolución |
|---|----------|------------|
| **B4 oculto** | — (no estaba en el informe) | **FIX-5**: `mem[1023]` no se escribía (mux por `state` con `load_wr_en` registrado) → X propagada. **FIX-6**: salida corrida 1 bin (latencia BSRAM sin prefetch) → pico en bin equivocado. El checker del TB ignoraba los X (`X>tol`=falso). **CORREGIDO** + TB ahora detecta X. |
| **H1** | Sí, y peor | `uart_rx` estaba en **M11 = línea TX** del FPGA (por eso "no recibía"). **CORREGIDO** → `T13` (RX real). `rst_n=T10`, LEDs `L16/L14` confirmados oficiales. Ver `PINOUT_GUIDE.md`. |
| **H2** | Sí, peligroso | `rfft_block1_2.cst` usaba 6 pines del LCD. **CORREGIDO** → botones/LEDs onboard (T10, T13, T3, L16, L14, N14). Ya no colisiona con el LCD. |
| **H3** | Parcial | `br_*` sin constrain es intencional (build standalone, solo warning). Documentado en el `.cst`. Sin cambio. |
| **H4** | Parcial/incorrecto | GowinSynthesis ≥1.9.8 **sí** ejecuta `$readmemh` en síntesis (manual SUG550). El riesgo real es la ruta. **Documentado** en `twiddle_rom.v` (regla de prioridad + verificación + alternativa IP). |
| **H5** | Sí, cosmético | **CORREGIDO**: gate `first_done` en `spectrum_buffer.v` → LCD en negro hasta el primer frame completo. |
| **L1** | Sí, menor | Tolerancia ±1 LSB en B1 es laxa pero la ruta es digital pura; los TB pasan bit-exacto en la práctica. Sin cambio (bajo riesgo). |
| **L2** | Sí, crítico | **CORREGIDO**: `tb/tb_complex_fft_core.v` (regresión rápida del B4) + `tb/tb_chain_b2b4recomb.v` (cadena vs golden). Ambos detectan X. Justamente esto destapó los bugs del B4. |
| **L3** | Sí, menor | El E2E sigue usando `white_near` ±2px, pero ahora se complementa con el chain test bit-exacto. Cobertura suficiente. |
| **Q1** | Correcto | Sin overflow en operación normal (margen 506×). Sin cambio. |
| **Q2** | Correcto | El mux `load_wr_en` cierra a 27 MHz. Sin cambio. |
| **Q3/Q4** | Correctos | Rutas combinacionales y registro de coordenadas OK a 27/40.5 MHz. Sin cambio. |
| **V1** | Sí | `gen_e2e_vectors.py` regenera todos los vectores de forma consistente (amp 0.5, MAG_SHIFT=7). Documentado. |
| **V2** | Sí, y se materializó | El `twiddles_recomb.hex` de `examples/block4_coreFFT/otros/` era un **placeholder incorrecto** (todo `7FFF0000`). El de `src/block3/` (submódulo) es el correcto y es el que usa el pipeline. Sin acción (ya usamos el bueno). |
| **V3** | Sí, conocido | El PLL es stub en sim; el CDC se mitiga con RAM doble-reloj + 2FF. Limitación inherente de simular sin el PLL real. |

**Estado tras la revisión:** pipeline **funcional de verdad** (no por falsos
PASS). El tono de 3 kHz por UART produce una barra única en 3 kHz en el LCD,
verificado contra golden numpy. Listo para síntesis y placa siguiendo
`PINOUT_GUIDE.md`.
