#!/usr/bin/env python3
"""Which images on disk can nothing in the project still reach?

Written to answer one question honestly: when a cutscene was replaced by a
video, did its sprites leave with it, or are they still riding along in the
APK?

It is a REPORT, not a broom. It deletes nothing. The reason it errs so hard
towards "still referenced" is that a false orphan here means deleting art that
some scene loads by name at runtime, and that failure only shows up when a
player reaches that scene.

AND UNREACHED IS NOT THE SAME AS UNUSED. This tool answers "can anything load
this?" - it does not and cannot answer "should this exist?". The case that
proved it: the art behind Safety Lullaby's intro and Chimera's prelude comes out
of here as unreachable, correctly, because all four quality presets ask for the
pre-rendered video and nothing draws the live scene any more. Deleting it on
that basis was still wrong, and CI caught it - test_cutscene_assets_kept.gd
holds the reason. That art is the only master the .ogv can ever be re-rendered
from: render_cutscene.gd films the live scene by turning prefer_cutscene_video
off, so with no live scene there is nothing to film, and the cutscene is frozen
at whatever was last encoded. The .ogv is output, not a negative.

So before deleting anything this lists, read test_cutscene_assets_kept.gd, and
ask what the file is the SOURCE of - not just who loads it.

Reachability is measured several ways at once, and a file survives if ANY of
them holds:

  * transitive walk. From every .tscn and .tres that is not itself inside an
    assets folder, follow every ext_resource path (and every uid, resolved
    through the project's uid map) as far as it goes. This is what proves that
    an atlas .tres nobody loads any more does not keep its sheets alive. The
    walk goes THROUGH binary .res/.scn too, decoding them - see below.
  * literal mention. Any res:// path spelled out in a .gd, .cfg or .json. Code
    that builds a path with load("res://.../%s.png" % name) is caught by the
    prefix check below instead.
  * folder in code. If a script mentions a DIRECTORY, everything under it is
    treated as reachable, because that is what dynamic loading looks like.
  * folder of a model. A .gltf names its textures by bare filename inside its
    own JSON, never as a res:// path, so anything sharing a directory with a
    reachable model counts as reachable too.
  * Adobe Animate atlases. spritemap1.png is named by spritemap1.json beside an
    Animation.json, never by a res:// path.
  * binary resources. A .res is not text and this project's are `RSCC` -
    zstd-compressed - so neither grep nor `strings` gets anything out of one.
    Stopping there was the most expensive blind spot this report had: the mod's
    .res files resolve BY PATH, and those paths point at res://assets/, the PC
    pck's root. Without decoding them, 86 of the 89 MB under assets/ came out as
    unreachable when they are exactly what the game loads.

Every one of those rules was added because the report was WRONG without it,
and each time the error pointed the same way - towards calling live art dead.
It was validated by planting a file nothing references and checking it shows
up; the first two versions did not catch it, because a bare "res://" written
somewhere in the code declared the whole project reachable as a prefix.

Usage:
    python3 tools/orphan_report.py                # everything
    python3 tools/orphan_report.py <dir> [<dir>]  # only under these
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEXT_RES = (".tscn", ".tres")
## Los binarios de Godot. Se atraviesan igual que los de texto, decodificandolos
## - ver read_binary_res.py y la nota de `descend` mas abajo.
BIN_RES = (".res", ".scn")
# Sin .import: cada .png trae uno que nombra su propio source_file, asi que
# incluirlos hacia que TODA imagen se declarase a si misma como usada y el
# informe saliera en cero. Un .import no es nadie que alcance nada.
CODE = (".gd", ".cfg", ".json", ".godot")
# Lo que se cuenta como "arte": lo que pesa y lo que se borraria.
LEAF = (".png", ".jpg", ".jpeg", ".webp", ".ogg", ".mp3", ".wav", ".ogv",
        ".svg", ".ttf", ".glb", ".fbx", ".obj")

SKIP_DIRS = {".git", ".godot", "reference", "tools", "precompiled_astc_imports",
             "precompiled_texture_imports", "precompiled_lightmap_imports"}


def binary_payload(path):
    """El contenido de un .res/.scn, descomprimido si es `RSCC`."""
    from read_binary_res import payload
    return payload(path)


def walk_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            yield os.path.join(dirpath, f)


def rel(p):
    return "res://" + os.path.relpath(p, ROOT).replace(os.sep, "/")


def main():
    args = sys.argv[1:]
    # Con `--con-recursos` tambien se listan los .tres y .tscn que nadie alcanza,
    # ni los .res, .json y .xml que los acompañan. Hace falta para vaciar una
    # carpeta entera: un SpriteFrames
    # huerfano sigue "referenciando" sus PNG, asi que si se borran las imagenes y
    # se deja el .tres, lo que queda es un recurso roto en vez de una carpeta
    # limpia. Fuera de ese caso estorba, porque casi todo .tres vive colgado de
    # una escena y la lista se llena de ruido.
    global LEAF
    if "--con-recursos" in args:
        args.remove("--con-recursos")
        LEAF = LEAF + (".tres", ".tscn", ".res", ".scn", ".json", ".xml")
    only = [a.rstrip("/") for a in args]

    all_files = list(walk_files())
    on_disk = {rel(p): p for p in all_files}

    # --- uid -> ruta, leido de las cabeceras y de los .import.
    uid_map = {}
    for p in all_files:
        ext = os.path.splitext(p)[1].lower()
        if ext in TEXT_RES:
            head = open(p, encoding="utf-8", errors="replace").read(400)
            m = re.search(r'^\[gd_(?:scene|resource)[^\]]*uid="([^"]+)"', head, re.M)
            if m:
                uid_map[m.group(1)] = rel(p)
        elif ext == ".import":
            txt = open(p, encoding="utf-8", errors="replace").read()
            m = re.search(r'^uid="([^"]+)"', txt, re.M)
            src = re.search(r'^source_file="([^"]+)"', txt, re.M)
            if m and src:
                uid_map[m.group(1)] = src.group(1)

    def resolve(token):
        if token.startswith("uid://"):
            return uid_map.get(token)
        if token.startswith("res://"):
            return token
        return None

    # --- 1. camino transitivo desde las escenas y recursos que no son arte.
    def is_asset_side(r):
        return "/assets/" in r or r.startswith("res://assets/")

    roots = [r for r, p in on_disk.items()
             if os.path.splitext(r)[1].lower() in TEXT_RES and not is_asset_side(r)]

    reached = set()
    stack = list(roots)
    while stack:
        cur = stack.pop()
        if cur in reached:
            continue
        reached.add(cur)
        p = on_disk.get(cur)
        if p is None:
            continue
        ext = os.path.splitext(cur)[1].lower()
        if ext in TEXT_RES:
            text = open(p, encoding="utf-8", errors="replace").read()
            found = re.findall(r'"((?:res|uid)://[^"]+)"', text)
        elif ext in BIN_RES:
            # Un .res es un recurso BINARIO, y los de este proyecto son `RSCC`
            # -comprimidos con zstd- asi que ni un grep ni `strings` sacan nada
            # de ellos. Pararse aqui era el punto ciego mas caro del informe: los
            # .res del mod resuelven POR RUTA -no guardan uid, se comprobo
            # decodificando el uid de las texturas y buscandolo en el binario- y
            # esas rutas apuntan a res://assets/, la raiz del pck de PC. Sin
            # leerlos, 86 de los 89 MB de assets/ salian como inalcanzables
            # cuando en realidad son justo lo que el juego carga.
            try:
                found = [m.decode("ascii", "replace")
                         for m in re.findall(rb'(?:res|uid)://[\x20-\x7e]+',
                                             binary_payload(p))]
            except Exception as e:
                print("  aviso: no se pudo leer %s (%s)" % (cur, e), file=sys.stderr)
                found = []
        else:
            continue
        for tok in found:
            nxt = resolve(tok)
            if nxt and nxt not in reached:
                stack.append(nxt)

    # --- 2 y 3. lo que el codigo nombra, por fichero y por carpeta.
    named = set()
    named_dirs = set()
    for p in all_files:
        if os.path.splitext(p)[1].lower() not in CODE:
            continue
        text = open(p, encoding="utf-8", errors="replace").read()
        for tok in re.findall(r'(?:res|uid)://[^"\'\s\)\]]+', text):
            r = resolve(tok.rstrip(",;"))
            if not r:
                continue
            if os.path.splitext(r)[1]:
                named.add(r)
                continue
            # Un token sin extension SOLO cuenta como carpeta si es una carpeta
            # de verdad. Sin esta comprobacion el informe salia en cero: hay
            # codigo que escribe la cadena "res://" a secas, y como prefijo eso
            # declara alcanzable el proyecto entero. Tambien aparecian
            # `res://.../`, `res://,/` y `res://./`, restos de comentarios y de
            # concatenaciones.
            d = r.rstrip("/")
            if d in ("res:/", "res://") or "/" not in d[len("res://"):]:
                continue
            if os.path.isdir(os.path.join(ROOT, d[len("res://"):])):
                named_dirs.add(d + "/")

    # --- 4. lo que cuelga de un modelo 3D.
    #
    # Un .gltf nombra sus texturas por NOMBRE DE FICHERO dentro de su JSON
    # -"uri": "mdl_shop_base_wood.png"- y un .glb las lleva dentro o al lado,
    # asi que ninguna aparece nunca como una ruta res://. Sin esto el informe
    # acusaba de muertas a todas las texturas de la tienda y de la casa de
    # Chimera, que es justo el tipo de falso positivo que haria borrar arte que
    # si se usa. La regla es deliberadamente ancha: si en una carpeta hay un
    # modelo al que se llega, todo lo que hay en ella y por debajo cuenta como
    # alcanzable. Es coarse, y ese es el punto - un informe de borrado tiene que
    # equivocarse hacia "no lo toques".
    model_dirs = set()
    for r, p in on_disk.items():
        if os.path.splitext(r)[1].lower() not in (".gltf", ".glb", ".fbx", ".obj", ".blend"):
            continue
        if r in reached or r in named:
            model_dirs.add(r.rsplit("/", 1)[0] + "/")

    # --- 5. los atlas de Adobe Animate.
    #
    # `spritemap1.png` lo nombra `spritemap1.json`, que a su vez cuelga de un
    # `Animation.json` en la misma carpeta, y ninguno de los dos escribe una ruta
    # res://. Sin esto el informe acusaba de muertos a los 3.67 MB de
    # `characters/hypno_world` y a los 2.66 MB de `characters/gf`, que son la
    # animacion de hipnosis de GF: arte muy vivo.
    def animate_atlas(r):
        base = r.rsplit("/", 1)
        if len(base) != 2:
            return False
        folder, name = base
        stem = name.rsplit(".", 1)[0]
        return (folder + "/" + stem + ".json") in on_disk \
            and (folder + "/Animation.json") in on_disk

    def code_reaches(r):
        if r in named:
            return True
        if any(r.startswith(d) for d in named_dirs):
            return True
        if any(r.startswith(d) for d in model_dirs):
            return True
        return animate_atlas(r)

    # --- el veredicto, solo sobre hojas de arte.
    rows = []
    for r, p in sorted(on_disk.items()):
        if os.path.splitext(r)[1].lower() not in LEAF:
            continue
        sub = r[len("res://"):]
        if only and not any(sub.startswith(o) for o in only):
            continue
        if r in reached or code_reaches(r):
            continue
        # Una imagen a la que solo llega su .import no cuenta como usada.
        rows.append((os.path.getsize(p), r))

    rows.sort(reverse=True)
    total = sum(s for s, _ in rows)
    for size, r in rows:
        print("%10.2f MB  %s" % (size / 1048576.0, r))
    print("\n%d ficheros sin nadie que los alcance, %.1f MB"
          % (len(rows), total / 1048576.0))
    print("NO es una lista para borrar: inalcanzable no es lo mismo que sin usar.")
    print("Antes de tocar nada, lee tools/test_cutscene_assets_kept.gd.")


if __name__ == "__main__":
    main()
