#!/usr/bin/env python3
"""
gen_e2e_vectors.py - vectores de prueba y golden para final/

Genera:
  tb/vectors/e2e_input.hex      2048 muestras Q15 (tono de prueba) que el
                                TB E2E envia por UART (1 por linea, 4 hex).
  tb/vectors/recomb_z_in.hex    Z[0..1023]: FFT compleja /1024 de la senal
                                empaquetada (entrada del TB unitario de
                                recombinacion). 32 bits {re,im} por linea.
  tb/vectors/recomb_x_gold.hex  X[0..511] golden de la recombinacion.
  tb/vectors/e2e_params.vh      parametros para los TB: bin del pico,
                                altura esperada de barra, etc.

Replica exactamente el escalado del hardware:
  FFT compleja con /2 por etapa (total /1024)  -> np.fft.fft(z)/1024
  Recombinacion: Xe + W2048^k * Xo (Q15, >>>1 en Xe/Xo como el RTL)
  Magnitud del drawer: max(|re|,|im|) + min/2 ; altura = mag >> 7
"""

import os
import numpy as np

FS     = 48000          # Hz (ESP32 / MAX9814)
N_REAL = 2048
N_CPLX = 1024
F_TONE = 3000.0         # Hz -> bin RFFT = F_TONE/FS*N_REAL = 128
AMP    = 0.8            # amplitud del tono (evita saturacion)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.normpath(os.path.join(HERE, "..", "tb", "vectors"))
os.makedirs(OUT, exist_ok=True)


def q15(x):
    return np.clip(np.round(np.asarray(x) * 32767.0), -32768, 32767).astype(np.int64)


def to_u16(v):
    return int(v) & 0xFFFF


# ── 1. senal de entrada (2048 reales Q15) ────────────────────
n = np.arange(N_REAL)
x = AMP * np.cos(2 * np.pi * F_TONE * n / FS)
x_q = q15(x)

with open(os.path.join(OUT, "e2e_input.hex"), "w") as f:
    for v in x_q:
        f.write(f"{to_u16(v):04x}\n")

# ── 2. pipeline golden ───────────────────────────────────────
# Bloque 1: empaquetado even/odd -> complejo.
# El top escala las muestras /2 (asr) antes del Bloque 4 para que
# la FFT nunca sature (cota |x| <= 0.5 en las 10 etapas).
z_re = x_q[0::2] >> 1            # asr bit-exact (>> de python = floor)
z_im = x_q[1::2] >> 1
z = z_re.astype(np.float64) + 1j * z_im.astype(np.float64)

# Bloques 2+4: FFT compleja escalada /1024 (el orden bit-reverse es
# interno; el resultado equivale a la FFT en orden natural)
Z = np.fft.fft(z) / N_CPLX
Z_re = np.clip(np.round(Z.real), -32768, 32767).astype(np.int64)
Z_im = np.clip(np.round(Z.imag), -32768, 32767).astype(np.int64)

with open(os.path.join(OUT, "recomb_z_in.hex"), "w") as f:
    for r, i in zip(Z_re, Z_im):
        f.write(f"{to_u16(r):04x}{to_u16(i):04x}\n")

# ── 3. recombinacion golden (misma aritmetica del RTL) ───────
def sat16(v):
    return max(-32768, min(32767, int(v)))


def mul_q15(a, b):
    return sat16((a * b) >> 15)


def asr1(v):
    return int(np.floor(v / 2)) if v >= 0 else -((-v + 1) // 2) if False else v >> 1


def recombine(zr, zi):
    """X[k] = Xe + W2048^k * Xo, k = 0,2,..,1022 (decimado x2 para
    cubrir 0..24 kHz en 512 columnas), bit-exact con el RTL."""
    xs = []
    for k in range(0, 1024, 2):
        ar, ai = int(zr[k]), int(zi[k])
        br, bi = int(zr[(N_CPLX - k) % N_CPLX]), int(zi[(N_CPLX - k) % N_CPLX])
        xe_r = (ar + br) >> 1          # >>> aritmetico (python >> es floor)
        xe_i = (ai - bi) >> 1
        xo_r = (ai + bi) >> 1
        xo_i = (-(ar - br)) >> 1
        th = 2 * np.pi * k / 2048.0
        twr = sat16(round(np.cos(th) * 32767))
        twi = sat16(round(-np.sin(th) * 32767))
        wo_r = sat16(mul_q15(twr, xo_r) - mul_q15(twi, xo_i))
        wo_i = sat16(mul_q15(twr, xo_i) + mul_q15(twi, xo_r))
        xs.append((sat16(xe_r + wo_r), sat16(xe_i + wo_i)))
    return xs


X = recombine(Z_re, Z_im)

with open(os.path.join(OUT, "recomb_x_gold.hex"), "w") as f:
    for r, i in X:
        f.write(f"{to_u16(r):04x}{to_u16(i):04x}\n")

# ── 4. prediccion de display (magnitud + altura de barra) ────
def mag_approx(r, i):
    a, b = abs(r), abs(i)
    return max(a, b) + (min(a, b) >> 1)


heights = [mag_approx(r, i) >> 6 for (r, i) in X]   # MAG_SHIFT=6 del top
peak_bin = int(np.argmax(heights))
peak_h   = heights[peak_bin]

with open(os.path.join(OUT, "e2e_params.vh"), "w") as f:
    f.write("// generado por scripts/gen_e2e_vectors.py - no editar\n")
    f.write(f"localparam E2E_PEAK_BIN = {peak_bin};   // {F_TONE/1000:.1f} kHz\n")
    f.write(f"localparam E2E_PEAK_H   = {peak_h};\n")

print(f"Tono {F_TONE/1000:.1f} kHz, fs={FS/1000:.0f} kHz, amp={AMP}")
print(f"Bin RFFT esperado: {F_TONE/FS*N_REAL:.0f} -> pico golden en bin {peak_bin}")
print(f"Altura de barra esperada: {peak_h} px (mag>>6)")
print(f"Vectores escritos en {OUT}/")
