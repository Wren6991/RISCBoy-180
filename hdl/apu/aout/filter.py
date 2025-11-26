#!/usr/bin/env python3
import numpy as np
from scipy import signal
import matplotlib.pyplot as plt

num_taps = 63
upsample = 16
sample_rate = 48e3 * upsample
cut_off = 22e3

h = signal.firwin(num_taps, cut_off, fs=sample_rate)

# Quantise the response. Magic number makes the worst-case sum of absolutes
# exactly 128 (with 7 zeroes stuffed between each sample)
qbits = 8
quantise = 2 ** qbits * upsample
magic = 0.87
b = np.array(list(round(x * quantise * magic) for x in h))

def skipskum(b, i):
	return sum(abs(b[j]) for j in range(i, num_taps, upsample))

for i in range(0, upsample + 1):
	print(skipskum(b, i))
	assert skipskum(b, i) <= 2 ** qbits

for i, x in enumerate(b):
	print(f"\t9'h{x & 0x1ff:03x},")

# plt.plot(h, '.-')
# plt.plot(b / (quantise * magic), '.-')
# plt.show()

H = np.abs(np.fft.fft(b / (quantise * magic), 1024))
H = np.fft.fftshift(H)
logH = 20 * np.log10(H)
w = np.linspace(-sample_rate/2, sample_rate/2, len(H))
plt.plot(w, logH, '.-')
plt.grid()
plt.show()
