#!/usr/bin/env python3
"""Builds Genesis/Resources/Sounds/page-turn-1.caf … page-turn-5.caf (softest
to loudest) from a real page-turn recording. The reader's Page-turn volume
slider picks one: system sounds can't change their own volume, and playing
them as system sounds keeps them off the audio session narration and
ambient sounds use.

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
SOUNDS = ROOT / "Genesis" / "Resources" / "Sounds"
# Gain of each level against the middle one (level 3: peaks near -7 dB).
LEVELS = {1: -12, 2: -6.5, 3: 0, 4: 3, 5: 6}

FILTERS = ",".join([
    "atrim=0:0.68",                                            # the turn, without the tail
    "highpass=f=140",                                          # no rumble
    "lowpass=f=6500",                                          # no hiss or harsh edge
    "acompressor=threshold=-24dB:ratio=3:attack=2:release=60",  # a softer attack
    "afade=t=in:d=0.015",
    "afade=t=out:st=0.52:d=0.16",
    "volume=2dB",                                              # level 3: peaks near -7 dB, mean near -36 dB
    "aresample=44100",
])

for level, gain in LEVELS.items():
    out = SOUNDS / f"page-turn-{level}.caf"
    # The loudest levels pass through a limiter so they never clip.
    chain = f"{FILTERS},volume={gain}dB,alimiter=limit=0.89:level=false"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(SOURCE), "-af", chain, "-ac", "1",
         "-c:a", "pcm_s16le", "-f", "caf", str(out)],
        check=True,
    )
    print(f"Wrote {out.relative_to(ROOT)}")
