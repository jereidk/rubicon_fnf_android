#!/usr/bin/env python3
"""Animation tracks that switch a node on and never switch it off.

Chimera's reported black graphic came from a full-screen black ColorRect being
visible when the scene authored it hidden. One cause was found and fixed - a
suppressor script that also forced visible = true - but reading the device log
turned up a second node with the same symptom and a different cause:

    tracks/19/path = NodePath("../Prelude/Black:visible")
    tracks/19/keys = { "times": [0], "update": 1, "values": [true] }

One key, at time zero, true. Godot holds a track's first value for everything
before it, so a track like this has no state in which the node is off: not at
the start, not after a seek, not on a RESET. Whether that is a bug depends on
whether something else hides it - Prelude/Black is covered by a separate track
on the parent - which is exactly the judgement a person has to make.

So this does not report bugs. It reports the shape, ranked by how much of the
screen the node covers if it is wrong, and says which ones have an off switch
somewhere. A full-screen ColorRect at alpha 1 with no off key anywhere is worth
a look; a 32-pixel sprite is not.

Usage:
    python3 tools/audit_stuck_visible.py [scene.tscn ...]
"""

import glob
import re
import sys

SCENES = sys.argv[1:] or sorted(glob.glob("lullaby_mod/songs/**/*.tscn", recursive=True))

TRACK = re.compile(
    r'tracks/(\d+)/path = NodePath\("([^"]+):visible"\)\n'
    r'(?:tracks/\1/[a-z_]+ = [^\n]*\n)*?'
    r'tracks/\1/keys = \{\n'
    r'"times": PackedFloat32Array\(([^)]*)\)[^}]*?'
    r'"values": \[([^\]]*)\]',
    re.MULTILINE,
)

NODE = re.compile(r'\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?[^\]]*\]\n((?:[^\[]*\n)*)')


def nodes_of(text):
    """{full path: (type, body)} for every node in the scene."""
    out = {}
    for m in NODE.finditer(text):
        name, ntype, parent, body = m.group(1), m.group(2), m.group(3), m.group(4)
        path = name if not parent or parent == "." else "%s/%s" % (parent, name)
        out[path] = (ntype, body)
    return out


def screen_ish(ntype, body):
    """Roughly, does this cover the screen - and is it opaque black."""
    if ntype != "ColorRect":
        return False, ""
    right = re.search(r'offset_right = ([\d.]+)', body)
    bottom = re.search(r'offset_bottom = ([\d.]+)', body)
    colour = re.search(r'color = Color\(([\d., ]+)\)', body)
    big = right and bottom and float(right.group(1)) >= 640 and float(bottom.group(1)) >= 360
    if not big:
        return False, ""
    if colour:
        parts = [float(p) for p in colour.group(1).split(",")]
        if len(parts) == 4 and parts[3] >= 0.99 and max(parts[:3]) <= 0.1:
            return True, "%dx%d negro opaco" % (float(right.group(1)), float(bottom.group(1)))
        return True, "%dx%d" % (float(right.group(1)), float(bottom.group(1)))
    return True, "%dx%d" % (float(right.group(1)), float(bottom.group(1)))


total_flagged = 0
for scene in SCENES:
    try:
        text = open(scene, encoding="utf-8", errors="replace").read()
    except OSError:
        continue

    nodes = nodes_of(text)

    # Every visible-track in the file, by target, with the values it can hold.
    holds_on = {}
    can_turn_off = set()
    for m in TRACK.finditer(text):
        target = m.group(2).lstrip("./")
        values = m.group(4)
        has_false = "false" in values
        has_true = "true" in values
        if has_false:
            can_turn_off.add(target)
        if has_true and not has_false:
            holds_on.setdefault(target, 0)
            holds_on[target] += 1

    rows = []
    for target, count in holds_on.items():
        # The authored state is what the track overrides. A node authored
        # visible has nothing to be switched on.
        node = nodes.get(target)
        if node is None:
            # Tracks address nodes relative to the AnimationPlayer, so a miss
            # here is usually a path this crude resolver cannot follow.
            continue
        ntype, body = node
        if "visible = false" not in body:
            continue
        big, note = screen_ish(ntype, body)
        rows.append((big, target, ntype, note, count, target in can_turn_off))

    rows.sort(key=lambda r: (not r[0], r[1]))
    if not rows:
        continue

    print("%s" % scene)
    for big, target, ntype, note, count, has_off in rows:
        flag = "PANTALLA" if big else "        "
        off = "otra pista lo apaga" if has_off else "NADIE lo apaga"
        print("  %s %-44s %-12s %-22s x%d  %s"
              % (flag, target[:44], ntype, note or "-", count, off))
        if big and not has_off:
            total_flagged += 1
    print()

print("rects a pantalla completa encendidos y sin apagado: %d" % total_flagged)
print()
print("Nota: encendido-sin-apagar no es por si solo un fallo. Prelude/Black en")
print("Chimera es el fondo del cutscene y se oculta con su padre. Lo que esto")
print("da es la forma; decidir cual sobra es cosa de mirarlo.")
