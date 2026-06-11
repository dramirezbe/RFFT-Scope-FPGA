import numpy as np
import matplotlib.pyplot as plt

# --- 1. System Parameters ---
FS = 48000
N_SAMPLES = 2048
t = np.arange(N_SAMPLES) / FS

# --- 2. Generate Signals ---
# Signal A: 3 kHz clean tone (from gen_e2e_vectors.py)
F_TONE_A = 3000.0
sig_a = 0.5 * np.cos(2 * np.pi * F_TONE_A * t)
# Convert to Q15
q15_a = np.clip(np.round(sig_a * 32767.0), -32768, 32767).astype(np.float64)

# Signal B: 5 kHz tone with Gaussian noise (from HIL debug script)
F_TONE_B = 5000.0
sigma = 0.048  # Picking a mid-level noise vector
noise = np.random.normal(0.0, sigma, N_SAMPLES)
sig_b = 0.5 * np.sin(2 * np.pi * F_TONE_B * t) + noise
# Convert to Q15
sig_b_clipped = np.clip(sig_b, -1.0, 1.0 - 2.0**-15)
q15_b = np.clip(np.round(sig_b_clipped * 32768.0), -32768, 32767).astype(np.float64)

# --- 3. Compute RFFT ---
# np.fft.rfft automatically computes only the positive frequencies for real inputs
fft_a = np.fft.rfft(q15_a)
fft_b = np.fft.rfft(q15_b)

# Get the frequency bins for the x-axis
freqs = np.fft.rfftfreq(N_SAMPLES, d=1.0/FS)

# Calculate magnitude and scale it down by N_SAMPLES to match the physical amplitude
mag_a = np.abs(fft_a) / (N_SAMPLES / 2)  # Scale by N/2 to get Q15 amplitude
mag_b = np.abs(fft_b) / (N_SAMPLES / 2)

# --- 4. Plotting ---
fig, axs = plt.subplots(2, 2, figsize=(14, 8))
fig.suptitle("Q15 Test Vectors and RFFT Analysis", fontsize=16)

# Time Domain: 3 kHz Clean
axs[0, 0].plot(t[:200] * 1000, q15_a[:200], color='blue') # Plotting first 200 samples
axs[0, 0].set_title("Time Domain: 3 kHz Clean (Q15)")
axs[0, 0].set_xlabel("Time (ms)")
axs[0, 0].set_ylabel("Amplitude (Q15)")
axs[0, 0].grid(True)

# Time Domain: 5 kHz Noisy
axs[0, 1].plot(t[:200] * 1000, q15_b[:200], color='orange')
axs[0, 1].set_title(f"Time Domain: 5 kHz + Noise (Q15, sigma={sigma})")
axs[0, 1].set_xlabel("Time (ms)")
axs[0, 1].set_ylabel("Amplitude (Q15)")
axs[0, 1].grid(True)

# Frequency Domain: 3 kHz Clean
axs[1, 0].plot(freqs, mag_a, color='blue')
axs[1, 0].set_title("RFFT Spectrum: 3 kHz")
axs[1, 0].set_xlabel("Frequency (Hz)")
axs[1, 0].set_ylabel("Magnitude")
axs[1, 0].set_xlim(0, 10000) # Zoom in up to 10 kHz to see the peak clearly
axs[1, 0].grid(True)

# Frequency Domain: 5 kHz Noisy
axs[1, 1].plot(freqs, mag_b, color='orange')
axs[1, 1].set_title("RFFT Spectrum: 5 kHz + Noise")
axs[1, 1].set_xlabel("Frequency (Hz)")
axs[1, 1].set_ylabel("Magnitude")
axs[1, 1].set_xlim(0, 10000)
axs[1, 1].grid(True)

plt.tight_layout()
plt.show()