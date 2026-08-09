#!/usr/bin/env python3
"""Repacks the sheets behind a SpriteFrames into as few pixels as possible.

ASTC is a fixed-rate format: 8x8 costs 16 bytes per 64 pixels whatever is in
them, so a sheet that is 60% transparent pays full price for the empty part -
on disk the APK's zip claws some of it back, in VRAM none of it. The mod's
sheets average 74.6% coverage and the worst are under 40%, which is a lot of
nothing being paid for twice.

Repacking is the only way to recover it that does not touch the art. What
makes it delicate is that every frame is addressed by a pixel rectangle
stored in the resource, so moving a frame means rewriting its region, and
getting that wrong is exactly the bug that broke Gold's back-turned pose.

Three things this is careful about:

  Fractional regions. The regions are floats - Rect2(1276.1, 0.7, ...) - so
  the whole-pixel block is extracted by its integer bounding box and the
  fractional part is re-applied to the new origin. The sub-rectangle the
  engine samples ends up identical rather than merely close.

  Block alignment. Frames are placed on 8-pixel boundaries, so no ASTC block
  ever straddles two frames. The source sheets do not do this, which is why
  they can bleed a neighbour's pixels into a frame's edge under compression.

  Gutters. GUTTER transparent pixels around each frame, so bilinear filtering
  at a frame edge cannot reach into the next one.

`margin` is left alone on purpose: it describes the transparent border that
was trimmed off the original art, which is a property of the frame and not of
where the frame happens to sit.

Usage:
    python3 tools/repack_atlas.py <resource.tres>            # dry run
    python3 tools/repack_atlas.py <resource.tres> --apply    # write it
"""
import argparse
import os
import re
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("hace falta Pillow: pip install pillow")

## Transparent pixels kept around every frame.
GUTTER = 2
## ASTC 8x8 block size; every frame origin lands on a multiple of this.
BLOCK = 8
## Kept at or below what any target GPU accepts without a second thought.
MAX_SIDE = 4096

EXT_RE = re.compile(
    r'\[ext_resource type="Texture2D"(?: uid="(?P<uid>uid://[a-z0-9]+)")?'
    r' path="(?P<path>[^"]+)" id="(?P<id>[^"]+)"\]')
SUB_RE = re.compile(
    r'\[sub_resource type="AtlasTexture" id="(?P<id>[^"]+)"\](?P<body>.*?)(?=\n\[|\Z)',
    re.S)
ATLAS_RE = re.compile(r'atlas = ExtResource\("([^"]+)"\)')
REGION_RE = re.compile(
    r'region = Rect2\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)')


class Frame:
    def __init__(self, sub_id, ext_id, region):
        self.sub_id = sub_id
        self.ext_id = ext_id
        self.region = region                      # float x, y, w, h
        x, y, w, h = region
        self.x0, self.y0 = int(x), int(y)         # integer bounding box
        self.x1 = -(-int(x + w * 1000) // 1000)   # ceil without float error
        self.x1 = int(x + w) + (1 if (x + w) % 1 else 0)
        self.y1 = int(y + h) + (1 if (y + h) % 1 else 0)
        self.frac = (x - self.x0, y - self.y0)
        self.box_w = self.x1 - self.x0
        self.box_h = self.y1 - self.y0
        self.sheet = None
        self.dest = None                          # integer x, y of the block


def parse(path):
    text = open(path, encoding="utf-8").read()
    ext = {m.group("id"): m.group("path") for m in EXT_RE.finditer(text)}
    frames = []
    for m in SUB_RE.finditer(text):
        body = m.group("body")
        a, r = ATLAS_RE.search(body), REGION_RE.search(body)
        if not a or not r:
            continue
        frames.append(Frame(m.group("id"), a.group(1),
                            tuple(float(v) for v in r.groups())))
    return text, ext, frames


def shelf_pack(frames, width):
    """Rows of frames, tallest first. Returns (sheets, total_pixels) or None.

    Simple on purpose. Every frame here is a similar width, so a shelf packer
    lands within a couple of percent of what a MaxRects would manage, and it
    is short enough to be read and trusted.
    """
    order = sorted(frames, key=lambda f: -f.box_h)
    sheets = []
    x = y = row_h = 0
    sheet = 0
    for f in order:
        need_w = _up(f.box_w + 2 * GUTTER)
        need_h = _up(f.box_h + 2 * GUTTER)
        if need_w > width or need_h > MAX_SIDE:
            return None
        if x + need_w > width:                    # next row
            x = 0
            y += row_h
            row_h = 0
        if y + need_h > MAX_SIDE:                 # next sheet
            sheets.append(y)
            sheet += 1
            x = y = row_h = 0
        f.sheet = sheet
        f.dest = (x + GUTTER, y + GUTTER)
        x += need_w
        row_h = max(row_h, need_h)
    sheets.append(y + row_h)
    return sheets, sum(width * h for h in sheets)


def _up(v):
    return -(-v // BLOCK) * BLOCK


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("resource")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--out", default=None,
                    help="donde escribir (por defecto, junto al original)")
    args = ap.parse_args()

    text, ext, frames = parse(args.resource)
    if not frames:
        sys.exit("no encontre AtlasTexture con region en %s" % args.resource)

    root = os.path.dirname(os.path.abspath(args.resource))
    project = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    # A sheet used both as an atlas source and directly - a Sprite2D's
    # texture, say - cannot have its ext_resource swapped out from under the
    # direct user. Common enough in a .tscn to be worth refusing over.
    mixed = _mixed_use(text, ext, {f.ext_id for f in frames})
    if mixed:
        print("%s\n  SALTADA: estas hojas se usan ademas fuera de un "
              "AtlasTexture, asi\n  que no puedo reapuntarlas sin romper ese "
              "otro uso:" % os.path.relpath(args.resource, project))
        for eid in sorted(mixed):
            print("   %s (ExtResource \"%s\")" % (ext[eid], eid))
        return 2

    shared = _shared_sheets(ext, args.resource, project)
    if shared:
        print("%s\n  SALTADA: estas hojas las usa tambien otro recurso, asi que "
              "repaquetar\n  solo este las dejaria apuntando a un fichero que ya "
              "no existe:" % os.path.relpath(args.resource, project))
        for sheet, users in sorted(shared.items()):
            print("   %s\n      tambien en: %s" % (sheet, ", ".join(sorted(users))))
        return 2

    sources = {}
    before_px = 0
    for eid, res_path in ext.items():
        disk = os.path.join(project, res_path[len("res://"):])
        if not os.path.exists(disk):
            sys.exit("falta la fuente %s" % disk)
        img = Image.open(disk).convert("RGBA")
        sources[eid] = (disk, img)
        before_px += img.width * img.height

    used = sum(f.box_w * f.box_h for f in frames)

    # Try every width that is a multiple of the block, keep the smallest
    # total area. Narrow sheets waste less on the right edge but more on the
    # shelves, so the best width is not guessable.
    # Fewest sheets first, then fewest pixels.
    #
    # Minimising area alone picks a narrow width, because a narrow sheet
    # wastes less on the right edge - and then spreads the frames over far
    # more sheets than it started with. The first run of this did exactly
    # that: serena_sing went from 2 sheets to 15, which trades VRAM for
    # texture bindings and draw calls, and undoing a memory win by making
    # the renderer slower is not a win. Never ending up with more sheets
    # than the resource already had is the constraint that keeps it honest.
    limit = len(sources)
    best = None
    for width in range(_up(max(f.box_w for f in frames) + 2 * GUTTER),
                       MAX_SIDE + 1, BLOCK):
        packed = shelf_pack(frames, width)
        if packed is None:
            continue
        heights, total = packed
        key = (len(heights), total)
        if len(heights) > limit:
            continue
        if best is None or key < best[0]:
            best = (key, width, list(heights),
                    [(f.sub_id, f.sheet, f.dest) for f in frames])
    if best is None:
        print("  SALTADA: no cabe en %d hoja(s) de %d de lado como maximo"
              % (limit, MAX_SIDE))
        return 2
    _key, width, heights, placement = best
    total = _key[1]

    # shelf_pack mutated the frames on every attempt; replay the winner.
    by_id = {f.sub_id: f for f in frames}
    for sub_id, sheet, dest in placement:
        by_id[sub_id].sheet = sheet
        by_id[sub_id].dest = dest
    heights = [_up(h) for h in heights]
    total = sum(width * h for h in heights)

    print("%s" % os.path.relpath(args.resource, project))
    print("  fotogramas        : %d" % len(frames))
    print("  hojas ahora       : %d, %.2f Mpx" % (len(sources), before_px / 1e6))
    print("  pixeles utiles    : %.2f Mpx (%.1f%% de ocupacion)"
          % (used / 1e6, 100 * used / before_px))
    print("  hojas repaquetadas: %d de %dx%s, %.2f Mpx"
          % (len(heights), width, "/".join(str(h) for h in heights), total / 1e6))
    print("  ahorro            : %.1f%%  (ASTC 8x8: %.2f MB -> %.2f MB)"
          % (100 * (1 - total / before_px), before_px * 0.25 / 1e6,
             total * 0.25 / 1e6))

    if not args.apply:
        print("\n(prueba en seco; usa --apply para escribirlo)")
        return 0

    out_dir = os.path.abspath(args.out or root)
    os.makedirs(out_dir, exist_ok=True)
    if os.path.relpath(out_dir, project).startswith(".."):
        print("\n  AVISO: %s esta fuera del proyecto, asi que el source_file de\n"
              "  los .import no sera una ruta res:// valida. Sirve para mirar\n"
              "  el resultado; para usarlo de verdad hay que escribir dentro."
              % out_dir)
    stem = os.path.splitext(os.path.basename(args.resource))[0]
    stem = stem[:-7] if stem.endswith("_frames") else stem

    sheets = [Image.new("RGBA", (width, h), (0, 0, 0, 0)) for h in heights]
    for f in frames:
        _, src = sources[f.ext_id]
        block = src.crop((f.x0, f.y0, f.x1, f.y1))
        sheets[f.sheet].paste(block, f.dest)

    # The new sheets need .import files of their own. lullaby.astc_sprite
    # returns priority 0.0, below the built-in texture importer's, so Godot
    # would quietly import a brand new PNG with the wrong one - ASTC settings
    # lost, and nothing in the log to say so. The params are carried over
    # from the sheet being replaced rather than restated here, so a sheet
    # imported at some non-default block size keeps it.
    params = _source_params(sources)

    names = []
    for i, sheet in enumerate(sheets):
        name = "%s_packed_%d.png" % (stem, i)
        sheet.save(os.path.join(out_dir, name), optimize=True)
        names.append(name)
        rel = os.path.relpath(os.path.join(out_dir, name), project)
        rel = rel.replace(os.sep, "/")
        # uid, path and dest_files are deliberately absent: Godot assigns
        # them on first import, and a stale one copied from another texture
        # would collide.
        with open(os.path.join(out_dir, name + ".import"), "w",
                  encoding="utf-8") as f:
            f.write('[remap]\n\nimporter="lullaby.astc_sprite"\ntype="Texture2D"\n')
            f.write('\n[deps]\n\nsource_file="res://%s"\n' % rel)
            f.write("\n[params]\n\n%s\n" % params)

    new_text = _rewrite(text, args.resource, ext, frames, names, project)
    open(os.path.join(out_dir, os.path.basename(args.resource)), "w",
         encoding="utf-8").write(new_text)

    print("\nescrito en %s:" % os.path.relpath(out_dir, project))
    for n in names:
        print("   %s" % n)
    print("   %s" % os.path.basename(args.resource))
    return 0


def _rewrite(text, res_path, ext, frames, names, project):
    """Points the resource at the new sheets and moves every region."""
    res_dir = os.path.dirname(os.path.abspath(res_path))
    rel = os.path.relpath(res_dir, project).replace(os.sep, "/")

    new_ext = []
    for i, name in enumerate(names):
        new_ext.append('[ext_resource type="Texture2D" path="res://%s/%s" '
                       'id="packed_%d"]' % (rel, name, i))

    # Drop the old ext_resource lines and put the new ones where they were.
    lines = text.split("\n")
    kept, first = [], None
    for line in lines:
        if EXT_RE.match(line) and EXT_RE.match(line).group("id") in ext:
            if first is None:
                first = len(kept)
            continue
        kept.append(line)
    kept[first:first] = new_ext
    text = "\n".join(kept)

    for f in frames:
        nx = f.dest[0] + f.frac[0]
        ny = f.dest[1] + f.frac[1]
        old = ('atlas = ExtResource("%s")\nregion = Rect2(%s, %s, %s, %s)'
               % (f.ext_id, *(_num(v) for v in f.region)))
        new = ('atlas = ExtResource("packed_%d")\nregion = Rect2(%s, %s, %s, %s)'
               % (f.sheet, _num(nx), _num(ny),
                  _num(f.region[2]), _num(f.region[3])))
        if old not in text:
            sys.exit("no pude localizar la region de %s para reescribirla"
                     % f.sub_id)
        text = text.replace(old, new, 1)
    return text


def _mixed_use(text, ext, atlas_ids):
    """Sheets referenced by something other than an AtlasTexture's `atlas`.

    Counted by blanking every AtlasTexture block first and then looking for
    what is left, so a reference from a node or another sub-resource still
    shows up while the ones this tool is about to rewrite do not.
    """
    stripped = SUB_RE.sub(lambda m: "", text)
    mixed = set()
    for eid in atlas_ids:
        if eid not in ext:
            continue
        if re.search(r'ExtResource\("%s"\)' % re.escape(eid), stripped):
            mixed.add(eid)
    return mixed


SKIP_DIRS = {".git", ".godot", "original_pck", "builds", "android",
             "precompiled_astc_imports", "precompiled_texture_imports",
             "precompiled_lightmap_imports"}


def _shared_sheets(ext, resource, project):
    """Sheets this resource uses that something else uses too.

    Repacking replaces the sheets and deletes the originals, so a sheet with
    a second user has to be left alone - or that user is left pointing at a
    file that no longer exists, which is a broken import and not a wrong
    pixel, so it would not show up in the frame-by-frame verification at all.
    Searched as raw bytes so a binary .res that embeds the path or the uid
    counts as a user.
    """
    mine = os.path.abspath(resource)
    needles = {}
    for res_path in ext.values():
        disk = os.path.join(project, res_path[len("res://"):])
        keys = [res_path.encode()]
        imp = disk + ".import"
        if os.path.exists(imp):
            uid = re.search(r'uid="(uid://[a-z0-9]+)"',
                            open(imp, encoding="utf-8").read())
            if uid:
                keys.append(uid.group(1).encode())
        needles[res_path] = keys

    found = {}
    for root, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            path = os.path.join(root, name)
            if os.path.abspath(path) == mine:
                continue
            # The sheet's own .import names it, and so does any log lying
            # around; neither is a user of the atlas.
            if name.endswith((".import", ".log", ".md", ".txt")):
                continue
            try:
                blob = open(path, "rb").read()
            except OSError:
                continue
            for res_path, keys in needles.items():
                if any(k in blob for k in keys):
                    found.setdefault(res_path, set()).add(
                        os.path.relpath(path, project))
    return found


def _source_params(sources):
    """The [params] block of the sheets being replaced.

    They have to agree - one repacked sheet holds frames from all of them, so
    it can only be imported one way.
    """
    seen = set()
    for disk, _img in sources.values():
        imp = disk + ".import"
        if not os.path.exists(imp):
            continue
        text = open(imp, encoding="utf-8").read()
        block = text.split("[params]", 1)
        if len(block) == 2:
            seen.add(block[1].strip())
    if not seen:
        return "compress/block_size=8\ncompress/quality=100.0\nmipmaps/generate=false"
    if len(seen) > 1:
        # Exit 2, the same code as the other refusals: this is a resource to
        # leave alone, not a failure that should stop a batch. A sheet mixing
        # importers usually means part of it is not astc_sprite art at all.
        print("  SALTADA: las hojas de origen no comparten ajustes de "
              "importacion,\n  y una hoja repaquetada solo puede tener unos:")
        for block in sorted(seen):
            print("   ---\n%s" % "\n".join("   " + l for l in block.split("\n")))
        sys.exit(2)
    return seen.pop()


def _num(v):
    """Godot writes floats without a trailing .0 when they are whole."""
    return str(int(v)) if float(v).is_integer() else repr(round(float(v), 6))


if __name__ == "__main__":
    sys.exit(main())
