#!/usr/bin/env python3
"""Every animation track in Chimera that touches the full-screen black rect.

The device census caught BlackBoxofAwesomeness - a full-rect ColorRect at the
scene root - measured at coverage 1.00 while the song was running. The scene
authors it visible=false with color.a=0, so something animated it opaque and
left it there. That matches the report: a black graphic in front of everything
from the moment the sprite plane starts.

Text-parsed rather than loaded through Godot: the scene pulls in textures and
.gltf materials that a headless run without an import step cannot resolve, so
load() fails outright on it.

This prints values and does not draw a conclusion. The last two theories about
this bug were both wrong - the results screen turned out to be a bare Control
that paints nothing, and its Vingette a gradient that never reaches opaque -
and both looked convincing right up until the numbers were read.

Usage:
    python3 tools/audit_black_box.py [node_name] [scene.tscn ...]
"""

import re
import sys
from pathlib import Path

TARGET = sys.argv[1] if len(sys.argv) > 1 else "BlackBoxofAwesomeness"
SCENES = sys.argv[2:] or ["lullaby_mod/songs/chimera/sng_chimera.tscn"]

# "update" in a keys dict: 0 CONTINUOUS, 1 DISCRETE, 2 CAPTURE. On a bool or a
# colour track this decides whether the value snaps at the keyframe or is
# interpolated between them, which for a bool means it flips at the midpoint.
UPDATE = {0: "CONTINUOUS", 1: "DISCRETE", 2: "CAPTURE"}

BLOCK = re.compile(r'^\[(sub_resource|resource)([^\]]*)\]', re.M)
COLOR = re.compile(r'Color\(([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+)\)')


def blocks(text):
    """Split a Godot text resource into (header, body) sections."""
    marks = [(m.start(), m.group(0)) for m in BLOCK.finditer(text)]
    for i, (pos, header) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        yield header, text[pos:end]


def field(body, key):
    m = re.search(r'^%s = (.*)$' % re.escape(key), body, re.M)
    return m.group(1).strip() if m else None


def keys_of(body, idx):
    """The keys dict of one track, as raw text."""
    m = re.search(r'^tracks/%d/keys = \{(.*?)^\}' % idx, body, re.M | re.S)
    return m.group(1) if m else ""


def describe(value):
    value = value.strip()
    c = COLOR.match(value)
    if c:
        r, g, b, a = (float(x) for x in c.groups())
        return "Color(%.2f, %.2f, %.2f, a=%.2f)" % (r, g, b, a), a
    return value, None


def split_values(raw):
    """Split the values array on top-level commas."""
    out, depth, cur = [], 0, ""
    for ch in raw:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def scan(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    hits = 0

    for header, body in blocks(text):
        if 'type="Animation"' not in header:
            continue
        name = field(body, "resource_name") or header
        length = field(body, "length") or "?"

        for m in re.finditer(r'^tracks/(\d+)/path = NodePath\("([^"]*)"\)', body, re.M):
            idx, node_path = int(m.group(1)), m.group(2)
            if TARGET not in node_path:
                continue

            hits += 1
            keys = keys_of(body, idx)
            upd = re.search(r'"update":\s*(\d+)', keys)
            upd = int(upd.group(1)) if upd else -1
            times = re.search(r'"times":\s*PackedFloat32Array\(([^)]*)\)', keys)
            times = [t.strip() for t in times.group(1).split(",")] if times else []
            vals = re.search(r'"values":\s*\[(.*?)\]\s*$', keys, re.S | re.M)
            vals = split_values(vals.group(1)) if vals else []

            print("%s  %s  len=%ss" % (Path(path).name, name.strip('"'), length))
            print("   %s   update=%s  keys=%d"
                  % (node_path, UPDATE.get(upd, "?"), len(times)))

            last_alpha, last_raw = None, None
            for i, t in enumerate(times):
                raw = vals[i] if i < len(vals) else "?"
                shown, alpha = describe(raw)
                print("      %8ss  %s" % (t, shown))
                last_alpha, last_raw = alpha, shown

            notes = []
            if node_path.endswith(":visible") and last_raw and "true" in last_raw:
                notes.append("TERMINA VISIBLE")
            if last_alpha is not None and last_alpha >= 0.95:
                notes.append("TERMINA OPACO (a=%.2f)" % last_alpha)
            # A bool on a CONTINUOUS track does not snap at its keyframe: Godot
            # interpolates it and it flips at the midpoint between keys.
            if upd == 0 and last_raw and ("true" in last_raw or "false" in last_raw):
                notes.append("bool CONTINUOUS: cambia en el punto medio, no en la clave")
            if notes:
                print("   -> %s" % "; ".join(notes))
            print()

    return hits


total = 0
for scene in SCENES:
    if not Path(scene).exists():
        print("no existe: %s" % scene)
        continue
    total += scan(scene)

print("%d pista(s) tocan %s" % (total, TARGET))
