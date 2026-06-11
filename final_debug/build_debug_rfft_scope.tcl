# Gowin Tcl build script - RFFT Scope HIL Debug (GW2A-18C)
# Usage: gw_sh final_debug/build_debug_rfft_scope.tcl
# Pipeline: debug ROM player -> B1 (FIFO+pack) -> B2 (bit-reverse)
# -> B4 (FFT core + B3 butterfly/twiddle) -> B5 (recomb + drawer)
# -> LCD 800x480. Autonomous, no UART/ESP32.

set script_dir [file normalize [file dirname [info script]]]

file delete -force $script_dir/debug_rfft_scope

create_project -name debug_rfft_scope      \
               -dir  $script_dir           \
               -pn   GW2A-LV18PG256C8/I7   \
               -device_version C           \
               -force

# Copy .hex init files into the project tree so $readmemh resolves
# relative to the .gprj directory (SUG550 rule 1).
file mkdir $script_dir/debug_rfft_scope/src/block3
file copy -force $script_dir/src/block3/twiddles_fft.hex    \
                 $script_dir/debug_rfft_scope/src/block3/
file copy -force $script_dir/src/block3/twiddles_recomb.hex \
                 $script_dir/debug_rfft_scope/src/block3/
file mkdir $script_dir/debug_rfft_scope/src/debug_hex
file copy -force $script_dir/src/debug_hex/debug_vectors.hex \
                 $script_dir/debug_rfft_scope/src/debug_hex/

# --- Bloque 1 (debug variant: ROM player instead of UART) ---
add_file $script_dir/src/debug_test_rom_player.v -type verilog
add_file $script_dir/src/block1/sample_fifo.v          -type verilog
add_file $script_dir/src/block1/sample_buffer.v        -type verilog
add_file $script_dir/src/block1/pack_real_to_complex.v -type verilog
add_file $script_dir/src/block1/block1_top.v           -type verilog
add_file $script_dir/src/debug_block1_i2s_top.v        -type verilog

# --- Bloque 2 ---
add_file $script_dir/src/block2/bit_reverse.v                  -type verilog
add_file $script_dir/src/block2/dual_port_ram_buffer.v         -type verilog
add_file $script_dir/src/block2/permutation_controller.v       -type verilog
add_file $script_dir/src/block2/block2_memory_bitreverse_top.v -type verilog

# --- Bloque 3 (twiddle ROM with $readmemh) ---
add_file $script_dir/src/block3/butterfly_radix2.v -type verilog
add_file $script_dir/src/block3/twiddle_rom.v      -type verilog
add_file $script_dir/src/block3/twiddles_fft.hex     -type other
add_file $script_dir/src/block3/twiddles_recomb.hex  -type other

# --- Bloque 4 ---
add_file $script_dir/src/block4/working_memory.v       -type verilog
add_file $script_dir/src/block4/fft_stage_controller.v -type verilog
add_file $script_dir/src/block4/complex_fft_core.v     -type verilog

# --- Bloque 5 ---
add_file $script_dir/src/block5/rfft_recombine.v    -type verilog
add_file $script_dir/src/block5/spectrum_buffer.v   -type verilog
add_file $script_dir/src/block5/spectrum_draw.v     -type verilog
add_file $script_dir/src/block5/block5_lcd_drawer.v -type verilog

# --- LCD + PLL ---
add_file $script_dir/src/lcd/gowin_rpll/pll_40m.v -type verilog
add_file $script_dir/src/lcd/lcd_ctrl.v           -type verilog

# --- Debug test vectors ---
add_file $script_dir/src/debug_hex/debug_vectors.hex -type other

# --- Top + constraints ---
add_file $script_dir/src/debug_rfft_scope_top.v -type verilog
add_file $script_dir/src/debug_rfft_scope.cst   -type cst

# --- Device ---
set_device GW2A-LV18PG256C8/I7 -device_version C

# --- Options ---
set_option -top_module   debug_rfft_scope_top
set_option -verilog_std  sysv2017
set_option -output_base_name debug_rfft_scope

set_option -use_sspi_as_gpio 1
set_option -use_jtag_as_gpio 0

set_option -gen_sdf                  1
set_option -gen_posp                 1
set_option -gen_verilog_sim_netlist  1
set_option -gen_text_timing_rpt      1

set_option -bit_format  bin
set_option -bit_crc_check 1
set_option -bit_compress   1

run all

run close
