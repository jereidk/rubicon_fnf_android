#!/usr/bin/env python3
"""What a scene's dependency graph actually weighs, by asset and by kind.

The Collector's Shop takes 32.3s to load cold and then 35.6s more to warm its
pipelines. The device log cannot say what is heavy inside that: its dependency
probe is capped at 120ms of breadth-first walking, so the 112 paths it reports
are the shallowest ones, not the graph. This walks the whole thing offline.

Sizes are of the source assets on disk. For a texture that is not what the GPU
receives - an ASTC 8x8 import is 0.25 bytes per pixel regardless of how well
the PNG compressed - so pixel counts are reported alongside, since that is what
decides both VRAM and upload time.

Usage:
    python3 tools/audit_scene_weight.py [scene.tscn ...]
"""

import re
import struct
import sys
from collections import defaultdict
from pathlib import Path

SCENES = sys.argv[1:] or ["lullaby_mod/rooms/env_collector_shop.tscn"]

# ext_resource lines in .tscn/.tres, and the bare path= in .import files.
DEP = re.compile(r'path="(res://[^"]+)"')
TEXT_KINDS = {".tscn", ".tres", ".godot", ".import", ".gdshader"}


def disk(res_path):
    return Path(res_path.removeprefix("res://"))


def png_size(path):
    """Width/height from a PNG header, without decoding it."""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return struct.unpack(">II", head[16:24])
    except Exception:
        return None


def walk(scene):
    seen, queue, found = set(), [scene], []
    while queue:
        res = queue.pop(0)
        if res in seen:
            continue
        seen.add(res)

        p = disk(res)
        if not p.exists():
            continue
        found.append((res, p.stat().st_size))

        if p.suffix.lower() not in TEXT_KINDS:
            # A texture or model carries its own .import, which names nothing
            # further that matters here.
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for m in DEP.finditer(text):
            if m.group(1) not in seen:
                queue.append(m.group(1))
    return found


for scene in SCENES:
    if not Path(disk(scene) if scene.startswith("res://") else scene).exists():
        print("no existe: %s" % scene)
        continue

    root = scene if scene.startswith("res://") else "res://" + scene
    found = walk(root)

    by_kind = defaultdict(lambda: [0, 0])  # count, bytes
    pixels = 0
    biggest = []
    for res, size in found:
        ext = Path(res).suffix.lower() or "(sin ext)"
        by_kind[ext][0] += 1
        by_kind[ext][1] += size
        biggest.append((size, res))
        if ext == ".png":
            wh = png_size(disk(res))
            if wh:
                pixels += wh[0] * wh[1]

    total = sum(s for _, s in found)
    print("=" * 74)
    print("%s" % root)
    print("  %d archivos, %.1f MB en disco" % (len(found), total / 1048576))
    if pixels:
        print("  %.1f MPx de PNG  ->  ~%.1f MB en ASTC 8x8 (0.25 B/px)"
              % (pixels / 1e6, pixels * 0.25 / 1048576))
    print()

    print("  por tipo:")
    for ext, (n, size) in sorted(by_kind.items(), key=lambda kv: -kv[1][1])[:12]:
        print("    %-10s %4d archivos  %8.2f MB" % (ext, n, size / 1048576))
    print()

    print("  los 15 mas pesados:")
    biggest.sort(reverse=True)
    for size, res in biggest[:15]:
        extra = ""
        if res.lower().endswith(".png"):
            wh = png_size(disk(res))
            if wh:
                extra = "  (%dx%d = %.1f MPx)" % (wh[0], wh[1], wh[0] * wh[1] / 1e6)
        print("    %8.2f MB  %s%s" % (size / 1048576, res.removeprefix("res://"), extra))
    print()
