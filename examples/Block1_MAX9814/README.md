# Block1 — Integración FPGA (Block1) + Firmware ESP32 (MAX9814 → UART)

Este directorio contiene una integración empaquetada del Bloque 1 para este repositorio (RFFT-Scope-FPGA): los fuentes Verilog del Bloque 1 y el código del firmware ESP32 que genera las tramas UART con muestras del MAX9814.

Estructura dentro de este ejemplo:
- `src/` — implementaciones Verilog y testbenches (copiados desde el proyecto original Block1).
- `firmware/` — código ESP32 (driver y tarea) y ficheros de construcción.

Archivos presentes (resumen):
- Verilog (en `src/`): `uart_rx.v`, `sample_buffer.v`, `pack_real_to_complex.v`, `block1_i2s_top.v`, `block1_top.v`, `sample_fifo.v`, y los testbenches `tb_pack.v`, `tb_uart_rx.v`, `tb_e2e.v`.
- Firmware (en `firmware/`): `main_task.c`, `max9814_driver.c`, `max9814_driver.h`, `CMakeLists.txt`, `idf_component.yml`, `plot_mic.py`.

Formato de datos y parámetros (resumen relevante para este repo):
- Muestras Q15 signed (16 bits). Rango: $0x8000$ = −1.0, $0x7FFF$ ≈ 1.0 − $2^{-15}$.
- Bloque: 2048 muestras reales por frame → 1024 complejos empaquetados.
- UART: Header fijo `0xAA 0x55`, longitud en 2 bytes (big‑endian) = número de muestras (N_samples), payload = muestras MSB first (por muestra: MSB, LSB).
- Baud por defecto en la integración: `921600` bps. Reloj FPGA asumido: `50 MHz` (ajusta `CLK_FREQ` en `uart_rx.v` si tu reloj difiere).

Protocolo UART (detallado):
- Trama: [HEADER][LEN_HI][LEN_LO][PAYLOAD_BYTES]
  - HEADER = `0xAA 0x55`
  - LEN = 16‑bit big‑endian = número de muestras (N_samples)
  - PAYLOAD: N_samples × 2 bytes, cada muestra MSB first

`uart_rx.v` detecta el header, lee LEN y ensambla muestras, emitiendo `sample_valid` (1 ciclo por muestra), `sample_out[15:0]`, `frame_start` (pulso 1 ciclo en el primer sample del frame) y `frame_done` al completar el payload.

Simulaciones y tests (rápido, desde la raíz del repo `RFFT-Scope-FPGA`):

1) Test unitario del empaquetador (empieza en `examples/Block1_MAX9814/src`):

```bash
cd examples/Block1_MAX9814/src
iverilog -o tb_pack.vvp tb_pack.v block1_top.v sample_fifo.v sample_buffer.v pack_real_to_complex.v
vvp tb_pack.vvp
```

2) Test del receptor UART solo:

```bash
cd examples/Block1_MAX9814/src
iverilog -o tb_uart_rx.vvp tb_uart_rx.v uart_rx.v
vvp tb_uart_rx.vvp
```

3) Test end‑to‑end (envía tramas simuladas y verifica salidas `complex_*`):

```bash
cd examples/Block1_MAX9814/src
iverilog -o tb_e2e.vvp tb_e2e.v block1_i2s_top.v block1_top.v sample_fifo.v sample_buffer.v pack_real_to_complex.v uart_rx.v
vvp tb_e2e.vvp
```

Salida esperada: los testbenches incluidos imprimen `PASS` o resumen de errores.

Cómo compilar/usar el firmware ESP32 (en este repo):

Requisitos: Espressif ESP‑IDF instalado y configurado.

```bash
cd examples/Block1_MAX9814/firmware
idf.py build
idf.py -p /dev/ttyUSB0 flash monitor
```

Qué hace el firmware: `max9814_driver.c` configura `adc_continuous`, lee bloques de `BLOCK_SAMPLES` (2048) muestras, las convierte a Q15 y envía por UART en el formato que espera `uart_rx`.

Observaciones y siguientes pasos recomendados para este repositorio:
- Añadir constraints/pinout para tu FPGA objetivo (Tang Primer 20K) y un script de síntesis si vas a generar bitstreams.
- Si planeas pruebas hardware, conecta TX del ESP32 al pin RX de la FPGA y asegura masa común.
- Considerar añadir CRC/ACK si necesitas robustez en la transmisión.

Si quieres puedo:
- Añadir un `run_sim.sh` que ejecute los tres TB automáticamente.
- Crear un `flash_esp.sh` que construya y flashee el firmware (con opción de puerto serie).

Archivo actualizado para este repositorio: [examples/Block1_MAX9814/README.md](examples/Block1_MAX9814/README.md)

---
Personalizado para el repo RFFT-Scope-FPGA — dime si quieres que incluya instrucciones de commit/push automáticas.
