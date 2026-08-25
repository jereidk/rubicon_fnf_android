#!/usr/bin/env python3
"""Guard de la fusion del fondo del callejon (Safety Lullaby).

Lo que fija:

1. La receta es reproducible: regenera back_merged.png con
   tools/bake_alley_background.py y exige que sea byte-identico al commitado.
   Si alguien mueve una capa o cambia un PNG fuente, esto dice que hay que
   rehornear, en vez de que el fondo y la escena se deslicen separados.
2. alley.tscn tiene la forma esperada: Parallax2 con exactamente MergedBack y
   Lamp1 (Lamp1 queda fuera de la fusion - lleva lamp_flicker.gd y las tres
   luces), con la posicion/escala que imprime el horneado.
3. ext_resource declarados == usados, y back_merged.png.import existe con el
   importador lullaby.astc_sprite y el mismo uid que declara la escena.
4. sng_safety_lullaby.tscn no referencia los nodos que la fusion quito.

Sin dependencias: usa la misma receta que bake_alley_background.py.
"""
import hashlib
import io
import os
import re
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLEY = os.path.join(REPO, "lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn")
SNG = os.path.join(REPO, "lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn")
MERGED = os.path.join(REPO, "lullaby_mod/assets/funkin/safety_lullaby/maps/alley/back_merged.png")
MERGED_IMPORT = MERGED + ".import"
BAKER = os.path.join(REPO, "tools/bake_alley_background.py")

failures = []


def check(ok: bool, what: str) -> None:
    print(("  ok   " if ok else "  FALLO ") + what)
    if not ok:
        failures.append(what)


def main() -> int:
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        print("FALLO: necesita Pillow (pip install Pillow)")
        return 1

    # 1. Receta reproducible: hornear en un directorio temporal y comparar.
    import subprocess
    with tempfile.TemporaryDirectory() as tmp:
        # El horneado escribe junto a las fuentes; redirigir copiando el
        # arbol minimo y parcheando BASE/OUT.
        src = open(BAKER).read()
        rel = "lullaby_mod/assets/funkin/safety_lullaby/maps/alley/"
        baked = src.replace('BASE = "%s"' % rel, 'BASE = "%s"' % os.path.join(REPO, rel))
        baked = baked.replace('OUT = BASE + "back_merged.png"',
                              'OUT = %r' % os.path.join(tmp, "back_merged.png"))
        p = subprocess.run([sys.executable, "-c", baked], capture_output=True, text=True)
        check(p.returncode == 0, "el horneado corre limpio%s" % ("" if p.returncode == 0 else ": " + p.stderr[-200:]))
        m = re.search(r"lienzo (\d+)x(\d+)", p.stdout)
        check(m is not None and (int(m.group(1)) % 8 == 0 and int(m.group(2)) % 8 == 0),
              "el lienzo sale multiplo de 8 (%s)" % (m.group(0) if m else "sin tamano"))
        m2 = re.search(r"position = Vector2\(([\d.-]+), ([\d.-]+)\) scale = Vector2\(([\d.-]+),", p.stdout)
        check(m2 is not None, "el horneado imprime posicion y escala")
        if os.path.exists(MERGED) and p.returncode == 0:
            new = open(os.path.join(tmp, "back_merged.png"), "rb").read()
            old = open(MERGED, "rb").read()
            check(hashlib.md5(new).hexdigest() == hashlib.md5(old).hexdigest(),
                  "back_merged.png es byte-identico a la receta (rehornear si cambio una fuente)")
        else:
            check(False, "back_merged.png existe y se genero")

    scene = open(ALLEY).read()

    # 2. Forma de la escena.
    names = re.findall(r'\[node name="([^"]+)"[^\]\n]*parent="BG/Parallax2"[^\]\n]*\]', scene)
    check(names == ["MergedBack", "Lamp1"],
          "Parallax2 tiene exactamente MergedBack y Lamp1 (tiene: %s)" % ", ".join(names))

    mb = re.search(r'\[node name="MergedBack"[^\]]*\]\n((?:[^\[\n].*\n)*)', scene)
    check(mb is not None, "MergedBack existe")
    if mb:
        props = mb.group(1)
        check("light_mask = 0" in props,
              "MergedBack va fuera de la mascara del BgLight (esta horneado)")
        if m2:
            pos = re.search(r"position = Vector2\(([\d.-]+), ([\d.-]+)\)", props)
            check(pos is not None
                  and abs(float(pos.group(1)) - float(m2.group(1))) < 0.01
                  and abs(float(pos.group(2)) - float(m2.group(2))) < 0.01,
                  "MergedBack tiene la posicion del horneado")
            check("scale = Vector2(%s, %s)" % (m2.group(3), m2.group(3)) in props,
                  "MergedBack tiene la escala del horneado")
    # 2b. El override de la cancion sigue poniendo la energia que se horneo.
    sng_text_check = open(SNG).read()
    bg = re.search(r'\[node name="BgLight"[^\]]*\]\n((?:[^\[\n].*\n)*)', sng_text_check)
    check(bg is not None and re.search(r"energy = 0.75\b", bg.group(1)),
          "la cancion sigue reescribiendo BgLight a la energia horneada (0.75)")

    # 3. ext_resource declarados == usados.
    declared = set(re.findall(r'\[ext_resource [^\]]* id="([^"]+)"\]', scene))
    used = set(re.findall(r'ExtResource\("([^"]+)"\)', scene))
    check(declared == used, "ext_resource declarados == usados (sobran: %s, faltan: %s)"
          % (sorted(declared - used), sorted(used - declared)))

    check(os.path.exists(MERGED_IMPORT), "back_merged.png.import existe")
    if os.path.exists(MERGED_IMPORT):
        imp = open(MERGED_IMPORT).read()
        check('importer="lullaby.astc_sprite"' in imp, "el sidecar usa el importador ASTC")
        uid = re.search(r'uid="(uid://[^"]+)"', imp)
        ext = re.search(r'\[ext_resource [^\]]*back_merged\.png" id="15"\]', scene)
        ext_uid = re.search(r'\[ext_resource type="Texture2D" uid="(uid://[^"]+)"[^\]]*back_merged', scene)
        check(uid is not None and ext_uid is not None and uid.group(1) == ext_uid.group(1),
              "el uid del sidecar y el de la escena coinciden")
        check(ext is not None, "la escena referencia back_merged.png")

    # 4. La cancion no referencia los nodos quitados.
    sng = open(SNG).read()
    stale = [n for n in ["Street", "Trees", "LongFence", "Bench", "Pokecenter", "Lamp2", "BrokenLamp"]
             if re.search(r'\[node name="%s" parent="Environment/Alley' % n, sng)]
    check(not stale, "la cancion no tiene overrides de nodos fusionados (%s)" % ", ".join(stale))

    print("")
    if failures:
        print("%d FALLO(s)" % len(failures))
        return 1
    print("todo OK - el fondo fusionado cuadra con su receta y con las dos escenas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
