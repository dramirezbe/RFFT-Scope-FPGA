# RFFT Context and Verilog Module Guide

This document defines the implementation path for a 16-bit, 2048-point real FFT intended for FPGA work. The goal is to move from research code to a verified, synthesizable RTL design using a testbench-first workflow.

## Target Design

- Input: 2048 real samples, 16-bit signed fixed-point.
- Output: 1025 unique frequency bins for a real FFT.
- Architecture: packed $N/2$ complex FFT flow, where $N = 2048$ and the internal complex FFT size is 1024.
- Fixed-point style: Q15-like arithmetic for coefficients and sample processing.

## Design Principle

For a real input sequence, the FFT output is Hermitian symmetric:

$$
X[k] = X^*[N-k]
$$

That means only $N/2 + 1$ bins are unique. The FPGA implementation should therefore avoid a full 2048-point complex FFT and instead use:

1. packing of real samples into complex pairs,
2. a 1024-point complex FFT core,
3. a recombination stage to recover the real-spectrum bins.

This is the right direction for reducing DSP, BRAM, and latency while keeping the design synthesizable.

## Recommended Verilog Module Split

The design should be separated into small modules that can each be tested independently.

| Module | Purpose | What it does |
| :--- | :--- | :--- |
| `rfft_top` | Top-level integration | Connects all submodules, handles start/ready/done control, and exposes the final RFFT interface. |
| `sample_buffer` | Input capture | Stores the 2048 real samples from the ADC or testbench input. This module should make the sample timing explicit. |
| `pack_real_to_complex` | Packing stage | Converts 2048 real samples into 1024 complex samples by placing even samples in the real lane and odd samples in the imaginary lane. |
| `bit_reverse` | Address ordering | Reorders samples into bit-reversed order if the FFT architecture needs it. This can be inside the buffer or the controller. |
| `twiddle_rom` | Coefficient storage | Provides sine/cosine constants in Q15 format for the FFT stages and the final recombination stage. |
| `butterfly_radix2` | Core arithmetic unit | Performs one radix-2 FFT butterfly on complex fixed-point values with scaling or saturation rules. |
| `fft_stage_controller` | Stage sequencing | Iterates through the 10 FFT stages needed for a 1024-point complex FFT and controls which butterflies operate. |
| `complex_fft_core` | 1024-point FFT | Implements the internal FFT core over packed complex data. This can be iterative, pipelined, or RAM-based. |
| `rfft_recombine` | Real FFT unpacking | Combines the complex FFT results into the final 1025 unique bins using the RFFT recombination equations. |
| `magnitude_calc` | Optional display/output | Converts complex bins into magnitude values for spectrum display or microphone analysis. |

## What Each Module Should Do

### 1. `sample_buffer`

This module stores the incoming 16-bit real samples. For a 2048-point design, it should accept exactly 2048 valid samples per frame.

Use it to:

- isolate the sample capture timing,
- make testbenches easy to write,
- allow future streaming or DMA input later.

### 2. `pack_real_to_complex`

This is the classic real-FFT packing step.

- Input sample 0 becomes complex real part 0.
- Input sample 1 becomes complex imaginary part 0.
- Input sample 2 becomes complex real part 1.
- Input sample 3 becomes complex imaginary part 1.

For 2048 real samples, the packed stream becomes 1024 complex samples.

### 3. `bit_reverse`

This module performs the address permutation required by an iterative FFT architecture.

If the FFT core already uses a streaming or digit-reversed structure, this module can be reduced or removed. If the core is memory-based, bit reversal is usually needed before the stage loop begins.

### 4. `twiddle_rom`

This module contains the sine and cosine coefficients in fixed-point form.

Its role is to:

- avoid computing trigonometric functions in hardware,
- provide deterministic values for simulation and synthesis,
- support stage-by-stage butterfly multiplication.

For the recombination stage, it also provides the $W_N^k$ terms needed to combine the packed FFT results.

### 5. `butterfly_radix2`

This is the arithmetic core of the design.

It should:

- accept two complex inputs,
- multiply by the twiddle factor,
- compute the sum and difference outputs,
- apply scaling to prevent overflow,
- optionally saturate instead of wrapping.

This module is one of the best candidates for early testbenches, because it is small and easy to compare against Python reference values.

### 6. `fft_stage_controller`

This module sequences the 1024-point FFT stages.

For a 1024-point complex FFT, it controls 10 stages. It should manage:

- stage index,
- butterfly index,
- read/write RAM addresses,
- twiddle index selection,
- start/done handshake.

### 7. `complex_fft_core`

This is the main internal FFT engine.

It processes the packed 1024 complex samples and produces the intermediate frequency bins used by the real FFT recombination step.

In a first version, this can be a simple iterative RAM-based core. Later, it can be optimized to a pipelined or streaming architecture.

### 8. `rfft_recombine`

This is the key RFFT-specific module.

It receives the 1024-point complex FFT output and reconstructs the 1025 unique bins of the 2048-point real FFT.

Responsibilities:

- compute DC and Nyquist bins,
- process bin pairs $k$ and $N/2-k$,
- apply conjugate symmetry,
- multiply by the recombination twiddle,
- output the final real-spectrum bins.

This module should be compared carefully against the Python reference model.

### 9. `magnitude_calc`

This is optional for the core FFT engine, but useful for audio visualization.

It converts complex output bins into magnitude values:

$$
|X[k]| = \sqrt{\Re(X[k])^2 + \Im(X[k])^2}
$$

In hardware, this may later become a CORDIC, a lookup-based approximation, or a squared-magnitude block depending on resource goals.

## Testbench-First Workflow

The project should be developed in this order:

1. Test `butterfly_radix2` alone.
2. Test `twiddle_rom` and coefficient generation.
3. Test `pack_real_to_complex` and `bit_reverse`.
4. Test a small iterative `complex_fft_core` with reference vectors.
5. Test `rfft_recombine` against the Python model.
6. Integrate everything into `rfft_top`.
7. Optimize fixed-point scaling, RAM usage, and timing.

This keeps the project manageable and makes debugging much easier.

## Optimization Path

After the functional version works, optimize in this order:

1. Reduce LUT and DSP use in butterflies.
2. Tune scaling to avoid overflow while preserving SNR.
3. Replace floating-point reference helpers with ROM-based fixed-point tables.
4. Minimize RAM ports and address conflicts.
5. Pipeline long arithmetic paths if timing fails.

## Current Scope

For now, keep the project scoped to:

- 16-bit signed input samples,
- 2048-point real FFT,
- 1024-point internal complex FFT,
- one verified Python reference model,
- one future synthesizable Verilog module set.

## Final Goal

The final FPGA project should have:

- a clean RTL hierarchy,
- one testbench per module,
- a validated Python reference model,
- fixed-point arithmetic matched between simulation and hardware,
- a top-level `rfft_top` module ready for board integration.