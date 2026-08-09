#!/usr/bin/env python3
"""Checks that Monochrome's autoplay can finish every word in every window.

The typing challenge gives the player a deadline (TypingChallenge:time_end,
an absolute position in the song, not a duration) and starts prompting at
TypingChallenge:prompt_user. The window is the gap between them, and the word
is drawn at random from a list of nineteen - so "can the autoplay finish in
time" is nineteen questions per window, not one, and the answer is not
obvious by eye.

It is not hypothetical either. At the fixed 0.2s rate the mechanic has always
used, "John Monochrome" (14 keystrokes, 2.8s) does not fit the fourth
challenge (2.75s), and that combination comes up about one run in twenty.
That never mattered while autoplay was a debug toggle; it matters in Showcase
Mode, where the autoplay is what the room is watching.

Everything here is read from the project rather than restated: the windows
from the song scene, the words from its word_list track, the rates from
typing_challenge.gd. A check carrying its own copy of the numbers stops
checking anything the first time one of them moves.

    python3 tools/check_typing_pace.py

Exits non-zero if any word cannot be finished in any window.
"""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SONG = ROOT / "lullaby_mod/songs/monochrome/sng_monochrome.tscn"
MECHANIC = ROOT / "lullaby_mod/scripts/lullaby/mechanics/monochrome/typing_challenge.gd"

FRAME = 1.0 / 60.0


def tracks(text, path):
    """Every (times, values_source) pair for an animation track on `path`.

    The scene holds more than one AnimationPlayer touching these properties -
    an idle one keyed only at 0.0 and the real chart one - so this yields all
    of them and the caller keeps the one with content.
    """
    needle = 'NodePath("%s")' % path
    at = text.find(needle)
    while at != -1:
        chunk = text[at:at + 4000]
        times = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', chunk)
        values = re.search(r'"values": \[(.*?)\]\s*\n?\}', chunk, re.S)
        if times and values:
            parsed = [float(x) for x in times.group(1).split(",") if x.strip()]
            yield parsed, values.group(1)
        at = text.find(needle, at + 1)


def longest(text, path):
    best = ([], "")
    for times, values in tracks(text, path):
        if len(times) > len(best[0]):
            best = (times, values)
    return best


def constant(source, name):
    found = re.search(r"^const %s := ([0-9.]+)$" % name, source, re.M)
    if not found:
        sys.exit("no encontre la constante %s en typing_challenge.gd" % name)
    return float(found.group(1))


def simulate(word, window, interval_of):
    """Types `word` a letter at a time, asking for the interval each frame.

    Stepped rather than solved, because that is what _autoplay_process does:
    it accumulates delta and only compares against the interval on the frames
    it happens to land on. Solving it analytically would quietly assume the
    letters land on exact interval boundaries, which they do not.
    """
    left_to_type = sum(1 for c in word if c != " ")
    elapsed, typed, waited = 0.0, 0, 0.0
    while typed < left_to_type:
        remaining = window - elapsed
        if remaining <= 0:
            return None
        waited += FRAME
        elapsed += FRAME
        if waited >= interval_of(remaining, left_to_type - typed):
            typed += 1
            waited = 0.0
    return elapsed


def main():
    scene = SONG.read_text()
    source = MECHANIC.read_text()

    fixed = constant(source, "AUTOPLAY_INTERVAL")
    budget = constant(source, "SHOWCASE_AUTOPLAY_BUDGET")
    slowest = constant(source, "SHOWCASE_AUTOPLAY_MAX_INTERVAL")
    fastest = constant(source, "SHOWCASE_AUTOPLAY_MIN_INTERVAL")

    prompt_times, prompt_values = longest(scene, "../Stage/TypingChallenge:prompt_user")
    prompts = [t for t, v in zip(prompt_times, prompt_values.split(","))
               if v.strip() == "true"]

    end_times, end_values = longest(scene, "../Stage/TypingChallenge:time_end")
    ends = list(zip(end_times, [float(v) for v in end_values.split(",")]))

    words_src = longest(scene, "../Stage/TypingChallenge:word_list")[1]
    words = ast.literal_eval("[" + words_src[:words_src.index("]") + 1] + "]")[0]

    windows = []
    for start in prompts:
        # time_end is a discrete value track, so the deadline in force is the
        # one set by the last keyframe at or before the challenge starts.
        deadline = max((v for t, v in ends if t <= start), default=0.0)
        if deadline > start:
            windows.append((start, deadline - start))

    print("%d retos, %d palabras" % (len(windows), len(words)))
    print("ritmo fijo %.2fs | showcase %.0f%% del tiempo restante, entre %.2fs y %.2fs\n"
          % (fixed, budget * 100, fastest, slowest))

    def fixed_rate(_remaining, _left):
        return fixed

    def showcase_rate(remaining, left):
        return min(max(remaining * budget / left, fastest), slowest)

    header = "%-17s %3s" % ("palabra", "K")
    for i, (start, window) in enumerate(windows, 1):
        header += "%17s" % ("#%d %.2fs" % (i, window))
    print(header)

    failures, rescued, tightest = [], [], 1.0
    for word in words:
        keys = sum(1 for c in word if c != " ")
        row = "%-17s %3d" % (word, keys)
        for index, (start, window) in enumerate(windows, 1):
            before = simulate(word, window, fixed_rate)
            after = simulate(word, window, showcase_rate)
            if after is None:
                failures.append((word, index, window))
                row += "%17s" % "NO ENTRA"
            else:
                tightest = min(tightest, (window - after) / window)
                if before is None:
                    rescued.append((word, index, window))
                    row += "%17s" % ("rescata %.2f" % after)
                else:
                    row += "%17s" % ("%.2f->%.2f" % (before, after))
        print(row)

    print()
    for word, index, window in rescued:
        print("rescatado: %r en el reto #%d (%.2fs) no entraba al ritmo fijo"
              % (word, index, window))
    print("margen sobrante minimo: %.1f%% de la ventana" % (tightest * 100))

    if failures:
        print()
        for word, index, window in failures:
            print("FALLA: %r no cabe en el reto #%d (%.2fs)" % (word, index, window))
        return 1

    print("todas las palabras entran en todos los retos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
