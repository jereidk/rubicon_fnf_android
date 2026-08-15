#!/usr/bin/env python3
"""Attributes a scene's dependency graph to the sub-scenes that pull it in.

The shop's cold load is bound by per-file cost, so the useful question is not
which asset is biggest but which subsystem is responsible for the most files -
that is what says where a lazy-loading change would pay.

Walks the graph breadth-first remembering the chain, then charges each file to
the nearest .tscn above it. A file reachable through several sub-scenes is
charged to the first one that reached it, so the columns add up to the whole
and no file is counted twice.

With --chain it answers the other question instead: how does this scene reach
that file? Which is the one that stops a finding turning into a wrong fix.
Monochrome pulls a 2.6MB font, and the chain says it arrives through
sng_debugger.tscn and the debug theme - a debug tool shipping inside a song,
which looks like an easy win right up until you notice atl_debug.tscn is an
autoload, so the font is resident from boot and the song's reference costs
nothing at all.

Usage:
    python3 tools/audit_scene_owners.py [scene.tscn]
    python3 tools/audit_scene_owners.py [scene.tscn] --chain <substring>
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
CHAIN = None
if "--chain" in sys.argv:
    i = sys.argv.index("--chain")
    if i + 1 < len(sys.argv):
        CHAIN = sys.argv[i + 1]
        if CHAIN in ARGS:
            ARGS.remove(CHAIN)

SCENE = ARGS[0] if ARGS else "lullaby_mod/rooms/env_collector_shop.tscn"
ROOT = SCENE if SCENE.startswith("res://") else "res://" + SCENE

DEP = re.compile(r'path="(res://[^"]+)"')
TEXT = {".tscn", ".tres", ".import", ".gdshader"}


def disk(res):
    return Path(res.removeprefix("res://"))


seen = {ROOT}
queue = [(ROOT, ROOT)]          # (path, owning .tscn)
owner_of = {ROOT: ROOT}
referrer = {}
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
        # The immediate referrer, which is what --chain walks: owner_of only
        # remembers the nearest .tscn, and a chain that skipped the .tres in
        # the middle would hide exactly where a dependency is introduced.
        referrer[dep] = res
        queue.append((dep, child_owner))

if CHAIN is not None:
    hits = [r for r in files if CHAIN in r]
    if not hits:
        print("nada en el grafo de %s contiene %r" % (Path(ROOT).name, CHAIN))
        sys.exit(0)
    for hit in hits:
        chain, cur = [], hit
        while cur in referrer:
            chain.append(cur)
            cur = referrer[cur]
        chain.append(cur)
        print("como se llega a %s:" % Path(hit).name)
        for depth, step in enumerate(reversed(chain)):
            print("  " + "  " * depth + "-> " + step.removeprefix("res://"))
        print()
    sys.exit(0)

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
