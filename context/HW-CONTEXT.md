# Sipeed Tang Primer 20K (actualizado con implementacion final/)

## FPGA Chip: Gowin GW2A-LV18PG256C8/I7
- LUT4: 20,736 | FF: 15,552 | Block SRAM: 828 Kbits | DSP Multipliers (18x18): 48 | PLLs: 4
- On-board: 1 Gbit (128 MB) DDR3 SDRAM + 32 Mbit SPI NOR Flash (W25Q32JVS)
- Form factor: DDR3 SODIMM core module; two ext-boards: **Dock** and **Lite**

## Extension Boards
- **Dock:** USB-JTAG & UART (onboard debugger), Ethernet PHY (10/100), USB 2.0 PHY, HDMI, DVP camera, RGB LCD, SPI LCD, audio (3.5 mm), MIC array, microSD. DIP switch #1 must be ON to enable core board.
- **Lite:** 4x PMOD + dual-row pin headers for raw I/O access.

## Actual Pin Assignments (RFFT Scope)

### System Pins

| Signal FPGA | Pin | Direction | IO_TYPE | Conecta a |
|---|---|---|---|---|
| `clk` | **H11** | in | LVCMOS33 | Oscilador 27 MHz del core board (fijo) |
| `rst_n` | **T10** | in | LVCMOS33 | `btn_n0` (boton usuario onboard, activo-bajo). Pull-up interno |
| `uart_rx` | **T13** | in | LVCMOS33 | **ESP32 GPIO17 (U2_TXD)**. NOTA: T13 es el RX del puente USB-UART del BL616; no abrir el puerto USB-serial a la vez |
| `fifo_overflow` | **L16** | out | LVCMOS33 | `led0` onboard (debug) |
| `frame_dropped` | **L14** | out | LVCMOS33 | `led1` onboard (debug) |

### LCD RGB 800x480 (conector dedicado del Dock)

| Senal | Pin | | Senal | Pin | | Senal | Pin |
|---|---|---|---|---|---|---|---|
| `lcd_clk` | R9 | | `lcd_r[4]` | N6 | | `lcd_g[5]` | D10 |
| `lcd_hsync` | A15 | | `lcd_r[3]` | N7 | | `lcd_g[4]` | R7 |
| `lcd_vsync` | D14 | | `lcd_r[2]` | N9 | | `lcd_g[3]` | P7 |
| `lcd_de` | E15 | | `lcd_r[1]` | N8 | | `lcd_g[2]` | B11 |
| `lcd_bl` | E10 | | `lcd_r[0]` | L9 | | `lcd_g[1]` | A11 |
| | | | `lcd_b[4]` | B14 | | `lcd_g[0]` | D11 |
| | | | `lcd_b[3]` | A14 | | `lcd_b[2]` | B13 |
| | | | `lcd_b[1]` | C12 | | `lcd_b[0]` | B12 |

Mismos pines del ejemplo `RGB_lcd/800x480_5inch_lcd` de Sipeed. Pixel clock 40.5 MHz (PLL `pll_40m` desde 27 MHz: 27 x 3 / 2).

### ESP32-WROOM-32 Pinout

| Funcion | GPIO ESP32 | Detalle |
|---|---|---|
| UART TX (audio -> FPGA) | **GPIO17** | `UART_NUM_2`, 921600 bps, 8N1, MSB first |
| UART RX | — | no se usa (`RXD_PIN = -1`) |
| Microfono MAX9814 OUT | **GPIO36** | `ADC1_CHANNEL_0`, captura continua a 48 kHz |
| Alimentacion MAX9814 | 3V3 / GND | desde el propio ESP32 |

### Conexiones Minimas
1. `ESP32 GPIO17` -> `FPGA T13` (UART audio data)
2. `ESP32 GND` <-> `FPGA GND` (referencia comun)
3. `MAX9814 OUT` -> `ESP32 GPIO36`; `MAX9814 VDD/GND` -> 3V3/GND del ESP32
4. Pantalla RGB en el conector LCD del Dock
5. Alimentar Tang Primer por USB-C; ESP32 por su propio USB

### Notas Electricas
- **Niveles 3.3V** en ambos lados -> conexion directa GPIO17 a T13. No conectar 5V a pines FPGA.
- **Baudrate vs reloj:** divisor UART derivado de `CLK_FREQ=27_000_000` y `BAUD=921600`. Error ~2.3%, dentro de tolerancia 8N1.
- **rst_n:** activo-bajo con pull-up. En reposo=1; al pulsar=0. Si el Dock no expone `btn_n0`, puentear T10 a 3V3.
- **uart_rx (T13):** compartido con BL616 USB-UART. Si el ESP32 maneja la linea, no conectar el puerto USB-serial del PC simultaneamente.

## Toolchain
- **Gowin EDA** (>=v1.9.8): Official IDE — synthesis, P&R, bitstream generation. Supports Verilog SystemVerilog 2017.
- **OpenFPGALoader:** CLI tool for flashing bitstreams over USB-JTAG.
- **Icarus Verilog 12.0:** Open-source Verilog simulator used for all 13 testbenches.

## Build and Flash

```bash
# Sintesis
gw_sh final/build_rfft_scope.tcl

# Flasheo
openFPGALoader -b tangprimer20k final/rfft_scope/impl/pnr/rfft_scope.fs
```

## Drivers
- **Windows:** Install Gowin USB drivers or use Zadig (WinUSB/libusb-win32) for OpenFPGALoader.
- **Linux:** Install `libusb-1.0`, add udev rule for vendor `0403`, reload rules.
- **Debugger:** Onboard on Dock; external RV Debugger Plus required for Lite/core-only use (JST SH1.0 8-pin).
