#!/usr/bin/env python3
"""No material in Chimera's house may sit on ALPHA_DEPTH_PRE_PASS.

`transparency = 4` draws the surface **twice** - an opaque depth pass and then
the transparent one - and leaves it in the transparent queue, where nothing
behind it can be depth-rejected. Godot documents it as expensive; on a
tile-based GPU, which is every device this ships to, it is worse than that.

Measured on the device's own renderer path (Vulkan, Forward Mobile), 24
overlapping masked quads, identical geometry in all four cases:

    OPAQUE             gpu  35.6ms   draws=24 prims=48 objs=24
    ALPHA_SCISSOR (2)  gpu 103.5ms   draws=24 prims=48 objs=24
    DEPTH_PRE_PASS(4)  gpu 399.0ms   draws=24 prims=48 objs=24
    ALPHA         (1)  gpu 404.1ms   draws=24 prims=48 objs=24

**3.86x against scissor, and the draw/primitive/object counts are byte
identical across all four.** That last part is why this went unfound for so
long: every count-based reading of the device log concluded "it is not
geometry" - correct - and then had nowhere left to go, because the counter
cannot see a surface being drawn twice.

The cross-device evidence is what made it the prime suspect. On 10154-8d1ee1ac
Chimera costs about twice the shop on **both** GPUs measured (Adreno 619 31.85
vs 15.49ms, Mali-G52 24.22 vs 14.68ms) while having fewer lights reaching the
camera (4 vs 6), fewer baked meshes (62 vs 102), no fog, and fewer draw calls
(21 vs 39). The one structural difference: Chimera's house had five materials
on mode 4 and the shop has none - all thirteen of its materials are opaque.

Scissor buys correct self-sorting only for genuinely soft alpha, and none of
these five has any. The share of texels between alpha 8 and 247 - the
antialiased edge, the only pixels scissor renders differently - recomputed
from the sources:

    props1     68.0% opaque   0.29% partial
    props2     77.2% opaque   0.26% partial
    plantt     46.4% opaque   0.64% partial
    FUKC       64.9% opaque   1.23% partial
    foliage    13.1% opaque   3.96% partial

Binary masks. And `grars` and `trash` in that same folder were already on
scissor, so this is the folder's own convention rather than a new idea.

Deliberately out of scope: `models/hex/materials/HexBroeknArms.tres`, which is
a real gradient - scissor would notch it - and lives in a different folder, so
the rule below cannot reach it by accident.

Run with:
    python3 tools/audit_house_transparency.py
"""

import os
import re
import sys

FOLDER = "lullaby_mod/assets/funkin/chimera/models/house/materials"
DEPTH_PRE_PASS = "4"


def main():
    if not os.path.isdir(FOLDER):
        print("no existe %s - nada que comprobar" % FOLDER)
        return 0

    offenders = []
    checked = 0
    for name in sorted(os.listdir(FOLDER)):
        if not name.endswith(".tres"):
            continue
        path = os.path.join(FOLDER, name)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if "StandardMaterial3D" not in text and "ORMMaterial3D" not in text:
            continue
        checked += 1
        found = re.search(r"^transparency = (\d+)", text, re.M)
        if found and found.group(1) == DEPTH_PRE_PASS:
            offenders.append(name)

    print("materiales de la casa comprobados : %d" % checked)
    print("   en ALPHA_DEPTH_PRE_PASS         : %d" % len(offenders))

    if offenders:
        print("")
        print("transparency = 4 dibuja la superficie dos veces y la deja en la cola")
        print("transparente, donde nada de detras se puede rechazar por profundidad.")
        print("Medido en la ruta del telefono: 3.86x contra ALPHA_SCISSOR, con los")
        print("mismos draw calls y primitivas - por eso el log no lo ve.")
        print("")
        print("Si esta malla necesita alfa suave de verdad, dilo aqui con su")
        print("porcentaje de texeles parciales, como se hizo con HexBroeknArms.")
        for name in offenders:
            print("   %s" % name)
        return 1

    print("")
    print("todo OK - la casa esta en opaco o scissor, ninguno en pre-pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
