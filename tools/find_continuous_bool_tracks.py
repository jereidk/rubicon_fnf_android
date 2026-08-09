#!/usr/bin/env python3
"""Find animation value tracks that flip a bool halfway between its keys.

Godot stores a value track's interpolation as `"update": 0` (CONTINUOUS),
1 (DISCRETE), 2 (CAPTURE). CONTINUOUS asks the engine to interpolate between
keys, and for a type it cannot interpolate - a bool - Variant::interpolate
falls back to "a below the midpoint, b above it". So a CONTINUOUS bool track
does not change at its key. It changes exactly halfway to the next one.

That is not theoretical. Monochrome's scene animation keys
Stage/UnownKing/TextureRect:visible at 0 / 266.6 / 330.2 and, measured
against a real AnimationPlayer in 4.7.1, it switched at 133.0 and 298.4 -
both midpoints. The same animation keys TypingChallenge:active eleven times,
also CONTINUOUS, so the typing mechanic itself starts and stops at eleven
wrong times; and KingsEye:visible keys false at 0 and true at 330.29, so the
grey graphic turns on at 165 rather than at the end of the song.

Whatever engine the mod was authored against evidently treated these as
discrete. 4.7.1 does not, and every bool track authored this way is wrong by
half the gap to its next key.

Usage:
    python3 tools/find_continuous_bool_tracks.py            # report
    python3 tools/find_continuous_bool_tracks.py --fix      # set update = 1
"""

import glob
import os
import re
import sys

# A value track's keys live in one dictionary; capture it whole so the update
# mode and the values are read from the same track rather than paired up by
# position.
KEYS = re.compile(
    r'tracks/(?P<idx>\d+)/type = "value".*?'
    r'tracks/(?P=idx)/path = NodePath\("(?P<path>[^"]*)"\).*?'
    r'tracks/(?P=idx)/keys = \{(?P<keys>.*?)\n\}',
    re.S,
)


def bool_values(keys_blob):
    match = re.search(r'"values": \[(.*?)\]', keys_blob, re.S)
    if not match:
        return False
    values = [v.strip() for v in match.group(1).split(",") if v.strip()]
    return bool(values) and all(v in ("true", "false") for v in values)


def update_mode(keys_blob):
    match = re.search(r'"update": (\d+)', keys_blob)
    return int(match.group(1)) if match else None


def times(keys_blob):
    match = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys_blob)
    if not match or not match.group(1).strip():
        return []
    return [float(t) for t in match.group(1).split(",")]


def scan(path):
    """Every CONTINUOUS bool track in one file, with how far off it fires."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []

    found = []
    for match in KEYS.finditer(text):
        blob = match.group("keys")
        if update_mode(blob) != 0 or not bool_values(blob):
            continue

        stamps = times(blob)
        # A single key never interpolates towards anything, so it is correct
        # either way and only noise in the report.
        if len(stamps) < 2:
            continue

        worst = max(
            (stamps[i + 1] - stamps[i]) / 2.0 for i in range(len(stamps) - 1)
        )
        found.append((match.group("path"), len(stamps), worst))
    return found


def fix(path):
    """Set every CONTINUOUS bool value track in the file to DISCRETE."""
    text = open(path, encoding="utf-8", errors="replace").read()
    edits = []

    for match in KEYS.finditer(text):
        blob = match.group("keys")
        if update_mode(blob) != 0 or not bool_values(blob):
            continue
        if len(times(blob)) < 2:
            continue
        # Offsets of the "update" value inside this track's own keys dict, so
        # no other track's can be hit by accident.
        inner = re.search(r'"update": (\d+)', blob)
        start = match.start("keys") + inner.start(1)
        edits.append((start, inner.end(1) - inner.start(1)))

    if not edits:
        return 0

    for start, length in sorted(edits, reverse=True):
        text = text[:start] + "1" + text[start + length:]

    open(path, "w", encoding="utf-8").write(text)
    return len(edits)


def main(argv):
    do_fix = "--fix" in argv[1:]

    files = []
    for pattern in ("**/*.tscn", "**/*.tres", "**/*.res"):
        files += [f for f in glob.glob(pattern, recursive=True)
                  if not f.startswith(".godot") and "precompiled_" not in f]

    total_tracks, total_files, worst_overall = 0, 0, []
    for path in sorted(files):
        found = scan(path)
        if not found:
            continue
        total_files += 1
        total_tracks += len(found)
        for track_path, count, worst in found:
            worst_overall.append((worst, path, track_path, count))

        if do_fix:
            fix(path)

    worst_overall.sort(reverse=True)
    print("archivos afectados : %d" % total_files)
    print("pistas afectadas   : %d" % total_tracks)
    print("")
    print("las 20 peores (cuanto se adelanta el cambio, en segundos):")
    for worst, path, track_path, count in worst_overall[:20]:
        print("  %8.1fs  %-42s  %s" % (worst, track_path[-42:], os.path.basename(path)))

    if do_fix:
        print("")
        print("Corregidas a update = 1 (DISCRETE).")
    else:
        print("")
        print("Nada modificado. Pasa --fix para corregirlas.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
