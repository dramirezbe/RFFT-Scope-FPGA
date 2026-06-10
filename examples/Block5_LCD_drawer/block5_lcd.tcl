# Gowin Tcl build script for the Block5 LCD spectrum drawer (GW2A-18C)
# Usage: gw_sh examples/Block5_LCD_drawer/block5_lcd.tcl
# Demo standalone: fft_stim_gen emula al Bloque 4; para el pipeline real
# conectar complex_fft_core en top.v y quitar el generador.

set script_dir [file normalize [file dirname [info script]]]

# ──────────────────────────────────────────
# Clean stale project (to avoid path caching)
# ──────────────────────────────────────────
file delete -force $script_dir/block5_lcd

# ──────────────────────────────────────────
# Project
# ──────────────────────────────────────────
create_project -name block5_lcd           \
               -dir  $script_dir          \
               -pn   GW2A-LV18PG256C8/I7  \
               -device_version C          \
               -force

# ──────────────────────────────────────────
# Source files
# ──────────────────────────────────────────
add_file $script_dir/src/gowin_rpll/pll_40m.v   -type verilog
add_file $script_dir/src/lcd_ctrl.v             -type verilog
add_file $script_dir/src/spectrum_buffer.v      -type verilog
add_file $script_dir/src/spectrum_draw.v        -type verilog
add_file $script_dir/src/block5_lcd_drawer.v    -type verilog
add_file $script_dir/src/fft_stim_gen.v         -type verilog
add_file $script_dir/src/top.v                  -type verilog
add_file $script_dir/src/block5_lcd.cst         -type cst

# ──────────────────────────────────────────
# Device
# ──────────────────────────────────────────
set_device GW2A-LV18PG256C8/I7 -device_version C

# ──────────────────────────────────────────
# Options
# ──────────────────────────────────────────
set_option -top_module   top
set_option -verilog_std  sysv2017
set_option -output_base_name block5_lcd

# Dual-purpose pins
set_option -use_sspi_as_gpio 1
set_option -use_jtag_as_gpio 0

# PnR outputs
set_option -gen_sdf                  1
set_option -gen_posp                 1
set_option -gen_verilog_sim_netlist  1
set_option -gen_text_timing_rpt     1

# Bitstream
set_option -bit_format  bin
set_option -bit_crc_check 1
set_option -bit_compress   1

# ──────────────────────────────────────────
# Build
# ──────────────────────────────────────────
run all

run close
