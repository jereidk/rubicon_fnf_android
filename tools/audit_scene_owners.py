#!/usr/bin/env python3
"""Attributes a scene's dependency graph to the sub-scenes that pull it in.

The shop's cold load is bound by per-file cost, so the useful question is not
which asset is biggest but which subsystem is responsible for the most files -
that is what says where a lazy-loading change would pay.

Walks the graph breadth-first remembering the chain, then charges each file to
the nearest .tscn above it. A file reachable through several sub-scenes is
charged to the first one that reached it, so the columns add up to the whole
and no file is counted twice.

Usage:
    python3 tools/audit_scene_owners.py [scene.tscn]
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

SCENE = sys.argv[1] if len(sys.argv) > 1 else "lullaby_mod/rooms/env_collector_shop.tscn"
ROOT = SCENE if SCENE.startswith("res://") else "res://" + SCENE

DEP = re.compile(r'path="(res://[^"]+)"')
TEXT = {".tscn", ".tres", ".import", ".gdshader"}


def disk(res):
    return Path(res.removeprefix("res://"))


seen = {ROOT}
queue = [(ROOT, ROOT)]          # (path, owning .tscn)
owner_of = {ROOT: ROOT}
files = []

while queue:
    res, owner = queue.pop(0)
    p = disk(res)
    if not p.exists():
        continue
    files.append(res)

    if p.suffix.lower() not in TEXT:
        continue
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue

    # A .tscn becomes the owner of everything below it; anything else passes
    # its own owner down.
    child_owner = res if p.suffix.lower() == ".tscn" else owner
    for m in DEP.finditer(text):
        dep = m.group(1)
        if dep in seen:
            continue
        seen.add(dep)
        owner_of[dep] = child_owner
        queue.append((dep, child_owner))

by_owner = defaultdict(lambda: [0, 0])
for res in files:
    o = owner_of.get(res, ROOT)
    by_owner[o][0] += 1
    b = disk(res)
    by_owner[o][1] += b.stat().st_size if b.exists() else 0

total_files = len(files)
total_bytes = sum(v[1] for v in by_owner.values())

print("%s" % ROOT)
print("  %d archivos, %.1f MB" % (total_files, total_bytes / 1048576))
print()
print("  %-46s %6s  %8s  %5s" % ("quien lo arrastra", "arch", "MB", "% arch"))
for o, (n, b) in sorted(by_owner.items(), key=lambda kv: -kv[1][0]):
    print("  %-46s %6d  %8.2f  %4.0f%%"
          % (Path(o).name, n, b / 1048576, 100.0 * n / total_files))
