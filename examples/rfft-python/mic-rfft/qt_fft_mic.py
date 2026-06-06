import numpy as np
import pyqtgraph as pg
import sounddevice as sd
from rfft.rfft_from_scratch import top_level_rfft_q15 # Your function
import math

# Setup Qt application and window
app = pg.mkQApp("Mic FFT")
win = pg.GraphicsLayoutWidget(show=True, title="Real-Time Audio Spectrum")
plot = win.addPlot(title="FFT Magnitude (Scratch Implementation)")
plot.setLogMode(x=False, y=True)
curve = plot.plot(pen='y')

# IMPORTANT: Match the chunk size to your scratch function's N
CHUNK = 4096 
RATE = 44100 

# 1. Force the InputStream to use int16 dtype
# This mimics exactly what an ADC would provide to an FPGA
stream = sd.InputStream(samplerate=RATE, channels=1, blocksize=CHUNK, dtype='int16')
stream.start()

# Calculate X-axis frequency bins for 4096 points
freqs = np.linspace(0, RATE / 2, (CHUNK // 2) + 1)

def update():
    # 2. Read the raw 16-bit integer chunk
    data, _ = stream.read(CHUNK)
    
    # data is (CHUNK, 1). We need a 1D list for your scratch function
    raw_ints = data[:, 0].tolist()
    
    # 3. Call your scratch function
    # This replaces np.fft.rfft
    complex_spectrum = top_level_rfft_q15(raw_ints)
    
    fft_mag = []
    for z in complex_spectrum:
        # 1. Access the components
        a = z[0]
        b = z[1]
        
        # 2. Square them, add them, and take the square root
        magnitude = math.sqrt(a**2 + b**2)
        
        fft_mag.append(magnitude)
    
    # Update plot data
    curve.setData(freqs, [m + 1e-6 for m in fft_mag])

# Timer loop
timer = pg.QtCore.QTimer()
timer.timeout.connect(update)
timer.start(30)

pg.exec()