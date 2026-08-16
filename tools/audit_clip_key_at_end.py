#!/usr/bin/env python3
"""Finds animation-track clip keys placed at the very end of their animation.

An `animation` track dispatches a clip to another AnimationPlayer. Godot
assigns the clip on the frame the key is crossed and then keeps *seeking*
that sub-player from the parent, frame by frame. So a key sitting exactly at
the parent's `length` is assigned and never advanced: the parent stops on the
same frame, nothing seeks the sub-player again, and none of the clip's keys
ever apply.

That is not a hypothesis. Measured against the 4.7.1 binary with Chimera's
real numbers - a sequence of length 14.791667 dispatching `intro` at 0 and
`intro-end` at 14.791667, driven by the scene tree at speed_scale 1.0 - the
target node keeps the value the first clip left it with. Adding a key inside
the running clip fixes it; the dispatch itself cannot be relied on.

This cost a long time to find because the symptom is at the other end of the
song from the cause. Chimera's `102_intro` dispatches `intro-end`, whose only
job is to switch four intro nodes off, at exactly its own length. One of the
four - `OutsideDoor`, a full-screen sprite - is the only one the running
`intro` clip does not switch off by itself, so it stayed visible for the rest
of the song, under UILayer, covering the stage and not the notes.

    python3 tools/audit_clip_key_at_end.py

Exits non-zero if any clip key lands within one 24fps frame of the end. A hit
is not automatically a bug - `[stop]` at the end is harmless, and so is a clip
whose effects the parent animation reproduces itself - so read the report
rather than treating the exit code as a verdict.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## One frame at the 24fps these animations are authored at. A key closer to
## the end than this cannot survive a single frame of the parent's playback.
FRAME = 1.0 / 24.0

ANIM_BLOCK = re.compile(
    r'^\[sub_resource type="Animation" id="([^"]+)"\](.*?)(?=^\[sub_resource|^\[node|\Z)',
    re.S | re.M,
)


def _keys_block(body, index):
    m = re.search(r"tracks/%s/keys = \{(.*?)\n\}" % index, body, re.S)
    return m.group(1) if m else ""


def scan(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        src = handle.read()

    findings = []
    for block in ANIM_BLOCK.finditer(src):
        body = block.group(2)
        length_match = re.search(r"^length = ([\d.]+)", body, re.M)
        if not length_match:
            continue
        length = float(length_match.group(1))
        name_match = re.search(r'^resource_name = "([^"]*)"', body, re.M)
        name = name_match.group(1) if name_match else block.group(1)

        for track in re.finditer(r'tracks/(\d+)/type = "animation"', body):
            index = track.group(1)
            keys = _keys_block(body, index)
            times = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys)
            clips = re.search(r'"clips": PackedStringArray\(([^)]*)\)', keys)
            if not times:
                continue
            stamps = [float(x) for x in times.group(1).split(",") if x.strip()]
            names = (
                [c.strip().strip('"') for c in clips.group(1).split(",")]
                if clips
                else []
            )
            target = re.search(
                r'tracks/%s/path = NodePath\("([^"]*)"\)' % index, body
            )
            for i, stamp in enumerate(stamps):
                if length - stamp >= FRAME:
                    continue
                # A key at t=0 in a 0.001s animation is the "fire this clip
                # now" idiom, not a key that fell off the end - the parent is
                # only ever meant to exist for that one dispatch. Six of the
                # first run's ten findings were that shape.
                if stamp <= 0.0:
                    continue
                findings.append(
                    {
                        "animation": name,
                        "track": index,
                        "target": target.group(1) if target else "?",
                        "clip": names[i] if i < len(names) else "?",
                        "time": stamp,
                        "length": length,
                    }
                )
    return findings


def main():
    total = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "lullaby_mod", "**", "*.tscn"), recursive=True)):
        findings = scan(path)
        if not findings:
            continue
        print(os.path.relpath(path, ROOT))
        for f in findings:
            total += 1
            margin = f["length"] - f["time"]
            print(
                "  %-16s track %-3s -> %s"
                % (f["animation"], f["track"], f["target"])
            )
            print(
                "      clip %-14s en t=%.6f  length=%.6f  margen=%.6fs (%.2f frames)"
                % (f["clip"], f["time"], f["length"], margin, margin / FRAME)
            )
        print()

    print("claves de clip sin un frame de margen: %d" % total)
    if total:
        print(
            "\nUna clave sin margen se asigna y no se aplica nunca. Si el clip\n"
            "apaga algo, eso se queda encendido. Comprobar si la animacion que\n"
            "corre ya deja cada nodo en el valor correcto por si misma; si no,\n"
            "anadir la clave dentro de ella en vez de confiar en el despacho."
        )
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
