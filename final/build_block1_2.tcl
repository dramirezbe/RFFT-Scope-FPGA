# Gowin Tcl build script for the Block1 + Block2 fusion (GW2A-18C)
# Usage: gw_sh final/build_block1_2.tcl
# Builds: UART acquisition + complex packing (Block 1) fused with the
#         bit-reverse permutation memory (Block 2).

set script_dir [file dirname [info script]]

# ──────────────────────────────────────────
# Project
# ──────────────────────────────────────────
create_project -name block1_2_fusion      \
               -dir  $script_dir          \
               -pn   GW2A-LV18PG256C8/I7  \
               -device_version C          \
               -force

# ──────────────────────────────────────────
# Source files (relative to script_dir)
# ──────────────────────────────────────────
# Block 1 — UART RX, FIFO, ping-pong buffer, complex packing
add_file src/block1/uart_rx.v              -type verilog
add_file src/block1/sample_fifo.v          -type verilog
add_file src/block1/sample_buffer.v        -type verilog
add_file src/block1/pack_real_to_complex.v -type verilog
add_file src/block1/block1_top.v           -type verilog
add_file src/block1/block1_i2s_top.v       -type verilog

# Block 2 — bit-reverse permutation memory
add_file src/block2/bit_reverse.v                  -type verilog
add_file src/block2/dual_port_ram_buffer.v         -type verilog
add_file src/block2/permutation_controller.v       -type verilog
add_file src/block2/block2_memory_bitreverse_top.v -type verilog

# Fusion top + constraints
add_file src/rfft_block1_2_top.v -type verilog
add_file src/rfft_block1_2.cst   -type cst

# ──────────────────────────────────────────
# Device
# ──────────────────────────────────────────
set_device GW2A-LV18PG256C8/I7 -device_version C

# ──────────────────────────────────────────
# Options
# ──────────────────────────────────────────
set_option -top_module   rfft_block1_2_top
set_option -verilog_std  sysv2017
set_option -output_base_name block1_2_fusion

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
