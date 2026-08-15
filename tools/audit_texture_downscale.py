#!/usr/bin/env python3
"""Which of a scene's big textures could be downscaled, and which must not be.

Resolution is the largest remaining lever on the Collector's Shop: 19 textures
at 2048 square carry 79.7 of its 104.5 megapixels. Halving them would take that
to 19.9 - about 14MB of VRAM and a large slice of the GPU upload the precache
spends 35 seconds on.

It is not a blanket change, and the project's own ASTC importer says why in a
comment on the one line that would do it:

    PAD, never resize. resize() rescales the whole image to the new size,
    which silently stretches every pixel by a few thousandths - invisible on a
    standalone sprite, fatal on a texture atlas, where each frame's region
    comes from a .json in exact source pixels.

So the question is per texture: is it sampled through UVs, where a smaller
image is just less detail, or is it addressed in pixels, where a smaller image
is wrong? This sorts them by how they are reached.

  safe        reached through a Material3D - UV-mapped onto geometry
  UNSAFE      reached through an AtlasTexture or SpriteFrames - pixel regions
  check       reached straight from a scene; usually a 3D material, but a
              shader-driven flipbook lives here too and needs eyes on it

Usage:
    python3 tools/audit_texture_downscale.py [scene.tscn] [min_size]
"""

import re
import struct
import sys
from pathlib import Path

SCENE = sys.argv[1] if len(sys.argv) > 1 else "lullaby_mod/rooms/env_collector_shop.tscn"
MIN_SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 2048

DEP = re.compile(r'path="(res://[^"]+)"')
TEXT = {".tscn", ".tres", ".import", ".gdshader"}

# ASTC 8x8 is a quarter of a byte per pixel, which is what this project's
# importer produces by default.
BYTES_PER_PIXEL = 0.25


def disk(res):
    return Path(res.removeprefix("res://"))


def dimensions(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return (0, 0)
        return struct.unpack(">II", head[16:24])
    except Exception:
        return (0, 0)


def walk(root):
    seen, queue, parent, order = {root}, [root], {}, []
    while queue:
        res = queue.pop(0)
        p = disk(res)
        if not p.exists():
            continue
        order.append(res)
        if p.suffix.lower() not in TEXT:
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


def classify(owner):
    """How the texture is reached, which is what decides whether it can shrink."""
    p = disk(owner)
    if p.suffix == ".tres" and p.exists():
        head = p.read_text(encoding="utf-8", errors="replace")[:800]
        if "AtlasTexture" in head or "SpriteFrames" in head:
            return "UNSAFE", "regiones en pixeles"
        if "Material3D" in head or "ORMMaterial" in head:
            return "safe", "material 3D"
    if p.suffix == ".tscn":
        return "check", "desde la escena"
    return "check", "sin clasificar"


root = SCENE if SCENE.startswith("res://") else "res://" + SCENE
order, parent = walk(root)

buckets = {"safe": [], "check": [], "UNSAFE": []}
total_px = 0
for res in order:
    if not res.endswith(".png"):
        continue
    w, h = dimensions(disk(res))
    total_px += w * h
    if max(w, h) < MIN_SIZE:
        continue
    verdict, why = classify(parent.get(res, ""))
    buckets[verdict].append((w * h, Path(res).name, why, Path(parent.get(res, "?")).name))

print("%s" % root)
print("  %.1f MPx en total; mirando las de %d px o mas" % (total_px / 1e6, MIN_SIZE))
print()

savings = 0
for verdict in ("safe", "check", "UNSAFE"):
    rows = sorted(buckets[verdict], reverse=True)
    if not rows:
        continue
    print("%s (%d)" % (verdict, len(rows)))
    for px, name, why, owner in rows:
        print("   %5.1f MPx  %-42s %-18s <- %s" % (px / 1e6, name, why, owner))
    subtotal = sum(px for px, _, _, _ in rows)
    print("   subtotal %.1f MPx" % (subtotal / 1e6))
    if verdict == "safe":
        savings = subtotal * 0.75
    print()

if savings:
    print("reducir a la mitad solo las seguras:")
    print("  %.1f MPx menos  (~%.1f MB de VRAM en ASTC 8x8)"
          % (savings / 1e6, savings * BYTES_PER_PIXEL / 1048576))
    print("  el grafo pasaria de %.1f a %.1f MPx"
          % (total_px / 1e6, (total_px - savings) / 1e6))
print()
print("Nota: el importador de este proyecto (lullaby.astc_sprite) no expone")
print("hoy un limite de tamano. Anadirlo toca _get_import_options(), y 494")
print("texturas usan ese importador - si eso invalida sus .import, la build")
print("vuelve a reimportar todo. Conviene comprobarlo con una build delante.")
