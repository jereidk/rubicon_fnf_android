#!/usr/bin/env python3
"""Fail on ALPHA_DEPTH_PRE_PASS materials that do not earn it.

BaseMaterial3D.transparency = 4 is ALPHA_DEPTH_PRE_PASS. It draws the object
twice - an opaque depth pass and then the transparent one - so the geometry,
the vertex work and the depth writes are all paid for a second time. Godot's
own documentation calls it expensive and it is worst on a tile GPU, which is
what every Android device here has.

The mode buys correct self-sorting for a surface with genuinely soft alpha.
For a cutout mask it buys nothing: ALPHA_SCISSOR (2) discards below a
threshold in a single pass, writes depth, and lets early-z reject whatever is
behind it - which is the part that matters when the scene's overdraw is
already 3-7x.

Chimera's house had five materials on mode 4 whose masks are binary:

    props1     38.4% opaque   0.29% partial
    props2     36.9% opaque   0.26% partial
    plantt     21.2% opaque   0.64% partial
    FUKC       37.2% opaque   1.23% partial
    foliage     8.0% opaque   3.96% partial   (leaves, the classic scissor case)

"partial" is the share of texels between alpha 8 and 247 - the antialiased
edges, and the only pixels scissor renders differently. Two other materials in
that same folder, grars and trash, were already on scissor.

Exceptions are listed here with the number that justifies them rather than
being silently skipped, so the next person can see the reasoning and re-check
it if the texture changes.

Run with:
    python3 tools/audit_material_transparency.py [root...]
"""

import re
import sys
from pathlib import Path

DEPTH_PRE_PASS = re.compile(r"^transparency = 4$", re.M)

# path suffix -> why mode 4 stays. Measured, not assumed.
ALLOWED = {
    "models/hex/materials/HexBroeknArms.tres":
        "8.80% de sus texeles estan en alfa intermedio - es un degradado real, "
        "no un recorte, y scissor le pondria bordes duros",
    "console/icons/materials/mat_console_select.tres":
        "textura sin alfa util; sobra el modo pero es un icono pequeno y su "
        "histograma no esta explicado del todo - medir antes de tocarlo",
    "console/icons/materials/mat_console_inactive.tres":
        "igual que mat_console_select",
    "console/icons/materials/mat_console_idle.tres":
        "igual que mat_console_select",
}

SKIP_PARTS = {"reference", ".godot"}


def main(roots: list[str]) -> int:
    offenders: list[Path] = []
    allowed_seen = 0
    scanned = 0

    for root in roots:
        for path in sorted(Path(root).rglob("*")):
            if path.suffix not in (".tres", ".tscn", ".material"):
                continue
            if any(part in SKIP_PARTS for part in path.parts):
                continue
            scanned += 1
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if not DEPTH_PRE_PASS.search(text):
                continue

            excuse = next(
                (why for suffix, why in ALLOWED.items() if str(path).endswith(suffix)),
                None,
            )
            if excuse is not None:
                allowed_seen += 1
                print(f"permitido  {path}\n           {excuse}")
            else:
                offenders.append(path)

    for path in offenders:
        print(f"{path}: transparency = 4 (ALPHA_DEPTH_PRE_PASS)")
        print("    dibuja la geometria dos veces. Si su alfa es binaria usa 2 "
              "(ALPHA_SCISSOR); si es suave de verdad, anadelo a ALLOWED con "
              "el porcentaje de texeles intermedios que lo justifica.")

    print(f"\n{scanned} recursos revisados, {allowed_seen} excepciones conocidas")
    if offenders:
        print(f"{len(offenders)} material(es) pagan el doble sin necesitarlo")
        return 1
    print("todo OK - ningun material nuevo en ALPHA_DEPTH_PRE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["lullaby_mod", "addons", "scenes"]))
