# Gowin Tcl build script for sin_rgb (GW2A-18C)
# Usage: gw_sh examples/sin_lcd/sin_rgb.tcl
# Run from RFFT-Scope-FPGA project root (anywhere with gw_sh alias).

set script_dir [file dirname [info script]]
set project_dir [file dirname $script_dir]

# ──────────────────────────────────────────
# Project
# ──────────────────────────────────────────
create_project -name sin_lcd           \
               -dir  $project_dir      \
               -pn   GW2A-LV18PG256C8/I7 \
               -device_version C         \
               -force

# ──────────────────────────────────────────
# Source files (relative to project_dir)
# ──────────────────────────────────────────
add_file src/gowin_rpll/pll_40m.v   -type verilog
add_file src/lcd_ctrl.v             -type verilog
add_file src/lcd_data.v             -type verilog
add_file src/top.v                  -type verilog
add_file src/sin_rgb.cst            -type cst
add_file src/sin_lut.mem            -type other

# ──────────────────────────────────────────
# Device
# ──────────────────────────────────────────
set_device GW2A-LV18PG256C8/I7 -device_version C

# ──────────────────────────────────────────
# Options
# ──────────────────────────────────────────
set_option -top_module   top
set_option -synthesis_tool GowinSynthesis
set_option -verilog_std  sysv2017
set_option -output_base_name sin_rgb

# Dual-purpose pins
set_option -use_sspi_as_gpio 1
set_option -use_jtag_as_gpio 0

# PnR outputs
set_option -gen_sdf                  1
set_option -gen_posp                 1
set_option -gen_verilog_sim_netlist  1
set_option -gen_text_timing_rpt      1

# Bitstream
set_option -bit_format  bin
set_option -bit_crc_check 1
set_option -bit_compress   1

# ──────────────────────────────────────────
# Build
# ──────────────────────────────────────────
run all

run close
