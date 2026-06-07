import numpy as np

N = 1024
k_tone = 64

n = np.arange(N)
x_real = np.cos(2 * np.pi * k_tone * n / N)

# Escalar a Q15
x_q15 = np.clip(np.round(x_real * 32767), -32768, 32767).astype(np.int16)

# === CORRECCIÓN: Crear 1024 puntos complejos ===
# Opción 1: Zero-padding imaginario (la más común para prueba)
z_complex = x_q15.astype(np.float64) + 1j * np.zeros(N, dtype=np.float64)

# Opción 2 (si quieres emular packing real): 
# z_complex = x_q15[0::2].astype(np.float64) + 1j * x_q15[1::2].astype(np.float64)
# z_complex = np.concatenate([z_complex, np.zeros(512, dtype=np.complex128)])

# FFT de referencia (escalada 1/1024)
X = np.fft.fft(z_complex) / 1024.0

# Bit-reverse indices (0 a 1023)
br_idx = [int(f'{i:010b}'[::-1], 2) for i in range(N)]

# Guardar entrada en orden bit-reversed
with open("input_br.hex", "w") as f:
    for i in br_idx:
        re = int(np.real(z_complex[i])) & 0xFFFF
        im = int(np.imag(z_complex[i])) & 0xFFFF
        f.write(f"{re:04X}{im:04X}\n")

# Guardar salida esperada
with open("expected_fft.hex", "w") as f:
    for k in range(N):
        re = int(np.clip(np.round(np.real(X[k])), -32768, 32767)) & 0xFFFF
        im = int(np.clip(np.round(np.imag(X[k])), -32768, 32767)) & 0xFFFF
        f.write(f"{re:04X}{im:04X}\n")

print(f"Bin {k_tone} esperado: re={np.real(X[k_tone]):.1f}, im={np.imag(X[k_tone]):.1f}")
print("Archivos generados correctamente: input_br.hex y expected_fft.hex")