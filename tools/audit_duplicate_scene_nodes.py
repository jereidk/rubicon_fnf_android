#!/usr/bin/env python3
"""Fail on two [node] blocks describing the same node in one scene.

Written after shipping exactly that. An override block for an instanced
scene's child is added by name and parent path, and adding a second one for
the same child instead of editing the first is a silent mistake: the file
still loads, Godot applies both in order, and the result is whichever
properties the later block happens to set on top of whatever the earlier one
left behind. It looked right on the device because the two happened not to
disagree, which is the worst way for it to look right.

Nothing about it is visible in a diff either - the new block reads as a
perfectly ordinary addition, several thousand lines away from the one it
duplicates.

Run with:
    python3 tools/audit_duplicate_scene_nodes.py [root...]
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

# name= and parent= as written in a .tscn [node] header. parent is absent on
# the root node, which is the one node a scene can only have once anyway.
HEADER = re.compile(r'^\[node ')
NAME = re.compile(r'\bname="([^"]*)"')
PARENT = re.compile(r'\bparent="([^"]*)"')

# Directories that are copies of somebody else's scenes, kept for comparison.
SKIP_PARTS = {"reference", ".godot", "addons/gdanimate/examples"}


def duplicates(path: Path) -> list[tuple[str, list[int]]]:
    seen: dict[tuple[str, str], list[int]] = defaultdict(list)
    with path.open(encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle, start=1):
            if not HEADER.match(line):
                continue
            name = NAME.search(line)
            if name is None:
                continue
            parent = PARENT.search(line)
            seen[(parent.group(1) if parent else "", name.group(1))].append(number)

    return [
        (f"{parent}/{name}" if parent else name, lines)
        for (parent, name), lines in seen.items()
        if len(lines) > 1
    ]


def main(roots: list[str]) -> int:
    scenes: list[Path] = []
    for root in roots:
        for scene in sorted(Path(root).rglob("*.tscn")):
            if any(part in SKIP_PARTS for part in scene.parts):
                continue
            if any(str(scene).startswith(skip) for skip in SKIP_PARTS):
                continue
            scenes.append(scene)

    found = 0
    for scene in scenes:
        for node, lines in duplicates(scene):
            found += 1
            print(
                f"{scene}: '{node}' descrito {len(lines)} veces "
                f"(lineas {', '.join(str(line) for line in lines)})"
            )

    print(f"\n{len(scenes)} escenas revisadas")
    if found:
        print(f"{found} nodo(s) duplicado(s) - el ultimo bloque gana a medias")
        return 1
    print("todo OK - ningun nodo descrito dos veces")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["lullaby_mod", "addons", "scenes"]))
