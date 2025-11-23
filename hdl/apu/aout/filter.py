#!/usr/bin/env python3
import numpy as np
from scipy import signal
import matplotlib.pyplot as plt

num_taps = 33
sample_rate = 48e3 * 8
cut_off = 22e3

h = signal.firwin(num_taps, cut_off, fs=sample_rate)

# Quantise the response. Magic number makes the worst-case sum of absolutes
# exactly 128 (with 7 zeroes stuffed between each sample)
quantise = 2 ** 7 * 8
magic = 0.84
b = np.array(list(round(x * quantise * magic) for x in h))

def skipskum(b, i):
	if i == 0:
		return abs(b[0]) + abs(b[8]) + abs(b[16]) + abs(b[24]) + abs(b[32])
	else:
		return abs(b[i]) + abs(b[i + 8]) + abs(b[i + 16]) + abs(b[i + 24])

for i in range(0, 9):
	print(skipskum(b, i))
	assert skipskum(b, i) <= 128

for i, x in enumerate(b):
	print(f"// {i:<2} : {'+' if x >= 0 else '-'}7'b{abs(x):07b}")

# plt.plot(h, '.-')
# plt.plot(b / (QUANTISE * MAGIC), '.-')
# plt.show()

H = np.abs(np.fft.fft(b / 1024, 1024))
H = np.fft.fftshift(H)
logH = 20 * np.log10(H)
w = np.linspace(-sample_rate/2, sample_rate/2, len(H))
plt.plot(w, logH, '.-')
plt.show()
