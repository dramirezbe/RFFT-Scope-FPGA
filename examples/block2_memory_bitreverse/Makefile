.RECIPEPREFIX := >

IVERILOG = iverilog
VVP = vvp
PYTHON = python3

RTL = rtl/bit_reverse.v rtl/dual_port_ram_buffer.v rtl/permutation_controller.v

.PHONY: all test bit_reverse ram permutation1024 ready_pause scripts clean

all: test

test: bit_reverse ram permutation1024 ready_pause scripts

bit_reverse:
>$(IVERILOG) -o sim_bit_reverse tb/tb_bit_reverse.v rtl/bit_reverse.v
>$(VVP) sim_bit_reverse

ram:
>$(IVERILOG) -o sim_ram tb/tb_ram_buffer.v rtl/dual_port_ram_buffer.v
>$(VVP) sim_ram

permutation1024:
>$(IVERILOG) -o sim_perm_1024 tb/tb_permutation_1024.v $(RTL)
>$(VVP) sim_perm_1024

ready_pause:
>$(IVERILOG) -o sim_ready_pause tb/tb_permutation_ready_pause.v $(RTL)
>$(VVP) sim_ready_pause

scripts:
>$(PYTHON) scripts/bit_reverse_ref.py
>$(PYTHON) scripts/gen_ram_test.py

clean:
>rm -f sim_bit_reverse sim_ram sim_perm sim_perm_1024 sim_ready_pause
>rm -f *.vcd *.out *.fst
