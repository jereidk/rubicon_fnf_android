#!/usr/bin/env python3
"""Fail if two scripts claim the same global class_name.

Godot registers one script per global class name and picks the winner by
filesystem scan order. That order is not stable - it moves when files are
added, removed or reimported - so a duplicate is not a warning, it is a coin
flip re-tossed on every build, and the loser's callers silently bind to the
wrong implementation.

This project shipped six of them. reference/pck_gdanimate/ is a decompiled
copy of the pck's renderer, kept to diff the port against, and it declares
the same six class names as addons/gdanimate/: AdobeAtlas, AnimateAtlas,
AnimateDrawInfo, AnimateSymbol, SparrowAtlas and SparrowFrame. The addon's
copies have since diverged - AnimateSymbol is 470 lines against the
reference's 386 - so which one wins decides how every Adobe Animate
character in the game is drawn.

It was latent until .uid files were committed alongside the reference
copies, which is enough to change who registers first. The symptom was
Chimera drawing a black graphic over its own song, and a headless run here
resolving AnimateSymbol to the reference copy and failing on a method only
the addon has.

Usage:
    python3 tools/check_duplicate_class_names.py
"""

import os
import re
import sys
from collections import defaultdict

SKIP_DIRS = {".git", ".godot", "__pycache__"}
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)


def main():
    names = defaultdict(list)

    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        # A .gdignore makes Godot skip the whole directory - no scripts
        # registered, no class names claimed - so it is not a duplicate.
        # Checking it here rather than hardcoding a path keeps this honest
        # about what the engine actually sees.
        if ".gdignore" in files:
            dirs[:] = []
            continue
        for filename in files:
            if not filename.endswith(".gd"):
                continue
            path = os.path.join(root, filename)
            try:
                head = open(path, encoding="utf-8", errors="replace").read(2000)
            except OSError:
                continue
            match = CLASS_NAME.search(head)
            if match:
                names[match.group(1)].append(path.lstrip("./"))

    duplicates = {k: v for k, v in sorted(names.items()) if len(v) > 1}

    print("class_name globales : %d" % len(names))
    print("duplicados          : %d" % len(duplicates))

    if not duplicates:
        print("")
        print("todo OK - cada class_name pertenece a un solo script")
        return 0

    print("")
    for name, paths in duplicates.items():
        print("  %s" % name)
        for path in paths:
            print("      %s" % path)

    print("")
    print("Godot registra uno solo y elige por orden de escaneo, que cambia")
    print("entre builds. Quita el class_name de la copia que no se usa, o")
    print("saca ese directorio del proyecto.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
