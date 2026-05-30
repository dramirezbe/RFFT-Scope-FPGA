# SSPI as I/O Configuration Guide

## What is SSPI?

SSPI (Serial System Programming Interface) is a set of dedicated pins on Gowin
FPGAs used for device programming and configuration via JTAG+UART. On boards
like the Sipeed Tang Primer 20K/25K, the SSPI pins are hardwired to the
onboard crystal oscillator or programming logic.

**Default behavior:** SSPI pins are **reserved** for configuration and CANNOT
be used as general-purpose I/O (GPIO) unless explicitly reconfigured.

**Common error:** `Error (PR2017)` when constraining SSPI pins as regular I/O
without enabling the dual-purpose pin setting.

---

## GUI Method

`Project → Configuration → Dual-Purpose Pin → ☑ Use SSPI as Regular IO`

Also check related options:
- **"Use JTAG as Regular IO"** — if you need JTAG pins as GPIO
- **"Use CPU as Regular IO"** — on SoC devices (GW1NS-4C, GW5AS-25) with
  embedded ARM/RISC-V cores

---

## Tcl Method (gw_sh CLI)

```tcl
# Enable SSPI pins as general-purpose I/O
set_option -use_sspi_as_gpio 1

# Disable (default)
set_option -use_sspi_as_gpio 0
```

Place this **before** `run all` / `run pnr` in your build script.

### All Dual-Purpose Pin Options (Tcl)

```tcl
set_option -use_sspi_as_gpio      <0|1>   # SSPI pins as GPIO
set_option -use_mspi_as_gpio      <0|1>   # MSPI pins as GPIO
set_option -use_jtag_as_gpio      <0|1>   # JTAG pins as GPIO
set_option -use_ready_as_gpio     <0|1>   # READY pin as GPIO
set_option -use_done_as_gpio      <0|1>   # DONE pin as GPIO
set_option -use_reconfign_as_gpio <0|1>   # RECONFIG_N pin as GPIO
set_option -use_i2c_as_gpio       <0|1>   # I2C pins as GPIO
```

### Alternative format (device.cfg style)

```tcl
set SSPI regular_io = true     # Enable
set SSPI regular_io = false    # Disable
```

---

## Impact

Enabling SSPI as GPIO repurposes these pins:
- `SSPI_CS_N` → GPIO
- `SSPI_CLK`  → GPIO
- `SI`        → GPIO
- `SO`        → GPIO
- `CLKHOLD_N` → GPIO

**Caveat:** After setting SSPI pins as GPIO, you may lose the ability to
program the device via the standard background programming mode. For
development, use direct JTAG programming or an external programmer instead.

---

## Example: sin_rgb.tcl

See [`sin_rgb.tcl`](sin_rgb.tcl) for a complete build script using this option.

---

## Sources

- Gowin Software User Guide SUG100-4.4.2E, Section 8.3.19 (`set_option`)
- `multipurposeconfig.xml` in Gowin IDE (GUI-to-Tcl mapping)
- `device.cfg` in Gowin IDE share/config
- Gowin FPGA community forum / EEVblog FPGA board
