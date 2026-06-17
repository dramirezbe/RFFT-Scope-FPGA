# Plan de Verificación — RFFT Scope FPGA

Implementa la lógica de verificación del documento de diseño (Sección 3,
Tabla 1): **bottom-up**, cada bloque se valida por separado antes de integrar,
con el modelo dorado de Python como referencia y factor de escala 1/1024.

Las pruebas están **enfocadas además al error que presentamos** —"la
transmisión del micrófono se detiene a los pocos segundos y la gráfica se
congela"— cubriendo todo el camino de datos y posibles causas en cada bloque.

## El error y su acotación

```
MAX9814 → ADC(ESP32) → UART TX → │ uart_rx → fifo → buffer → pack → bit-rev → FFT → recomb → LCD
        (firmware C)             │ (FPGA)
        [prueba 5: HIL]          │ [pruebas 1..13: RTL automáticas]
```

El congelamiento resultó estar en el **firmware de TX del ESP32** (perdía el
tiempo real y desbordaba el buffer del ADC). Las pruebas RTL demuestran que
todo el lado FPGA es correcto → el fallo queda acotado al emisor. Esa es la
prueba de la lógica de verificación.

## Pruebas automáticas (RTL, Icarus Verilog)

| # | Prueba | Bloque / etapa | Posible causa que descarta | Tabla 1 |
|---|---|---|---|---|
| 1 | `uart_rx` | B1 — recepción UART (incl. fix 2 bytes de cola) | Tramas mal desensambladas / desincronización | — |
| 2 | `ram_buffer` | B1/B2 — buffer dual-port | Lectura/escritura de muestras corrupta | `sample_buffer` |
| 3 | `pack` | B1 — FIFO + ping-pong + pack real→complejo | Pérdida de muestras / empaquetado | `pack_real_to_complex` |
| 4 | `e2e_block1` | B1 — cadena UART→muestras completa | Camino de entrada completo | — |
| 5 | `bit_reverse` | B2 — permutación bit-reversa | Orden de entrada al FFT incorrecto | `bit_reverse` |
| 6 | `permutation` | B2 — controlador de permutación | Direccionamiento de la RAM de reordenado | `bit_reverse` |
| 7 | `permutation_1024` | B2 — permutación N=1024 | Igual, a tamaño real | `bit_reverse` |
| 8 | `permutation_ready_pause` | B2 — handshake ready/pause | Bloqueos por backpressure | — |
| 9 | `complex_fft_core` | B3+B4 — FFT 1024-pt (mariposa+twiddles) | Aritmética Q15 / twiddles / escala | `complex_fft_core` |
| 10 | `rfft_recombine` | B5 — recombinación 1025 bins | DC/Nyquist y bins mal recuperados | `rfft_recombine` |
| 11 | `chain_b2b4recomb` | B2→B4→B5 | Integración FFT+recombinación | full system |
| 12 | `block1_2_fusion` | B1→B2 | Integración entrada+permutación | full system |
| 13 | `scope_e2e` | Pipeline completo UART→LCD | Camino punta a punta | full system |

## Prueba manual (hardware-in-the-loop, NO automatizada)

| # | Prueba | Qué valida |
|---|---|---|
| HIL | `mic_record_test` | Graba audio real del MAX9814 y lo guarda como `.wav` para escucharlo. Valida la etapa **física** mic → ADC → muestras, independiente del FPGA. |

Necesita ESP32 + micrófono. Instrucciones:
[`examples/Block1_MAX9814/mic_record_test/README.md`](../examples/Block1_MAX9814/mic_record_test/README.md)

## Cómo ejecutar

```bash
cd verification_plan
./run_tests.sh          # corre las 13 pruebas una a una; logs en results/
```

Requiere Icarus Verilog (`brew install icarus-verilog`).

## Resultado de referencia

```
[Bloque 1] uart_rx, ram_buffer, pack, e2e_block1                 ... PASS
[Bloque 2] bit_reverse, permutation, permutation_1024, ready_pause ... PASS
[Bloques 3+4] complex_fft_core                                    ... PASS
[Bloque 5] rfft_recombine                                         ... PASS
[Integración] chain_b2b4recomb, block1_2_fusion, scope_e2e        ... PASS
PASS: 13   FAIL: 0
```
