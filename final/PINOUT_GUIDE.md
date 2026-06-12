# Guía de conexión — RFFT Scope (Tang Primer 20K + ESP32 WROOM-32)

Pinout completo para flashear y cablear el pipeline `rfft_scope_top`.
Todos los pines de la FPGA están verificados contra el repo oficial de
Sipeed ([TangPrimer-20K-example](https://github.com/sipeed/TangPrimer-20K-example):
`UART_HELLO`, `RGB_lcd`, BSP de Litex).

- **FPGA:** Gowin GW2A-LV18PG256C8/I7 (Tang Primer 20K) + ext-board **Dock**.
- **Reloj de placa:** 27 MHz en **H11** (oscilador del core board).
- **MCU de audio:** ESP32-WROOM-32 + micrófono **MAX9814**.
- **Niveles:** todo 3.3V (LVCMOS33). El ESP32 es 3.3V → conexión directa, sin level shifter.

---

## 1. Diagrama de conexión

```
   MAX9814                ESP32-WROOM-32                 Tang Primer 20K (Dock)
 ┌─────────┐            ┌────────────────┐             ┌──────────────────────┐
 │  OUT  ──┼────────────┼─ GPIO36 (ADC1_0)│             │                      │
 │  VDD  ──┼── 3V3      │                 │             │                      │
 │  GND  ──┼── GND      │  GPIO17 (U2_TXD)├──UART 921600┤ T6   uart_rx (MIC ARR)│
 └─────────┘            │            GND ─┼─────────────┤ GND  (común)         │
                        │            3V3 ─┼─ (opcional) │                      │
                        └────────────────┘             │ H11  clk 27MHz (osc) │
                                                        │ T10  rst_n (botón S? )│
        Pantalla RGB 800×480  ───────────────────────► │ conector RGB LCD     │
                                                        │ L16  LED fifo_ovf    │
                                                        │ L14  LED frame_drop  │
                                                        └──────────────────────┘
```

**Conexiones mínimas para que funcione:**
1. `ESP32 GPIO17` → `FPGA T6` (header MIC ARRAY; datos UART de audio).
2. `ESP32 GND` ↔ `FPGA GND` (referencia común, **imprescindible**).
3. `MAX9814 OUT` → `ESP32 GPIO36`; `MAX9814 VDD/GND` → 3V3/GND del ESP32.
4. Pantalla RGB en el conector LCD del Dock.
5. Alimentar la Tang Primer por su USB-C; el ESP32 por su propio USB.

---

## 2. Pines de la FPGA — `rfft_scope_top` (constraints en `src/rfft_scope.cst`)

### 2.1 Sistema

| Señal FPGA | Pin | Dirección | IO_TYPE | Conecta a |
|---|---|---|---|---|
| `clk` | **H11** | in | LVCMOS33 | Oscilador 27 MHz del core board (fijo) |
| `rst_n` | **T10** | in | LVCMOS33 | `btn_n0` (botón usuario, activo-bajo). Pull-up interno |
| `uart_rx` | **T6** | in | LVCMOS33 | **ESP32 GPIO17 (U2_TXD)** — pin del header MIC ARRAY |
| `fifo_overflow` | **L16** | out | LVCMOS33 | `led0` onboard (debug) |
| `frame_dropped` | **L14** | out | LVCMOS33 | `led1` onboard (debug) |

> **Por qué T6 y no T13:** T13 es el RX del UART oficial, pero va **internamente
> al puente USB-UART (BL616)** del Dock — no está en ningún header donde se pueda
> soldar un cable al ESP32. Por eso `uart_rx` se asigna a **T6**, un GPIO libre
> del header **MIC ARRAY** (esquina superior izquierda del Dock) que tiene GND y
> 3V3 al lado. **Verificar** contra el header físico; si Gowin objeta el
> `IO_TYPE`, usar otro pin del mismo header (P6/R8/P8/T8/P9/T9) o quitar el
> `IO_TYPE`. Cambiar `uart_rx` requiere re-sintetizar.

### 2.2 Pantalla RGB LCD 800×480 (conector dedicado del Dock)

| Señal | Pin | | Señal | Pin | | Señal | Pin |
|---|---|---|---|---|---|---|---|
| `lcd_clk`  | R9  | | `lcd_r[4]` | N6 | | `lcd_g[5]` | D10 |
| `lcd_hsync`| A15 | | `lcd_r[3]` | N7 | | `lcd_g[4]` | R7  |
| `lcd_vsync`| D14 | | `lcd_r[2]` | N9 | | `lcd_g[3]` | P7  |
| `lcd_de`   | E15 | | `lcd_r[1]` | N8 | | `lcd_g[2]` | B11 |
| `lcd_bl`   | E10 | | `lcd_r[0]` | L9 | | `lcd_g[1]` | A11 |
| `lcd_b[4]` | B14 | | `lcd_b[2]` | B13| | `lcd_g[0]` | D11 |
| `lcd_b[3]` | A14 | | `lcd_b[1]` | C12| | `lcd_b[0]` | B12 |

Son los mismos pines del ejemplo `RGB_lcd/800x480_5inch_lcd` de Sipeed: si tu
panel ya funciona con ese ejemplo, aquí funcionará igual. Pixel clock 40.5 MHz
(PLL interno desde los 27 MHz).

---

## 3. ESP32-WROOM-32 — firmware `examples/Block1_MAX9814/firmware`

| Función | GPIO ESP32 | Detalle |
|---|---|---|
| UART TX (audio → FPGA) | **GPIO17** | `UART_NUM_2`, 921600 bps, 8N1 |
| UART RX | — | no se usa (`RXD_PIN = -1`) |
| Micrófono MAX9814 OUT | **GPIO36** | `ADC1_CHANNEL_0`, captura continua |
| Alimentación MAX9814 | 3V3 / GND | desde el propio ESP32 |

Formato de trama UART (lo que espera `uart_rx.v`): `0xAA 0x55` + `LEN_HI LEN_LO`
(big-endian, 2048) + 2048 muestras Q15 de 16 bits, **MSB primero**, a 48 kHz.

Flashear el ESP32:
```bash
cd examples/Block1_MAX9814/firmware
idf.py build && idf.py -p /dev/ttyUSB0 flash monitor
```

---

## 4. Notas eléctricas y de timing

- **GND común obligatorio** entre ESP32 y Tang Primer: sin él la UART no
  decodifica (no hay referencia de nivel).
- **Niveles 3.3V** en ambos lados → conexión directa de GPIO17 a T6. No
  conectar nada de 5V a los pines de la FPGA.
- **Baudrate vs reloj:** el `uart_rx` deriva el divisor de `CLK_FREQ=27_000_000`
  y `BAUD=921600` (parámetros del top). El error de baudrate resultante es
  ~2.3%, dentro de la tolerancia de 8N1 (el receptor resincroniza en cada start
  bit). Si ves bytes corruptos, baja el baudrate del ESP32 a 460800 y ajusta
  `BAUD` en la instancia de `block1_i2s_top` dentro de `rfft_scope_top.v`.
- **rst_n:** activo-bajo con pull-up. En reposo = 1 (corriendo); al pulsar el
  botón = 0 (reset). Si tu Dock no expone `btn_n0`, puentea T10 a 3V3 con un
  jumper y resetea por power-cycle.
- **br_ready** (del hito B1+B2 `build_block1_2.tcl`): en ese build standalone va
  a `T3` (`btn_n1`); puentéalo a 3V3 para liberar el flujo. En el pipeline
  completo es una señal interna (no sale a pin).

---

## 5. Build y flasheo de la FPGA

```bash
gw_sh final/build_rfft_scope.tcl
openFPGALoader -b tangprimer20k final/rfft_scope/impl/pnr/rfft_scope.fs
```

Al encender, el LCD queda **negro** hasta que llega el primer frame de audio
completo (gate del `spectrum_buffer`), luego muestra el espectro 0–24 kHz con
el eje X en kHz. Si los LEDs `L16`/`L14` se encienden, hay overflow de FIFO o
frames perdidos (revisar baudrate / GND).
