#!/usr/bin/env python3
"""Finds keys authored past the point where their sequence is cut short.

A song's timeline is one long animation whose `animation` track dispatches
sequences to a SequencePlayer at fixed times. The sequence that gets
dispatched has its own `length`, and nothing makes the two agree: if the next
dispatch lands before the current sequence reaches its own end, everything
authored after that point never runs. Not "runs late" - never runs, and
without a warning.

Chimera's black graphic was this. `scene` dispatches 102_intro at 19.9167 and
103_stroll at 34.583332, which is 0.125s before 102_intro's own length of
14.791667 would have ended. So 102_intro only ever plays 0 to 14.6666, and
the `intro-end` clip authored at 14.791667 - whose only job is switching four
intro nodes off - is dead. Three of the four the running clip switches off by
itself; OutsideDoor, a full-screen sprite, is the one it does not, so it
stayed visible for the rest of the song.

It also ate a fix. A key added at 14.75 to make the switch-off independent of
the clip dispatch was itself past the cut, so the second attempt failed for
the same reason as the first, and the log looked identical both times.

    python3 tools/audit_sequence_truncation.py

Reports, per dispatched sequence, how much of it is unreachable and which
keys fall in that window. A truncated sequence is not automatically a bug -
a cut is a legitimate way to end a shot - so what matters is whether anything
is authored in the dead window. Keys there are what to read.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ANIM_BLOCK = re.compile(
    r'^\[sub_resource type="Animation" id="([^"]+)"\](.*?)(?=^\[sub_resource|^\[node|\Z)',
    re.S | re.M,
)


def _animations(src):
    """Every Animation sub-resource in the file, by id, with its body."""
    return {m.group(1): m.group(2) for m in ANIM_BLOCK.finditer(src)}


def _names(src):
    """Maps a sub-resource id to the clip name its library registers it as."""
    names = {}
    for lib in re.finditer(
        r'^\[sub_resource type="AnimationLibrary" id="[^"]+"\](.*?)(?=^\[)', src, re.S | re.M
    ):
        for name, sid in re.findall(r'&?"([^"]*)":\s*SubResource\("([^"]+)"\)', lib.group(1)):
            names[sid] = name
    return names


def _length(body):
    m = re.search(r"^length = ([\d.]+)", body, re.M)
    return float(m.group(1)) if m else None


def _keys(body, index):
    m = re.search(r"tracks/%s/keys = \{(.*?)\n\}" % index, body, re.S)
    return m.group(1) if m else ""


def _times(keys):
    m = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys)
    return [float(x) for x in m.group(1).split(",") if x.strip()] if m else []


def scan(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        src = handle.read()

    anims = _animations(src)
    names = _names(src)
    by_name = {names.get(sid, sid): sid for sid in anims}

    findings = []
    for sid, body in anims.items():
        for track in re.finditer(r'tracks/(\d+)/type = "animation"', body):
            index = track.group(1)
            keys = _keys(body, index)
            clips = re.search(r'"clips": PackedStringArray\(([^)]*)\)', keys)
            if not clips:
                continue
            clip_names = [c.strip().strip('"') for c in clips.group(1).split(",")]
            stamps = _times(keys)

            for i, clip in enumerate(clip_names):
                if i >= len(stamps):
                    break
                target_id = by_name.get(clip)
                if target_id is None:
                    continue
                target_length = _length(anims[target_id])
                if target_length is None:
                    continue

                # The dispatch that replaces this one, if any.
                nxt = stamps[i + 1] if i + 1 < len(stamps) else None
                if nxt is None:
                    continue
                played = nxt - stamps[i]
                if played >= target_length:
                    continue

                dead = []
                target = anims[target_id]
                for t in re.finditer(r"tracks/(\d+)/type = \"(\w+)\"", target):
                    ti, kind = t.group(1), t.group(2)
                    tpath = re.search(
                        r'tracks/%s/path = NodePath\("([^"]*)"\)' % ti, target
                    )
                    for stamp in _times(_keys(target, ti)):
                        if stamp > played:
                            dead.append(
                                (stamp, tpath.group(1) if tpath else "?", kind)
                            )
                if dead:
                    findings.append(
                        {
                            "driver": names.get(sid, sid),
                            "clip": clip,
                            "played": played,
                            "length": target_length,
                            "dead": sorted(dead),
                        }
                    )
    return findings


def main():
    total = 0
    for path in sorted(
        glob.glob(os.path.join(ROOT, "lullaby_mod", "**", "*.tscn"), recursive=True)
    ):
        findings = scan(path)
        if not findings:
            continue
        print(os.path.relpath(path, ROOT))
        for f in findings:
            total += 1
            print(
                "  %s despacha %s: corre %.4fs de %.4fs (%.4fs muertos)"
                % (f["driver"], f["clip"], f["played"], f["length"],
                   f["length"] - f["played"])
            )
            for stamp, tpath, kind in f["dead"][:12]:
                print("      t=%.4f  %-10s %s" % (stamp, kind, tpath))
            if len(f["dead"]) > 12:
                print("      ... y %d claves mas" % (len(f["dead"]) - 12))
        print()

    print("secuencias truncadas con claves en la zona muerta: %d" % total)
    if total:
        print(
            "\nUn corte no es por si solo un fallo - cortar un plano es legitimo.\n"
            "Lo que importa es si algo autorado en la zona muerta hacia falta,\n"
            "y sobre todo si apagaba algo."
        )
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
