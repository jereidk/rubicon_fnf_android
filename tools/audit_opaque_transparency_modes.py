#!/usr/bin/env python3
"""StandardMaterial3D/ORMMaterial3D resources paying for alpha handling their
own texture never uses.

`transparency` (0=DISABLED/opaque, 1=ALPHA, 2=ALPHA_SCISSOR, 4=ALPHA_DEPTH_PRE_PASS)
picks how the rasteriser treats this material's fragments. Measured on the
phone's path (Vulkan, Forward Mobile):

  - large opaque surfaces (Chimera's house walls, ~1600x720 worth of pixels):
    DEPTH_PRE_PASS 399.0ms vs ALPHA_SCISSOR 103.5ms vs OPAQUE 35.6ms - a
    3.86x-11.2x difference, all on byte-identical draws/prims/objs.
  - six small icon plaques (720x540 SubViewport, the shop's Home tab icons):
    DEPTH_PRE_PASS 4.33ms vs OPAQUE 4.07ms - a real but modest ~6% at this
    much smaller screen coverage.

Either way it is free money when the material's albedo has no transparency to
lose: `transparency` at anything but DISABLED only buys something when a
texel's alpha can actually fall inside the tested range, and a material whose
texture (and albedo_color) are opaque everywhere never crosses that test.
This is what caught mat_console_inactive/select/idle - three UI icon plaque
materials shipping ALPHA_DEPTH_PRE_PASS over textures with 0% of their texels
below full opacity.

    python3 tools/audit_opaque_transparency_modes.py [file.tres ...]

With no arguments it sweeps every StandardMaterial3D/ORMMaterial3D .tres in
lullaby_mod/ and addons/. Prints a finding only when BOTH the texture (if any)
and albedo_color are fully opaque - never fixes a material that has real
alpha to lose, and never guesses at a threshold the way ALPHA_SCISSOR
conversions do (that decision needs alpha_scissor_threshold tuning per
texture, which this does not attempt).
"""
import re, sys, os, glob

try:
    from PIL import Image
except ImportError:
    print("Necesita Pillow: pip install Pillow", file=sys.stderr)
    sys.exit(2)

TRANSPARENCY_NAMES = {"1": "ALPHA", "2": "ALPHA_SCISSOR", "3": "ALPHA_HASH", "4": "ALPHA_DEPTH_PRE_PASS"}


def prop(text, name):
    m = re.search(r"^%s = (.+)$" % re.escape(name), text, re.M)
    return m.group(1).strip() if m else None


def albedo_alpha(text):
    color = prop(text, "albedo_color")
    if color is None:
        return 1.0
    m = re.match(r"Color\(([^)]*)\)", color)
    if not m:
        return 1.0
    parts = [float(x) for x in m.group(1).split(",")]
    return parts[3] if len(parts) == 4 else 1.0


def texture_res_path(text):
    tex_id = prop(text, "albedo_texture")
    if tex_id is None:
        return None
    m = re.search(r'ExtResource\("([^"]+)"\)', tex_id)
    if not m:
        return None
    rid = m.group(1)
    m2 = re.search(r'\[ext_resource type="Texture2D"[^\]]*path="([^"]*)"[^\]]*id="%s"\]' % re.escape(rid), text)
    if not m2:
        m2 = re.search(r'\[ext_resource type="Texture2D"[^\]]*id="%s"[^\]]*path="([^"]*)"\]' % re.escape(rid), text)
    return m2.group(1) if m2 else None


## Tolerancia sobre 255: el hueco mas pequeno representable en 8 bits contra
## el fondo de maximo contraste es (1-254/255)*255 ~= 1 unidad de canal - el
## piso de ruido de redondeo/compresion, no un borde suave real. Un texel
## suelto a 254 (`uigradientSELECT_tex.png` lo tiene) no puede producir una
## diferencia visible entre desactivado y cualquier modo con alfa; exigir 255
## exacto habria descartado ese caso por ruido, no por contenido real. Un
## borde suave de verdad deja una franja de texeles bajo este umbral, no uno
## suelto - por eso "casi todos por encima" sigue siendo una senal fuerte.
OPAQUE_FLOOR = 254


def texture_is_opaque(res_path):
    local = res_path.replace("res://", "")
    if not os.path.exists(local):
        return None  # no se puede comprobar - no se afirma nada
    try:
        img = Image.open(local).convert("RGBA")
    except Exception:
        return None
    for _, _, _, a in img.getdata():
        if a < OPAQUE_FLOOR:
            return False
    return True


def audit(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    if 'type="StandardMaterial3D"' not in text and 'type="ORMMaterial3D"' not in text:
        return []
    transparency = prop(text, "transparency")
    if transparency is None or transparency == "0":
        return []
    if transparency not in TRANSPARENCY_NAMES:
        return []

    if not (albedo_alpha(text) >= 1.0 - 1e-6):
        return []  # el propio albedo_color ya es semitransparente - hace falta

    tex_path = texture_res_path(text)
    if tex_path is None:
        # Sin textura, todo el alfa lo decide albedo_color, y ya se comprobó
        # que es opaco.
        opaque = True
    else:
        opaque = texture_is_opaque(tex_path)
        if opaque is None:
            return []  # textura no localizable - no se afirma nada

    if not opaque:
        return []

    return [(TRANSPARENCY_NAMES[transparency], tex_path)]


def main() -> int:
    paths = sys.argv[1:] or sorted(
        glob.glob("lullaby_mod/**/*.tres", recursive=True) + glob.glob("addons/**/*.tres", recursive=True))

    total = 0
    for path in paths:
        for mode, tex in audit(path):
            print("[COSTE] %-70s %-20s textura opaca: %s" % (path, mode, tex or "(sin textura)"))
            total += 1
    print("\n%d ficheros barridos, %d hallazgos" % (len(paths), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
