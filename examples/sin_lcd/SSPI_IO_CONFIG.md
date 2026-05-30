# Enabling Dual-Purpose Pins as Regular I/O in Gowin IDE

## Problem

When using certain FPGA pins that have dual purpose (e.g., SSPI, JTAG, MODE), Gowin Place & Route will reject them with errors:

```
ERROR (PR2017) : 'lcd_r[2]' cannot be placed according to constraint, for the location is a dedicated pin (SSPI)
ERROR (PR2028) : The constrained location is useless in current package
```

This happens because N9 (IOR36[B]) defaults to SSPI_CS_N/D0 function and must be explicitly reconfigured as a regular I/O.

## Solution

### Method 1: Gowin IDE GUI (Recommended)

1. Open your project in Gowin IDE
2. Click **Project** in the top menu bar
3. Select **Configuration** from the dropdown
4. In the left panel, navigate to **Place & Route** → **Dual-Purpose Pin**
5. Locate the pin that needs to be reconfigured:
   - For Tang Primer 20K Dock `lcd_r[2]`: pin **N9** (IOR36[B], SSPI_CS_N/D0)
6. Change its setting from the dedicated function to **Regular I/O** (or `ENABLE` / `AS_USER_PIN`)
7. Click **OK** and re-run Place & Route

![Dual Purpose Pin Configuration](https://raw.githubusercontent.com/sipeed/TangPrimer-20K-example/main/.assets/rp2017.png)

### Method 2: Project File Configuration

Alternatively, the setting is stored in the `.prj` project file. You can add the pin to the dual-purpose enable list manually.

## Common Dual-Purpose Pins on GW2A-LV18PG256C8/I7 (Tang Primer 20K)

| Pin  | Default Function | Location | Used By         |
|------|-----------------|----------|-----------------|
| N9   | SSPI_CS_N/D0    | IOR36[B] | lcd_r[2]        |
| R9   | FASTRD_N/D3     | IOR35[A] | lcd_clk          |
| T10  | SI/D2           | IOR35[B] | Reset (RST_N)   |
| M8   | SO/D1           | IOR36[A] | SD card DAT0     |
| T9   | DIN/CLKHOLD_N   | IOR38[A] | --               |
| P9   | DOUT/WE_N       | IOR38[B] | --               |

## Verifying the Fix

After enabling the pin, re-run synthesis + PNR. The pinout report should show the pin placed successfully with its user function rather than the dedicated function name.

## Reference

- [Tang Primer 20K Example - Error code RP2017](https://github.com/sipeed/TangPrimer-20K-example#error-coderp2017)
- [Gowin Semiconductor - Dual Purpose Pin Configuration](https://www.gowinsemi.com)
