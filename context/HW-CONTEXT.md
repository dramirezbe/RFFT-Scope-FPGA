# Sipeed Tang Primer 20K

## FPGA Chip: Gowin GW2A-LV18PG256C8/I7
- LUT4: 20,736 | FF: 15,552 | Block SRAM: 828 Kbits | DSP Multipliers (18×18): 48 | PLLs: 4
- On-board: 1 Gbit (128 MB) DDR3 SDRAM + 32 Mbit SPI NOR Flash (W25Q32JVS)
- Form factor: DDR3 SODIMM core module; two ext-boards: **Dock** and **Lite**

## Extension Boards
- **Dock:** USB-JTAG & UART (onboard debugger), Ethernet PHY (10/100), USB 2.0 PHY, HDMI, DVP camera, RGB LCD, SPI LCD, audio (3.5 mm), MIC array, microSD. DIP switch #1 must be ON to enable core board.
- **Lite:** 4× PMOD + dual-row pin headers for raw I/O access.

## Toolchain
- **Gowin EDA** (≥v1.9.8): Official IDE — synthesis, P&R, bitstream generation. Supports Verilog/VHDL.
- **OpenFPGALoader:** CLI tool for flashing bitstreams over USB-JTAG.
- **LiteX / PicoRV32 / VexRiscv:** RISC-V soft-core frameworks; board can run C/C++ code or Linux after loading appropriate bitstream.

## Drivers
- **Windows:** Install Gowin USB drivers or use Zadig (WinUSB/libusb-win32) for OpenFPGALoader.
- **Linux:** Install `libusb-1.0`, add udev rule for vendor `0403`, reload rules.
- **Debugger:** Onboard on Dock; external RV Debugger Plus required for Lite/core-only use (JST SH1.0 8-pin).