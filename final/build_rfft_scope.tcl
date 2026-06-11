# Gowin Tcl build script - RFFT Scope completo (GW2A-18C)
# Usage: gw_sh final/build_rfft_scope.tcl
# Pipeline: UART/MAX9814 (B1) -> bit-reverse (B2) -> FFT compleja
# (B4, con butterfly+twiddle ROM del B3) -> recombinacion RFFT +
# drawer en LCD 800x480 (B5).

set script_dir [file normalize [file dirname [info script]]]

# ──────────────────────────────────────────
# Clean stale project (to avoid path caching)
# ──────────────────────────────────────────
file delete -force $script_dir/rfft_scope

# ──────────────────────────────────────────
# Project
# ──────────────────────────────────────────
create_project -name rfft_scope           \
               -dir  $script_dir          \
               -pn   GW2A-LV18PG256C8/I7  \
               -device_version C          \
               -force

# ──────────────────────────────────────────
# Source files
# ──────────────────────────────────────────
# Bloque 1 — UART RX, FIFO, ping-pong, packing
add_file $script_dir/src/block1/uart_rx.v              -type verilog
add_file $script_dir/src/block1/sample_fifo.v          -type verilog
add_file $script_dir/src/block1/sample_buffer.v        -type verilog
add_file $script_dir/src/block1/pack_real_to_complex.v -type verilog
add_file $script_dir/src/block1/block1_top.v           -type verilog
add_file $script_dir/src/block1/block1_i2s_top.v       -type verilog

# Bloque 2 — bit-reverse
add_file $script_dir/src/block2/bit_reverse.v                  -type verilog
add_file $script_dir/src/block2/dual_port_ram_buffer.v         -type verilog
add_file $script_dir/src/block2/permutation_controller.v       -type verilog
add_file $script_dir/src/block2/block2_memory_bitreverse_top.v -type verilog

# Bloque 3 — butterfly + twiddle ROM (del submodulo twiddle_butterfly)
add_file $script_dir/src/block3/butterfly_radix2.v -type verilog
add_file $script_dir/src/block3/twiddle_rom.v      -type verilog
add_file $script_dir/src/block3/twiddles_fft.hex     -type other
add_file $script_dir/src/block3/twiddles_recomb.hex  -type other
add_file $script_dir/src/block3/twiddles_fft.mi      -type other
add_file $script_dir/src/block3/twiddles_recomb.mi   -type other

# Bloque 4 — FFT core
add_file $script_dir/src/block4/working_memory.v       -type verilog
add_file $script_dir/src/block4/fft_stage_controller.v -type verilog
add_file $script_dir/src/block4/complex_fft_core.v     -type verilog

# Bloque 5 — recombinacion RFFT + drawer
add_file $script_dir/src/block5/rfft_recombine.v    -type verilog
add_file $script_dir/src/block5/spectrum_buffer.v   -type verilog
add_file $script_dir/src/block5/spectrum_draw.v     -type verilog
add_file $script_dir/src/block5/block5_lcd_drawer.v -type verilog

# LCD + PLL (de examples/sin_lcd via Block5_LCD_drawer)
add_file $script_dir/src/lcd/gowin_rpll/pll_40m.v -type verilog
add_file $script_dir/src/lcd/lcd_ctrl.v           -type verilog

# Top + constraints
add_file $script_dir/src/rfft_scope_top.v -type verilog
add_file $script_dir/src/rfft_scope.cst   -type cst

# ──────────────────────────────────────────
# Device
# ──────────────────────────────────────────
set_device GW2A-LV18PG256C8/I7 -device_version C

# ──────────────────────────────────────────
# Options
# ──────────────────────────────────────────
set_option -top_module   rfft_scope_top
set_option -verilog_std  sysv2017
set_option -output_base_name rfft_scope

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
