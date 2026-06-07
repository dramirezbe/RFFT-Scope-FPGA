# Block 2 – Memory and Bit-Reversal Reordering

## Overview

This repository contains the implementation of **Block 2 – Memory and Bit-Reversal Reordering** for a 1024-point Radix-2 FFT architecture targeting the **Tang Primer 20K FPGA**.

The purpose of this block is to:

1. Receive complex samples from Block 1.
2. Store incoming data into a dual-port RAM buffer.
3. Reorder samples using bit-reversed addressing.
4. Deliver reordered samples to the FFT Controller (Block 4) through a valid/ready handshake interface.

---

## Project Structure

```text
block2_memory_bitreverse/
│
├── README.md
│
├── readme/
│   └── README_BLOCK2.md
│
├── rtl/
│   ├── bit_reverse.v
│   ├── dual_port_ram_buffer.v
│   ├── permutation_controller.v
│   └── block2_memory_bitreverse_top.v
│
├── tb/
│   ├── tb_bit_reverse.v
│   ├── tb_ram_buffer.v
│   ├── tb_permutation.v
│   ├── tb_permutation_1024.v
│   └── tb_permutation_ready_pause.v
│
├── scripts/
│   ├── bit_reverse_ref.py
│   └── gen_ram_test.py
│
├── Makefile
└── .gitignore
```

---

## Main Modules

### bit_reverse

Computes the bit-reversed address associated with a given index.

### dual_port_ram_buffer

Stores complex samples using separate memories for real and imaginary components.

### permutation_controller

Implements the FSM responsible for:

* RAM write operations
* Bit-reversed address generation
* Memory read control
* Valid/ready handshake management

### block2_memory_bitreverse_top

Top-level integration module of Block 2.

---

## Validation Results

The following tests have been successfully completed:

* Bit-reversal validation (N = 8, 16, 1024)
* Dual-port RAM verification
* Permutation controller verification
* 1024-point frame validation
* Valid/ready handshake verification
* Pause-and-resume handshake validation

---

## Simulation

Run all available tests:

```bash
make test
```

Clean generated simulation files:

```bash
make clean
```

---

## Documentation

Detailed technical documentation is available in:

```text
readme/README_BLOCK2.md
```

---

## Target Platform

* FPGA: Tang Primer 20K
* FFT Size: 1024 points
* Data Format: Signed Q15 Fixed-Point
* Architecture: Radix-2 Decimation-In-Time (DIT)

---

## Authors

Digital Systems Design Verification Project

Block 2 Development Team
