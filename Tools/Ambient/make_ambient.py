#!/usr/bin/env python3
"""Builds the ambient sounds in Genesis/Resources/Ambient.

Recorded sounds (rain, fireplace, birdsong, worship pad) are trimmed to a
seamless loop (the tail crossfades into the head), levelled and encoded as
AAC. Wind and ocean waves are synthesised here, so they have no licence
conditions at all.

    python3 Tools/Ambient/make_ambient.py <folder with the source mp3s>

Sources are matched by a word in the file name (see SOURCES). Needs ffmpeg,
numpy and scipy. Record where each recording came from in
Genesis/Resources/Ambient/AmbientCredits.txt.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44_100
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Genesis" / "Resources" / "Ambient"

# id: (word in the source file name, start second, loop seconds, crossfade seconds, target LUFS)
SOURCES = {
    "rain": ("rain", 6, 90, 4, -24),
    "fireplace": ("fireplace", 20, 120, 4, -25),
    "birdsong": ("birdsong", 4, 180, 5, -27),
    "pad": ("pad", 30, 120, 10, -29),
}


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "2", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def seamless(audio: np.ndarray, length: int, fade: int) -> np.ndarray:
    """A loop of `length` samples whose end flows into its start: the head is
    an equal-power crossfade of the head and the audio just after the loop."""
    assert len(audio) >= length + fade, "source too short for this loop"
    loop = audio[:length].copy()
    t = np.linspace(0, np.pi / 2, fade)[:, None]
    loop[:fade] = audio[:fade] * np.sin(t) + audio[length:length + fade] * np.cos(t)
    return loop


def encode(audio: np.ndarray, name: str, lufs: float) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "loop.f32"
        wav.write_bytes(audio.astype(np.float32).tobytes())
        level = f"loudnorm=I={lufs}:TP=-3:LRA=20"
        # Measure, then apply a single gain so the loop stays seamless.
        stats = subprocess.run(
            ["ffmpeg", "-hide_banner", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", str(wav),
             "-af", level + ":print_format=json", "-f", "null", "-"],
            check=True, capture_output=True, text=True,
        ).stderr
        measured = json.loads(stats[stats.rindex("{"):stats.rindex("}") + 1])
        gain_db = lufs - float(measured["input_i"])
        # A memoryless soft knee tames crackles and peaks after the gain
        # without breaking the seam (a limiter with release would).
        y = audio * 10 ** (gain_db / 20)
        knee, room = 0.5, 0.3
        over = np.abs(y) > knee
        y[over] = np.sign(y[over]) * (knee + room * np.tanh((np.abs(y[over]) - knee) / room))
        wav.write_bytes(y.astype(np.float32).tobytes())
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", str(wav),
             "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart",
             str(OUT / f"ambient-{name}.m4a")],
            check=True,
        )
    print(f"{name}: {len(audio) / RATE:.0f} s, gain {gain_db:+.1f} dB")


def periodic_noise(rng: np.random.Generator, length: int, fade: int, shape) -> np.ndarray:
    """Stereo noise shaped by `shape` (a filter), made seamless."""
    noise = rng.standard_normal((length + fade, 2))
    mid = rng.standard_normal(length + fade)
    noise = 0.55 * noise + 0.45 * mid[:, None]  # partly correlated: wide but not hollow
    shaped = np.stack([shape(noise[:, c]) for c in range(2)], axis=1)
    return seamless(shaped, length, fade)


def lowpass(cutoff: float, order: int = 2):
    sos = signal.butter(order, cutoff, "low", fs=RATE, output="sos")
    return lambda x: signal.sosfilt(sos, x)


def bandpass(low: float, high: float):
    sos = signal.butter(2, [low, high], "band", fs=RATE, output="sos")
    return lambda x: signal.sosfilt(sos, x)


def wrapped_bumps(length: int, times: list[float], widths: list[float], heights: list[float], rise: float = 0.35) -> np.ndarray:
    """A periodic envelope: one swell per time, rising quickly then falling."""
    t = np.arange(length) / RATE
    period = length / RATE
    env = np.zeros(length)
    for start, width, height in zip(times, widths, heights):
        d = (t - start) % period
        up = width * rise
        shape = np.where(d < up, np.sin(np.pi / 2 * d / up) ** 2,
                         np.where(d < width, np.cos(np.pi / 2 * (d - up) / (width - up)) ** 2, 0))
        env += height * shape
    return env


def waves(seconds: int = 96) -> np.ndarray:
    rng = np.random.default_rng(7)
    length, fade = seconds * RATE, 3 * RATE
    deep = periodic_noise(rng, length, fade, lowpass(380, 3))
    wash = periodic_noise(rng, length, fade, bandpass(500, 4200))
    times, t = [], 0.0
    while t < seconds - 6:
        times.append(t)
        t += rng.uniform(7.5, 11.5)
    widths = [rng.uniform(6.5, 9.5) for _ in times]
    heights = [rng.uniform(0.65, 1.0) for _ in times]
    swell = wrapped_bumps(length, times, widths, heights, rise=0.4)
    # The hiss of the wave breaking and drawing back comes a moment later.
    hiss = np.roll(swell, int(1.6 * RATE)) ** 1.6
    out = deep * (0.35 + 0.65 * swell)[:, None] * 2.2 + wash * (0.04 + 0.5 * hiss)[:, None]
    return out


def wind(seconds: int = 100) -> np.ndarray:
    rng = np.random.default_rng(3)
    length, fade = seconds * RATE, 3 * RATE
    body = periodic_noise(rng, length, fade, lowpass(520, 2))
    whistle_low = periodic_noise(rng, length, fade, bandpass(380, 560))
    whistle_high = periodic_noise(rng, length, fade, bandpass(700, 1000))
    t = np.arange(length) / RATE
    # Slow gusts made of a few sines whose periods divide the loop.
    def lfo(cycles: list[int], phases: list[float]) -> np.ndarray:
        wave = sum(np.sin(2 * np.pi * c * t / seconds + p) for c, p in zip(cycles, phases)) / len(cycles)
        return 0.5 + 0.5 * wave
    gust = lfo([3, 5, 8], [0.0, 1.3, 2.1])
    turn = lfo([4, 7], [0.7, 2.9])
    out = (body * (0.45 + 0.8 * gust)[:, None] * 2.0
           + whistle_low * (0.2 + 1.2 * gust * turn)[:, None]
           + whistle_high * (0.6 * gust ** 2 * (1 - turn))[:, None])
    return out


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (word, start, seconds, fade, lufs) in SOURCES.items():
        matches = sorted(p for p in folder.glob("*.mp3") if word in p.name.lower())
        if not matches:
            sys.exit(f"No source for {name}: expected an mp3 with '{word}' in its name")
        audio = decode(matches[0])[start * RATE:]
        encode(seamless(audio, seconds * RATE, fade * RATE), name, lufs)
    encode(waves(), "waves", -25)
    encode(wind(), "wind", -27)


if __name__ == "__main__":
    main()
