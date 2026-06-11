#!/usr/bin/env python3
"""Generate Q15 test vectors (noise-free diverse signals) for RFFT debug HIL.

V0: Pure 5 kHz sine     — single narrow peak at col 107
V1: Pure 3 kHz sine     — peak at col 64  (3 kHz label)
V2: Pure 10 kHz sine    — peak at col 213
V3: Rectangular 5 kHz   — fundamental + odd harmonics
V4: Delta/impulse       — flat spectrum, all bins lit
V5: DC constant         — peak only at bin 0
V6: Chirp 1–12 kHz     — broadband spread
V7: Two-tone 3+8 kHz    — two distinct peaks

Output: src/debug_hex/debug_vectors.hex (concatenated)
        src/debug_hex/debug_metadata.json
"""

import json
import math
import numpy as np
import os

FS          = 48000
N_SAMPLES   = 2048
AMPLITUDE   = 0.5
OUT_DIR     = os.path.join(os.path.dirname(__file__), "..", "src", "debug_hex")
os.makedirs(OUT_DIR, exist_ok=True)

t = np.arange(N_SAMPLES, dtype=np.float64) / FS

def to_q15(arr):
    clipped = np.clip(arr, -1.0, 1.0 - 2.0**-15)
    q15 = np.round(clipped * 32768.0).astype(np.int32)
    return np.clip(q15, -32768, 32767) & 0xFFFF

vectors = {}
metadata = {}

# V0 — pure 5 kHz sine
v = AMPLITUDE * np.sin(2.0 * math.pi * 5000 * t)
vectors["V0"] = to_q15(v)
metadata["V0"] = {"signal": "sine 5 kHz", "peak": "col 107", "amp": AMPLITUDE}

# V1 — pure 3 kHz sine
v = AMPLITUDE * np.sin(2.0 * math.pi * 3000 * t)
vectors["V1"] = to_q15(v)
metadata["V1"] = {"signal": "sine 3 kHz", "peak": "col 64", "amp": AMPLITUDE}

# V2 — pure 10 kHz sine
v = AMPLITUDE * np.sin(2.0 * math.pi * 10000 * t)
vectors["V2"] = to_q15(v)
metadata["V2"] = {"signal": "sine 10 kHz", "peak": "col 213", "amp": AMPLITUDE}

# V3 — rectangular wave 5 kHz (50% duty)
freq   = 5000
period = FS / freq
v = np.zeros(N_SAMPLES, dtype=np.float64)
for n in range(N_SAMPLES):
    if (n % int(period / 2)) < (period / 4):
        v[n] = AMPLITUDE
    else:
        v[n] = -AMPLITUDE
vectors["V3"] = to_q15(v)
metadata["V3"] = {"signal": "rect 5 kHz", "peaks": "fundamental 5 kHz + odd harmonics", "amp": AMPLITUDE}

# V4 — delta/impulse (single non-zero at sample 0)
v = np.zeros(N_SAMPLES, dtype=np.float64)
v[0] = AMPLITUDE
vectors["V4"] = to_q15(v)
metadata["V4"] = {"signal": "delta n=0", "peaks": "flat spectrum (all bins)", "amp": AMPLITUDE}

# V5 — DC constant
v = np.full(N_SAMPLES, AMPLITUDE, dtype=np.float64)
vectors["V5"] = to_q15(v)
metadata["V5"] = {"signal": "DC constant", "peak": "bin 0 only", "amp": AMPLITUDE}

# V6 — linear chirp 1 kHz to 12 kHz
f_start = 1000.0
f_end   = 12000.0
phase   = np.cumsum(2.0 * math.pi * (f_start + (f_end - f_start) * t / (N_SAMPLES / FS)) / FS)
v = AMPLITUDE * np.sin(phase)
vectors["V6"] = to_q15(v)
metadata["V6"] = {"signal": "chirp 1–12 kHz", "peaks": "broadband spread", "amp": AMPLITUDE}

# V7 — two-tone 3 kHz + 8 kHz
v = AMPLITUDE * (0.5 * np.sin(2.0 * math.pi * 3000 * t) +
                  0.5 * np.sin(2.0 * math.pi * 8000 * t))
vectors["V7"] = to_q15(v)
metadata["V7"] = {"signal": "two-tone 3+8 kHz", "peaks": "two peaks (col 64, 170)", "amp": AMPLITUDE * 0.5}

# Write concatenated hex
hex_lines = []
for vi in range(8):
    key = f"V{vi}"
    for val in vectors[key]:
        hex_lines.append(f"{val & 0xFFFF:04X}")
    metadata[key]["hex_offset"] = vi * N_SAMPLES
    metadata[key]["samples"]    = N_SAMPLES

hex_path = os.path.join(OUT_DIR, "debug_vectors.hex")
with open(hex_path, "w") as f:
    f.write("\n".join(hex_lines) + "\n")
print(f"Wrote {len(hex_lines)} lines to {hex_path}")

mi_path = os.path.join(OUT_DIR, "debug_vectors.mi")
with open(mi_path, "w") as f:
    f.write(f"#File_format=Hex\n#Address_depth={len(hex_lines)}\n#Data_width=16\n")
    f.write("\n".join(hex_lines) + "\n")
print(f"Wrote {len(hex_lines)} lines to {mi_path}")

meta_path = os.path.join(OUT_DIR, "debug_metadata.json")
with open(meta_path, "w") as f:
    json.dump(metadata, f, indent=2)
print(f"Wrote metadata to {meta_path}")

print("Done.")
