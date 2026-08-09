#!/usr/bin/env python3
"""Checks a repacked atlas samples identically to the original.

The whole risk in repacking is that a region ends up pointing a pixel or a
fraction of a pixel off, which does not crash, does not look obviously wrong
in a thumbnail, and shows up in the game as a seam or a neighbour's elbow
along a frame edge. Eyeballing the sheet cannot catch that - the sheet looks
fine either way, it is the REGIONS that move.

So this samples every frame out of both atlases the way the engine does, at
the exact float rectangle each resource declares, and compares the results
pixel for pixel. Anything but zero differing pixels is a failure.

Usage:
    python3 tools/verify_repack.py <original.tres> <repacked.tres>
"""
import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("hace falta Pillow: pip install pillow")

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

EXT_RE = re.compile(
    r'\[ext_resource type="Texture2D"(?: uid="[^"]+")? path="([^"]+)" id="([^"]+)"\]')
SUB_RE = re.compile(
    r'\[sub_resource type="AtlasTexture" id="([^"]+)"\](.*?)(?=\n\[|\Z)', re.S)
ATLAS_RE = re.compile(r'atlas = ExtResource\("([^"]+)"\)')
REGION_RE = re.compile(
    r'region = Rect2\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)')
MARGIN_RE = re.compile(
    r'margin = Rect2\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)')


def load(path, base_dir):
    text = open(path, encoding="utf-8").read()
    ext = {}
    for m in EXT_RE.finditer(text):
        res = m.group(1)
        disk = os.path.join(PROJECT, res[len("res://"):])
        if not os.path.exists(disk):
            disk = os.path.join(base_dir, os.path.basename(res))
        ext[m.group(2)] = Image.open(disk).convert("RGBA")
    frames = {}
    for m in SUB_RE.finditer(text):
        body = m.group(2)
        a, r = ATLAS_RE.search(body), REGION_RE.search(body)
        if not a or not r:
            continue
        mg = MARGIN_RE.search(body)
        frames[m.group(1)] = (
            ext[a.group(1)],
            tuple(float(v) for v in r.groups()),
            tuple(float(v) for v in mg.groups()) if mg else None,
        )
    return frames


def sample(img, region):
    """The pixels the engine would read for this region.

    Taken as the integer bounding box plus the fractional offset, which is
    what makes a half-pixel slip visible here instead of in the game.
    """
    x, y, w, h = region
    x0, y0 = int(x), int(y)
    x1 = int(x + w) + (1 if (x + w) % 1 else 0)
    y1 = int(y + h) + (1 if (y + h) % 1 else 0)
    return img.crop((x0, y0, x1, y1)), (round(x - x0, 6), round(y - y0, 6))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    old_path, new_path = sys.argv[1], sys.argv[2]
    old = load(old_path, os.path.dirname(os.path.abspath(old_path)))
    new = load(new_path, os.path.dirname(os.path.abspath(new_path)))

    if set(old) != set(new):
        print("FALLO: los fotogramas no coinciden")
        print("  solo en el original:", sorted(set(old) - set(new))[:5])
        print("  solo en el nuevo   :", sorted(set(new) - set(old))[:5])
        return 1

    failures = 0
    for sub_id in sorted(old):
        o_img, o_reg, o_mg = old[sub_id]
        n_img, n_reg, n_mg = new[sub_id]

        if (o_reg[2], o_reg[3]) != (n_reg[2], n_reg[3]):
            print("FALLO %s: el tamano de la region cambio %s -> %s"
                  % (sub_id, o_reg[2:], n_reg[2:]))
            failures += 1
            continue
        if o_mg != n_mg:
            print("FALLO %s: el margin cambio %s -> %s" % (sub_id, o_mg, n_mg))
            failures += 1
            continue

        o_crop, o_frac = sample(o_img, o_reg)
        n_crop, n_frac = sample(n_img, n_reg)
        if o_frac != n_frac:
            print("FALLO %s: la parte fraccionaria cambio %s -> %s"
                  % (sub_id, o_frac, n_frac))
            failures += 1
            continue
        if o_crop.size != n_crop.size:
            print("FALLO %s: el recorte cambio de tamano %s -> %s"
                  % (sub_id, o_crop.size, n_crop.size))
            failures += 1
            continue

        if o_crop.tobytes() != n_crop.tobytes():
            raw_o, raw_n = o_crop.tobytes(), n_crop.tobytes()
            diff = sum(1 for i in range(0, len(raw_o), 4)
                       if raw_o[i:i + 4] != raw_n[i:i + 4])
            print("FALLO %s: %d pixeles distintos de %d"
                  % (sub_id, diff, o_crop.width * o_crop.height))
            failures += 1

    total = len(old)
    if failures:
        print("\n%d de %d fotogramas fallan" % (failures, total))
        return 1
    print("%d fotogramas, todos identicos pixel a pixel" % total)
    print("region, margin y offset fraccionario conservados en todos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
