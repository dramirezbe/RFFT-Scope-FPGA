#!/usr/bin/env python3
# rfft-from-scratch.py

import math

def q15_mul(a, b):
    """Simulates a 16x16 multiplier returning the top 16 bits of a 32-bit result."""
    return (a * b) >> 15

def float_to_q15(val):
    """Converts ideal floating-point coefficients to 16-bit Q15 integers."""
    # Clamp to max 16-bit signed integer
    return int(max(min(val * 32768.0, 32767), -32768))

def generate_twiddle_rom_q15(n_half):
    """Generates Q15 integer Sine/Cosine ROMs."""
    w_real_rom = []
    w_imag_rom = []
    for i in range(n_half // 2):
        w_real_rom.append(float_to_q15(math.cos(-2 * math.pi * i / n_half)))
        w_imag_rom.append(float_to_q15(math.sin(-2 * math.pi * i / n_half)))
    return w_real_rom, w_imag_rom

def bit_reverse_address(i, bits):
    return int('{:0{width}b}'.format(i, width=bits)[::-1], 2)

def pack_and_permute_q15(real_input):
    """Packs 16-bit real samples into 16-bit [real, imag] RAM blocks."""
    n = len(real_input)
    n_half = n // 2
    bits = int(math.log2(n_half))
    
    # Init RAM blocks [Real, Imag]
    mem = [[real_input[2*i], real_input[2*i+1]] for i in range(n_half)]
    
    # In-place bit reversal
    for i in range(n_half):
        rev = bit_reverse_address(i, bits)
        if i < rev:
            mem[i], mem[rev] = mem[rev], mem[i]
            
    return mem

def butterfly_core_q15(u_r, u_i, v_in_r, v_in_i, wr, wi):
    """16-bit Fixed Point Radix-2 Butterfly with Gauss 3-Multiplier trick."""
    # 17-bit intermediate adders (Python handles this naturally)
    v_r_plus_i = v_in_r + v_in_i
    wi_minus_wr = wi - wr
    wr_plus_wi = wr + wi
    
    # Q15 DSP Multipliers
    k1 = q15_mul(wr, v_r_plus_i)
    k2 = q15_mul(v_in_r, wi_minus_wr)
    k3 = q15_mul(v_in_i, wr_plus_wi)
    
    # Result of complex multiplication
    v_r = k1 - k3
    v_i = k1 + k2
    
    # Butterfly Add/Sub with >> 1 scaling to prevent 16-bit overflow
    out_top_r = (u_r + v_r) >> 1
    out_top_i = (u_i + v_i) >> 1
    out_bot_r = (u_r - v_r) >> 1
    out_bot_i = (u_i - v_i) >> 1
    
    return [out_top_r, out_top_i], [out_bot_r, out_bot_i]

def compute_fft_stages_q15(mem, w_real_rom, w_imag_rom):
    """FFT Control Pipeline driving the 16-bit RAMs and ROMs."""
    n_half = len(mem)
    bits = int(math.log2(n_half))
    
    for stage in range(1, bits + 1):
        m = 2**stage
        m_half = m // 2
        rom_step = (n_half // 2) // m_half
        
        for k in range(0, n_half, m):
            for j in range(m_half):
                u_r, u_i = mem[k + j]
                v_in_r, v_in_i = mem[k + j + m_half]
                
                wr = w_real_rom[j * rom_step]
                wi = w_imag_rom[j * rom_step]
                
                # Execute Hardware Butterfly
                out_top, out_bot = butterfly_core_q15(u_r, u_i, v_in_r, v_in_i, wr, wi)
                
                mem[k + j] = out_top
                mem[k + j + m_half] = out_bot
                
    return mem

def unpack_rfft_q15(mem):
    """Recombines N/2 Complex into N/2+1 Real frequency bins using Q15 math."""
    n_half = len(mem)
    n = n_half * 2
    
    x_out = [[0, 0] for _ in range(n_half + 1)]
    
    # DC and Nyquist
    x_out[0] = [(mem[0][0] + mem[0][1]) >> 1, 0]
    x_out[n_half] = [(mem[0][0] - mem[0][1]) >> 1, 0]
    
    for k in range(1, n_half // 2 + 1):
        a_r, a_i = mem[k]
        b_r, b_i = mem[n_half - k]
        b_i = -b_i # Conjugate
        
        # Calculate Even/Odd components (scaled by 2)
        f_even_r, f_even_i = (a_r + b_r) >> 1, (a_i + b_i) >> 1
        
        # Multiply by -0.5j translates to swapping real/imag and negating
        f_odd_r, f_odd_i = (a_i - b_i) >> 1, -(a_r - b_r) >> 1
        
        # Q15 Twiddles for N points
        wr = float_to_q15(math.cos(-2 * math.pi * k / n))
        wi = float_to_q15(math.sin(-2 * math.pi * k / n))
        
        # Complex Multiply: wnk * f_odd
        k1 = q15_mul(wr, f_odd_r + f_odd_i)
        k2 = q15_mul(f_odd_r, wi - wr)
        k3 = q15_mul(f_odd_i, wr + wi)
        wnk_fodd_r = k1 - k3
        wnk_fodd_i = k1 + k2
        
        # Recombine (with one final >> 1 scale to prevent overflow)
        x_out[k] = [(f_even_r + wnk_fodd_r) >> 1, (f_even_i + wnk_fodd_i) >> 1]
        x_out[n_half - k] = [(f_even_r - wnk_fodd_r) >> 1, -(f_even_i - wnk_fodd_i) >> 1]
        
    return x_out

def top_level_rfft_q15(real_input_16bit):
    n = len(real_input_16bit)
    n_half = n // 2
    
    w_real_rom, w_imag_rom = generate_twiddle_rom_q15(n_half)
    mem = pack_and_permute_q15(real_input_16bit)
    mem = compute_fft_stages_q15(mem, w_real_rom, w_imag_rom)
    
    return unpack_rfft_q15(mem)