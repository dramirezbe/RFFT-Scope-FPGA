# RFFT Pipeline — Block Assignments

The design is split into five blocks, each owned by a different developer. Every block includes the Verilog modules, their interfaces, the testbenches, and the Python scripts needed to verify them independently before integration.

A common Python golden model (`rfft_golden.py`) using `numpy.fft.rfft(x, n=2048) / 1024` provides the global scaling reference shared by all blocks.

---

## Block 1 – Front-End, Packing and Q15

**Owner:** Developer 1

### Physical Front-End

A **MAX9814** electret microphone module with automatic gain control feeds an **ESP32** that performs ADC sampling and direct Q15 conversion. The ESP32 exposes two GPIO lines to the FPGA:

| GPIO | Signal | Description |
|---|---|---|
| 1 | `q15_data[15:0]` | 16-bit Q15 sample from the ESP32's ADC, updated when a new sample is ready. |
| 2 | `q15_clk` | Toggle signal — each rising edge indicates a new Q15 sample is stable on `q15_data`. |

### Verilog Modules

| Module | Function |
|---|---|
| `sample_buffer` | Captures 2048 real Q15 samples from the ESP32 front-end using the `q15_clk` toggle protocol and generates `frame_done`. |
| `pack_real_to_complex` | Converts the 2048 real samples into 1024 complex pairs: `z[m] = x[2m] + j·x[2m+1]`. |

### Input Interface (from ESP32 / external pins)

| Signal | Description |
|---|---|
| `clk` | System clock, ≥ 50 MHz (FPGA domain, used for synchronisation) |
| `rst_n` | Active-low reset |
| `q15_data[15:0]` | Q15 sample from ESP32 ADC |
| `q15_clk` | Toggle from ESP32 — rising edge marks a valid sample |

### Output Interface (to Block 2)

| Signal | Description |
|---|---|
| `complex_real[15:0]`, `complex_imag[15:0]` | Complex pair in Q15 |
| `complex_valid` | Pulse every 1024 clock cycles, when a full frame is ready |
| `frame_start` | Marks the beginning of a new frame |

### Testbenches and Scripts

- **`test_sample_buffer.py`**: generates 2048 sinusoidal samples (e.g. 440 Hz @ 48 kHz) in Q15.
- **`tb_sample_buffer.v`**: simulates the serial input and checks `frame_done`.
- **`tb_pack.v`**: verifies that the complex output matches the packing formula.

---

## Block 2 – Memory and Bit-Reverse Reordering

**Owner:** Developer 2

### Verilog Modules

| Module | Function |
|---|---|
| `bit_reverse` | Computes bit-reversed addresses for indices 0 to 1023 (10 bits). |
| `dual_port_ram_buffer` | Stores the 1024 complex words in natural order and reads them back in bit-reversed order. |
| `permutation_controller` | FSM that manages the write/read sequencing of the permutation buffer. |

### Input Interface (from Block 1)

| Signal | Description |
|---|---|
| `complex_real[15:0]`, `complex_imag[15:0]` | Complex data from Block 1 |
| `complex_valid`, `frame_start` | Handshake from Block 1 |

### Output Interface (to Block 4 – FFT Controller)

| Signal | Description |
|---|---|
| `br_real[15:0]`, `br_imag[15:0]` | Data in bit-reversed order |
| `br_valid` | Pulse per complex word (1024 per frame) |
| `br_ready` | Handshake with the FFT controller to prevent data overwrite |

### Testbenches and Scripts

- **`test_bit_reverse.py`**: list of indices and their bit-reversed values (N=1024).
- **`tb_bit_reverse.v`**: checks with N=8, 16, 1024.
- **`tb_ram_buffer.v`**: simulates sequential write and bit-reversed read; compares output against Python.

---

## Block 3 – Math Unit and Twiddle ROM

**Owner:** Developer 3

### Verilog Modules

| Module | Function |
|---|---|
| `twiddle_rom` | Dual ROM: 512 twiddles (32-bit each) for the FFT core, and 1025 twiddles for the recombination stage. |
| `butterfly_radix2` | Complex butterfly using 4 DSP multipliers, 15-bit right-shift with saturation, plus one extra shift bit per stage. |

### Input Interface (from Block 4)

| Signal | Description |
|---|---|
| `e_real[15:0]`, `e_imag[15:0]` | Even term |
| `o_real[15:0]`, `o_imag[15:0]` | Odd term |
| `twiddle_real[15:0]`, `twiddle_imag[15:0]` | Twiddle factor |
| `butterfly_en` | Enables computation |

### Output Interface (to Block 4)

| Signal | Description |
|---|---|
| `z1_real[15:0]`, `z1_imag[15:0]` | `E + W·O` |
| `z2_real[15:0]`, `z2_imag[15:0]` | `E - W·O` |
| `butterfly_done` | Computation ready, 1 cycle after enable |

### Testbenches and Scripts

- **`gen_twiddles.py`**: generates Wk_1024 (k=0..511) and Wk_2048 (k=0..1024) tables in Q15; produces `.mi` memory init files and C/Python coefficient arrays.
- **`test_butterfly.py`**: test cases with integer values (e.g. E=0.5, O=0.5, W=1) and corner cases (e.g. 0.9999).
- **`tb_butterfly.v`**: compares Q15 output against the Python model using the same multiply-and-shift routine.

**Note:** This block must deliver a quantization-error verification report (±2 LSB after accumulating the rounding errors of all four multiplications).

---

## Block 4 – Complex FFT Core Controller

**Owner:** Developer 4

### Verilog Modules

| Module | Function |
|---|---|
| `complex_fft_core` | Main FSM that iterates through the 10 radix-2 DIT stages. |
| `fft_stage_controller` | Generates read addresses, strides, and twiddle indices for each stage; controls the butterfly. |
| `working_memory` | Two dual-port RAM banks for ping-pong buffering between stages. |

### Input Interface (from Block 2)

| Signal | Description |
|---|---|
| `br_real[15:0]`, `br_imag[15:0]` | Bit-reversed data |
| `br_valid` | Data valid |
| `br_ready` | Ready for data |

Also from Block 3: `butterfly_done`.

### Output Interface (to Block 5)

| Signal | Description |
|---|---|
| `fft_real[15:0]`, `fft_imag[15:0]` | Complex spectrum Z[k], already scaled by 1/1024 |
| `fft_valid` | Pulse when all 1024 values are ready |
| `fft_done` | End of frame |

### Internal Interface with Block 3

| Signal | Description |
|---|---|
| `e_real`, `e_imag`, `o_real`, `o_imag` | Operands to butterfly |
| `tw_real`, `tw_imag` | Twiddle factor to butterfly |
| `butterfly_en` | Butterfly enable |

### Testbenches and Scripts

- **`test_fft_core.py`**: uses `numpy.fft.fft` on packed complex sequences (generated from real data); scales the result by 1/1024.
- **`tb_complex_fft.v`**: small cases (N=8, N=64), comparing against Python.
- **`tb_full_1024.v`**: test with a real 440 Hz tone already packed; checks SNR > 40 dB.

**Critical constraint:** The controller must apply the 1-bit-per-stage shift (configurable in the butterfly). Verification must use the same 1/1024 factor as the Python model.

---

## Block 5 – RFFT Post-Processing and Magnitude

**Owner:** Developer 5

### Verilog Modules

| Module | Function |
|---|---|
| `rfft_recombine` | Implements recombination equations (12) through (16) from the design document. |
| `magnitude_calc` | Computes `sqrt(Re² + Im²)` for each bin (optional; may output only the real part if only real-spectrum display is needed). |

### Input Interface (from Block 4)

| Signal | Description |
|---|---|
| `fft_real[15:0]`, `fft_imag[15:0]` | FFT output |
| `fft_valid`, `fft_done` | Handshake from Block 4 |

Also from Block 3: `twiddle_recomb_real[15:0]`, `twiddle_recomb_imag[15:0]` (Wk_2048 coefficients).

### Output Interface (to display / UART)

| Signal | Description |
|---|---|
| `bin_index[10:0]` | Bin index, 0 to 1024 |
| `bin_value[15:0]` | Q15 magnitude or real part |
| `bin_valid` | Pulse per bin (1025 per frame) |

### Testbenches and Scripts

- **`test_rfft_recombine.py`**: applies the recombination equations to the complex FFT output (simulated) and compares with scaled `numpy.fft.rfft`.
- **`tb_recombine.v`**: special cases — impulse (x[0]=1), pure tone, DC bin, and Nyquist bin.
- **`tb_magnitude.v`**: verifies magnitude is in range [0, 32767] and that the peak for a pure tone is correct.

**Scaling note:** The recombination stage must use the same Q15 twiddles and apply the same shift/saturation rules. DC and Nyquist bins (equations 15–16) are purely real.
