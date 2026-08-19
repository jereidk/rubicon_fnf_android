#!/usr/bin/env python3
"""Fail when a .lmbake's text-path fallback points at a file that is not there.

A LightmapGIData stores its baked texture as an external reference, and that
reference is a PAIR: a UID and a plain `res://` path. Godot tries the UID first
and drops to the path when it cannot resolve it. Import-time UID resolution in
this project works; EXPORT-time resolution does not, broadly - 84d99d5 read the
CI log for a real crash and counted ~1300 invalid-UID warnings across ~227
files during the export step alone. So on the APK the text path is not a
fallback, it is the path that gets used.

Which makes a missing file at that path invisible everywhere it is convenient
to look:

  - a plain-text grep does not find the reference, it is inside a binary
    resource (8878770)
  - ResourceLoader.get_dependencies() does not walk it either, it is the
    wrapper's fallback field rather than a dependency edge (e191f1e, 84d99d5)
  - the project loads fine on this side, because here the UID resolves
  - and only ONE of the two bakes crashes when its texture is missing. The
    collector shop threw "Failed to load resource" and got fixed the same
    night. Chimera does not throw: a LightmapGI with no texture is a legal
    LightmapGI, so the house simply renders with no baked light and the player
    reports "the screen is black from the end of the intro until the flash".
    That one went eleven days.

e191f1e deleted both of those .exr files as orphans after an audit that was
careful, documented, and looked in all the places that cannot see this. This
check looks in the one place that can.

Run with:
    python3 tools/audit_lightmap_fallback_paths.py [root...]
"""

import re
import sys
from pathlib import Path

# `res://` followed by printable ASCII. Binary resources store their strings
# NUL-padded, so the run ends at the first byte outside that set.
RES_PATH = re.compile(rb"res://[ -~]+")

SKIP_PARTS = {"reference", ".godot", ".git"}


def referenced_paths(blob: bytes, own_name: str) -> list[str]:
    """Every distinct res:// path a .lmbake points OUT at, in order.

    A binary resource also records the path it was saved under, and here that
    is the path it had in the PC project (`res://songs/chimera/...`) rather
    than the one it lives at now. Nothing loads through that field - it is
    ResourceFormatLoaderBinary's own bookkeeping - so checking it would report
    a break on every bake in the mod for a path that is never opened.

    Matched on the file name rather than on the `.lmbake` suffix, so a bake
    that genuinely references a DIFFERENT bake is still checked.
    """
    seen: dict[str, None] = {}
    for match in RES_PATH.finditer(blob):
        ref = match.group(0).decode("ascii")
        if ref.rsplit("/", 1)[-1] == own_name:
            continue
        seen.setdefault(ref, None)
    return list(seen)


def main(roots: list[str]) -> int:
    missing: list[tuple[Path, str]] = []
    checked = 0
    bakes = 0

    for root in roots:
        for bake in sorted(Path(root).rglob("*.lmbake")):
            if any(part in SKIP_PARTS for part in bake.parts):
                continue
            bakes += 1
            try:
                blob = bake.read_bytes()
            except OSError as err:
                print(f"{bake}: no se pudo leer ({err})")
                return 1

            for ref in referenced_paths(blob, bake.name):
                checked += 1
                target = Path(ref.removeprefix("res://"))
                if target.exists():
                    continue
                missing.append((bake, ref))

    for bake, ref in missing:
        print(f"{bake}")
        print(f"    apunta a {ref}, que no existe")
        print("    Es la ruta que usa el export cuando el UID no resuelve, asi")
        print("    que en el APK esto es el archivo que se carga. Restaura el")
        print("    fichero en esa ruta exacta - mover el que existe NO sirve,")
        print("    la ruta esta escrita dentro del binario del .lmbake.")

    print(f"\n{bakes} .lmbake revisados, {checked} referencia(s) comprobadas")
    if missing:
        print(f"{len(missing)} referencia(s) rotas: el bake no cargara en el APK")
        return 1
    print("todo OK - cada .lmbake encuentra su textura por ruta, no solo por UID")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["."]))
