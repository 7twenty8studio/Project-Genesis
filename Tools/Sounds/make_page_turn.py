#!/usr/bin/env python3
"""Generates Genesis/Resources/Sounds/page-turn.caf: a soft paper rustle,
synthesised from filtered noise (no third-party audio). Needs numpy, scipy
and ffmpeg.

    python3 Tools/Sounds/make_page_turn.py
"""
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44_100
OUT = Path(__file__).resolve().parents[2] / "Genesis" / "Resources" / "Sounds" / "page-turn.caf"

rng = np.random.default_rng(12)
length = int(0.42 * RATE)
t = np.arange(length) / RATE
noise = rng.standard_normal(length)

# The sheet lifting (soft, brighter sweep), then settling (a short, darker brush).
sweep_cut = np.interp(t, [0, 0.18, 0.42], [1800, 5200, 2600])
bright = np.zeros(length)
block = 512
for start in range(0, length, block):
    sos = signal.butter(2, [600, sweep_cut[start]], "band", fs=RATE, output="sos")
    bright[start:start + block] = signal.sosfilt(sos, noise[start:start + block])
lift = np.interp(t, [0, 0.03, 0.2, 0.3], [0, 0.6, 0.35, 0]) * (0.7 + 0.3 * np.sin(2 * np.pi * 23 * t))
settle_env = np.interp(t, [0, 0.26, 0.29, 0.42], [0, 0, 1, 0])
dark = signal.sosfilt(signal.butter(2, [250, 1600], "band", fs=RATE, output="sos"), noise)
audio = bright * lift + dark * settle_env * 0.8
audio = audio / np.abs(audio).max() * 0.5  # quiet: it's a page, not a door

pcm = (audio * 32767).astype("<i2").tobytes()
OUT.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(
    ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
     "-c:a", "pcm_s16le", "-f", "caf", str(OUT)],
    input=pcm, check=True,
)
print(f"{OUT.name}: {length / RATE:.2f} s")
