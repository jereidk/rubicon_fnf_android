#!/usr/bin/env python3
"""The console's icon-plaque materials must stay off any alpha mode.

`mat_console_inactive.tres`, `mat_console_select.tres` and
`mat_console_idle.tres` drive the six icon models in the shop console's Home
tab (`Viewports/ConsoleSubViewport/Console/TabContainer/Home/IconSubViewport`,
already the single most expensive SubViewport in the shop). All three shipped
`transparency = 4` (ALPHA_DEPTH_PRE_PASS - draws the surface twice, same cost
class already fixed in Chimera's house) over textures with **no transparency
to draw**: `uigradient_tex.png` and `uigradientSELECT_tex.png` are opaque
across every texel bar isolated compression noise at alpha=254 (checked
against the real PNGs with `tools/audit_opaque_transparency_modes.py`, which
needs Pillow and is a discovery tool, not a CI gate - same split as
`audit_house_transparency.py`'s own alpha-histogram work).

Measured on the phone's path (Vulkan, Forward Mobile), six small quads at the
IconSubViewport's real resolution (720x540) rather than Chimera's house-sized
walls:

    OPAQUE (0)          gpu 4.07ms
    ALPHA_SCISSOR (2)   gpu 4.38ms
    DEPTH_PRE_PASS (4)  gpu 4.33ms

Real but modest at this screen coverage - nowhere near the house's 3.86x on
big walls, because six icon-sized quads do not have much per-pixel cost to
double in the first place. Free money regardless: the texture never crosses
any alpha threshold, so OPAQUE is pixel-identical to what shipped, at a lower
cost with zero quality tradeoff to weigh - unlike a scissor conversion, this
one needs no threshold tuning.

Run with:
    python3 tools/audit_console_icon_materials.py
"""

import os
import re
import sys

FOLDER = "lullaby_mod/assets/menus/console/icons/materials"
KNOWN_SAFE = ("mat_console_inactive.tres", "mat_console_select.tres", "mat_console_idle.tres")
ALPHA_MODES = {"1": "ALPHA", "2": "ALPHA_SCISSOR", "3": "ALPHA_HASH", "4": "ALPHA_DEPTH_PRE_PASS"}


def main() -> int:
    if not os.path.isdir(FOLDER):
        print("no existe %s - nada que comprobar" % FOLDER)
        return 0

    offenders = []
    missing = []
    checked = 0
    for name in KNOWN_SAFE:
        path = os.path.join(FOLDER, name)
        if not os.path.isfile(path):
            missing.append(name)
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        checked += 1
        found = re.search(r"^transparency = (\d+)", text, re.M)
        mode = found.group(1) if found else "0"
        if mode in ALPHA_MODES:
            offenders.append((name, ALPHA_MODES[mode]))

    print("materiales de iconos comprobados : %d" % checked)
    print("   con un modo de alfa activo     : %d" % len(offenders))

    if missing:
        print("")
        print("no encontrados (renombrados o movidos - revisar la ruta):")
        for name in missing:
            print("   %s" % name)

    if offenders:
        print("")
        print("Las dos texturas que usan estos materiales son opacas en la practica")
        print("(el peor texel es ruido de redondeo a 254/255, no un borde suave real -")
        print("ver tools/audit_opaque_transparency_modes.py). Un modo de alfa activo")
        print("aqui solo paga trabajo por pixel sin comprar nada a cambio.")
        for name, mode in offenders:
            print("   %s -> %s" % (name, mode))
        return 1

    if missing:
        return 1

    print("")
    print("todo OK - los tres siguen en transparency=0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
