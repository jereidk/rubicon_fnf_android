#!/usr/bin/env python3
"""Every precompiled .md5 sidecar must describe the file it is named after.

`precompiled_astc_imports/` holds pre-run importer output so CI does not spend
an hour on EXHAUSTIVE ASTC. Godot decides whether to reimport by reading the
sidecar's `source_md5` back and comparing it against the source PNG - so a
sidecar carrying the wrong file's hash makes Godot skip a texture that really
did change and ship the stale `.res`. Nothing about that fails a build; the
symptom is a wrong texture on a device.

That is not hypothetical. `tools/harvest_precompiled_imports.py` used to find
its output by scanning for anything starting with `<basename>-`, and take the
first hit. This project has **nine** file names that appear more than once
across 26 files - `spritemap1.png` nine times, `grass.png` three - so on those
the first hit is arbitrary. One run rewrote
`grass.png-86e92392fbe8410b224616a38ec6ed67.md5`, which belongs to
`serena/Running/grass.png`, with the content hash of
`intro/opening_shot/grass.png`.

The pairing is not ambiguous and never was: Godot names the output
`<basename>-<md5 of the res:// source path>.res`, verified against all 505 ASTC
textures here, 505 for 505. So the hash in the file name identifies exactly one
source, and this checks each sidecar against that one.

Three outcomes, and only one of them is fatal:

- **cruzado** - the declared hash is the content of a *different* file that
  shares the base name. Provably the collision bug, cannot be a false positive,
  fails the build.
- **obsoleto** - the declared hash matches nothing. The source changed and the
  output was not regenerated. Safe: Godot notices and reimports, which is slow
  and correct. Reported, does not fail.
- **huerfano** - no ASTC `.import` claims that path hash any more. Also safe -
  the file is dead weight in LFS, not a wrong answer.

Run with:
    python3 tools/audit_precompiled_sidecars.py
"""

import collections
import hashlib
import os
import re
import sys

OUT_DIR = "precompiled_astc_imports"
IMPORTER = "lullaby.astc_sprite"


def astc_sources():
    """Every source PNG imported through the project's ASTC importer."""
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot")]
        for name in files:
            if not name.endswith(".import"):
                continue
            path = os.path.join(root, name)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            if IMPORTER not in text:
                continue
            source = path[: -len(".import")]
            yield source[2:] if source.startswith("./") else source


def md5_file(path):
    with open(path, "rb") as handle:
        return hashlib.md5(handle.read()).hexdigest()


def main():
    if not os.path.isdir(OUT_DIR):
        print("no hay %s - nada que comprobar" % OUT_DIR)
        return 0

    owner = {}
    by_base = collections.defaultdict(list)
    for source in astc_sources():
        owner[hashlib.md5(("res://" + source).encode()).hexdigest()] = source
        by_base[os.path.basename(source)].append(source)

    ok = stale = orphan = 0
    crossed = []
    stale_names = []

    for name in sorted(os.listdir(OUT_DIR)):
        if not name.endswith(".md5"):
            continue
        parts = re.match(r"^(.*)-([0-9a-f]{32})\.md5$", name)
        if not parts:
            continue
        base, path_hash = parts.groups()
        source = owner.get(path_hash)
        if source is None:
            orphan += 1
            continue

        try:
            declared = open(os.path.join(OUT_DIR, name)).read().split('"')[1]
        except (OSError, IndexError):
            crossed.append((name, source, "(sidecar ilegible)"))
            continue

        if declared == md5_file(source):
            ok += 1
            continue

        # The distinguishing question: does the declared hash belong to some
        # OTHER file with the same base name? If it does, this sidecar was
        # written from the wrong source and Godot will trust it.
        others = [
            other for other in by_base[base]
            if other != source and md5_file(other) == declared
        ]
        if others:
            crossed.append((name, source, others[0]))
        else:
            stale += 1
            stale_names.append((name, source))

    print("sidecars comprobados : %d" % (ok + stale + orphan + len(crossed)))
    print("   correctos          : %d" % ok)
    print("   obsoletos (aviso)  : %d" % stale)
    print("   huerfanos (aviso)  : %d" % orphan)
    print("   CRUZADOS (fatal)   : %d" % len(crossed))

    for name, source in stale_names[:10]:
        print("   obsoleto: %s -> %s" % (name, source))

    if crossed:
        print("")
        print("Un sidecar describe un fichero distinto del que le toca. Godot lee")
        print("source_md5 para decidir si reimportar, asi que se saltara una textura")
        print("que si cambio y enviara el .res viejo.")
        for name, source, other in crossed:
            print("")
            print("   %s" % name)
            print("      le toca : %s" % source)
            print("      describe: %s" % other)
        return 1

    print("")
    print("todo OK - cada sidecar describe su propia fuente")
    return 0


if __name__ == "__main__":
    sys.exit(main())
