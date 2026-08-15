#!/usr/bin/env python3
"""What the Collector's Shop loads eagerly that it will probably never use.

The shop's cold load is 32.3s and its resource count climbs the whole way, so
it is per-file cost rather than one stuck asset. 512 files hang off the scene,
and the interesting question is how many of them the player actually needs the
moment the room appears.

Two groups stand out and this measures them:

  voicelines - VoicelineGroup.tres holds a direct ExtResource per line, so
               every reactive line for every situation loads with the room.
               Most of them are for outcomes that did not happen this visit.

  the console's own screens - the credits portrait sheet is 4096x4096, and the
               credits are a screen inside a screen inside the room.

Usage:
    python3 tools/audit_shop_eager.py
"""

import re
import struct
from collections import defaultdict
from pathlib import Path

SCENE = "res://lullaby_mod/rooms/env_collector_shop.tscn"
DEP = re.compile(r'path="(res://[^"]+)"')
TEXT_KINDS = {".tscn", ".tres", ".import", ".gdshader"}


def disk(res):
    return Path(res.removeprefix("res://"))


def png_px(p):
    try:
        with open(p, "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return 0
        w, h = struct.unpack(">II", head[16:24])
        return w * h
    except Exception:
        return 0


def walk(root):
    """Full graph, remembering which file pulled each dependency in."""
    seen, queue, parent = {root}, [root], {}
    order = []
    while queue:
        res = queue.pop(0)
        p = disk(res)
        if not p.exists():
            continue
        order.append(res)
        if p.suffix.lower() not in TEXT_KINDS:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for m in DEP.finditer(text):
            dep = m.group(1)
            if dep not in seen:
                seen.add(dep)
                parent[dep] = res
                queue.append(dep)
    return order, parent


order, parent = walk(SCENE)
sizes = {r: disk(r).stat().st_size for r in order if disk(r).exists()}
total = sum(sizes.values())

print("grafo completo: %d archivos, %.1f MB" % (len(order), total / 1048576))
print()

# --- voicelines -----------------------------------------------------------
groups = [r for r in order if r.endswith("_group.tres")]
vox = defaultdict(list)
for res in order:
    if not res.endswith(".ogg"):
        continue
    owner = parent.get(res, "")
    if owner.endswith("_group.tres"):
        vox[owner].append(res)

vox_files = sum(len(v) for v in vox.values())
vox_bytes = sum(sizes.get(o, 0) for v in vox.values() for o in v)

print("VOICELINES")
print("  %d grupos, %d .ogg, %.1f MB" % (len(groups), vox_files, vox_bytes / 1048576))
for g in sorted(vox, key=lambda k: -len(vox[k]))[:10]:
    b = sum(sizes.get(o, 0) for o in vox[g])
    print("    %-52s %3d lineas  %6.2f MB" % (Path(g).name, len(vox[g]), b / 1048576))
other = len(groups) - len(vox)
if other > 0:
    print("    (+%d grupos sin .ogg propios)" % other)
print()

# --- the biggest textures, and who pulled them in -------------------------
print("TEXTURAS MAS GRANDES Y QUIEN LAS ARRASTRA")
pngs = [(png_px(disk(r)), sizes.get(r, 0), r) for r in order if r.endswith(".png")]
pngs.sort(reverse=True)
for px, b, r in pngs[:10]:
    who = Path(parent.get(r, "?")).name
    print("    %6.1f MPx  %6.2f MB  %-44s <- %s"
          % (px / 1e6, b / 1048576, Path(r).name, who))
print()

total_px = sum(px for px, _, _ in pngs)
print("  total %.1f MPx  ->  ~%.1f MB en ASTC 8x8" % (total_px / 1e6, total_px * 0.25 / 1048576))
print()

# --- what fraction is audio at all ---------------------------------------
audio = [r for r in order if r.endswith((".ogg", ".wav"))]
audio_bytes = sum(sizes.get(r, 0) for r in audio)
print("RESUMEN")
print("  audio      : %3d archivos  %6.2f MB  (%.0f%% de los archivos)"
      % (len(audio), audio_bytes / 1048576, 100.0 * len(audio) / len(order)))
print("  de eso vox : %3d archivos  %6.2f MB" % (vox_files, vox_bytes / 1048576))
print("  texturas   : %3d archivos  %6.1f MPx" % (len(pngs), total_px / 1e6))
