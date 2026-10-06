#!/usr/bin/env python3
"""Builds Genesis/Resources/Sounds/page-turn.caf from a real page-turn recording.

Source: "Turning Page in a Book" by xpmonster (Pixabay, sound 419580),
Pixabay Content License (free for commercial use, no attribution required;
credited in Genesis/Resources/Sounds/SoundCredits.txt). Kept in
Tools/Sounds/sources/.

The recording is trimmed to the turn, its rumble and harsh highs are rolled
off, its attack is softened, and it's levelled well below a notification so
it sits quietly under reading. Plays as a system sound (follows the silent
switch). Needs ffmpeg.

    python3 Tools/Sounds/make_page_turn.py
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Tools" / "Sounds" / "sources" / "turning-page-in-a-book.mp3"
OUT = ROOT / "Genesis" / "Resources" / "Sounds" / "page-turn.caf"

FILTERS = ",".join([
    "atrim=0:0.68",                                            # the turn, without the tail
    "highpass=f=140",                                          # no rumble
    "lowpass=f=6500",                                          # no hiss or harsh edge
    "acompressor=threshold=-24dB:ratio=3:attack=2:release=60",  # a softer attack
    "afade=t=in:d=0.015",
    "afade=t=out:st=0.52:d=0.16",
    "volume=2dB",                                              # peaks near -7 dB, mean near -36 dB
    "aresample=44100",
])

subprocess.run(
    ["ffmpeg", "-v", "error", "-y", "-i", str(SOURCE), "-af", FILTERS, "-ac", "1",
     "-c:a", "pcm_s16le", "-f", "caf", str(OUT)],
    check=True,
)
print(f"Wrote {OUT.relative_to(ROOT)}")
