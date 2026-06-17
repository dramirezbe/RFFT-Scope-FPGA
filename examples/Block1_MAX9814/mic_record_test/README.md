# mic_record_test — Prueba de verificación de la cadena del micrófono

Graba ~10 s del micrófono **MAX9814** con el ADC del ESP32 y los envía por el
**mismo USB de programación (UART0)**. Un script en el PC los guarda como `.wav`
en `~/Downloads` para escucharlos.

**Objetivo de verificación:** validar de forma aislada la etapa de captura
(mic → ADC → muestras Q15) **sin** el FPGA. Si la grabación se escucha bien,
la entrada del pipeline RFFT está correcta; cualquier problema posterior está
aguas abajo (UART/FPGA), no en el micrófono. (Requisito FUN-3.)

```
MAX9814 ──analógico──► ADC1_CH0 (GPIO36) ──► ESP32 ──UART0 (USB, 115200)──► PC ──► WAV
```

## Conexiones

| MAX9814 | ESP32 |
|---|---|
| VDD | 3V3 |
| GND | GND |
| OUT | GPIO36 (VP / ADC1_CH0) |

No se necesita adaptador USB-TTL: se reutiliza el **mismo cable USB** con el que
se flashea. La salida va por UART0 (GPIO1/GPIO3) a 115200 baud, los logs se
silencian durante el volcado para no corromper el PCM binario, y el host
descarta el ruido de arranque buscando el magic `ESPMIC01`.

## Pasos

```bash
# 1. Compilar y flashear (ESP-IDF)
cd examples/Block1_MAX9814/mic_record_test
idf.py set-target esp32
idf.py build flash          # NO uses 'monitor' después: el puerto se usa para el audio

# 2. En el PC, lanzar el receptor (cierra cualquier monitor antes)
pip install pyserial         # una sola vez
python3 host/save_audio.py -r   # -r reinicia la placa y arranca la grabación

# 3. Habla cerca del micrófono ~10 s. La transferencia tarda ~28 s a 115200.

# 4. Escuchar
afplay ~/Downloads/esp32_audio_*.wav     # macOS
```

`-r` usa la secuencia DTR/RTS (estilo esptool) para reiniciar el ESP32 sin tocar
el botón. Si tu placa no expone DTR/RTS, omite `-r` y pulsa EN/RESET a mano.

## Parámetros (en `main/mic_record.c`)

| Define | Valor | Nota |
|---|---|---|
| `SAMPLE_RATE_HZ` | 20000 | Mínimo del ADC-DMA del ESP32 (`SOC_ADC_SAMPLE_FREQ_THRES_LOW`); por debajo da `ESP_ERR_INVALID_ARG` |
| `RECORD_SECONDS` | 10 | Duración de la grabación |
| `ADC_CHANNEL` | `ADC_CHANNEL_0` | GPIO36 |
| `UART_PORT` / `UART_BAUD` | `UART_NUM_0` / 115200 | Mismo USB y baudios que la consola |

A 115200 baud, 10 s de audio (≈400 KB) tardan ~28–35 s en transferirse. Es una
prueba puntual (record-then-dump), no streaming en tiempo real.

## Protocolo del stream (little-endian)

```
[8]  magic = "ESPMIC01"
[4]  uint32 sample_rate_hz
[4]  uint32 num_samples
[2]  uint16 bits_per_sample (=16)
[2]  uint16 channels (=1)
[num_samples*2] int16 PCM
```

El ESP32 clásico no puede escribir en la carpeta Descargas del PC; por eso el
WAV lo construye el host a partir de este stream.

## Cómo encaja en el plan de verificación

Complementa los testbenches RTL de `sample_buffer` y "Q15 conversion" de la
Tabla 1: aquellos comprueban formato/almacenamiento en simulación; esta prueba
comprueba que la señal **física** del micrófono llega limpia y audible antes de
entrar al FFT. Es la verificación de bring-up del front-end (FUN-3).
