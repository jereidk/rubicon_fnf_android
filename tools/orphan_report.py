#!/usr/bin/env python3
"""Which images on disk can nothing in the project still reach?

Written to answer one question honestly: when a cutscene was replaced by a
video, did its sprites leave with it, or are they still riding along in the
APK?

It is a REPORT, not a broom. It deletes nothing. The reason it errs so hard
towards "still referenced" is that a false orphan here means deleting art that
some scene loads by name at runtime, and that failure only shows up when a
player reaches that scene.

Reachability is measured three ways at once, and a file survives if ANY of
them holds:

  * transitive walk. From every .tscn and .tres that is not itself inside an
    assets folder, follow every ext_resource path (and every uid, resolved
    through the project's uid map) as far as it goes. This is what proves that
    an atlas .tres nobody loads any more does not keep its sheets alive.
  * literal mention. Any res:// path spelled out in a .gd, .cfg or .json. Code
    that builds a path with load("res://.../%s.png" % name) is caught by the
    prefix check below instead.
  * folder in code. If a script mentions a DIRECTORY, everything under it is
    treated as reachable, because that is what dynamic loading looks like.
  * folder of a model. A .gltf names its textures by bare filename inside its
    own JSON, never as a res:// path, so anything sharing a directory with a
    reachable model counts as reachable too.

Every one of those rules was added because the report was WRONG without it,
and each time the error pointed the same way - towards calling live art dead.
It was validated by planting a file nothing references and checking it shows
up; the first two versions did not catch it, because a bare "res://" written
somewhere in the code declared the whole project reachable as a prefix.

Usage:
    python3 tools/orphan_report.py                # everything
    python3 tools/orphan_report.py <dir> [<dir>]  # only under these
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEXT_RES = (".tscn", ".tres")
# Sin .import: cada .png trae uno que nombra su propio source_file, asi que
# incluirlos hacia que TODA imagen se declarase a si misma como usada y el
# informe saliera en cero. Un .import no es nadie que alcance nada.
CODE = (".gd", ".cfg", ".json", ".godot")
# Lo que se cuenta como "arte": lo que pesa y lo que se borraria.
LEAF = (".png", ".jpg", ".jpeg", ".webp", ".ogg", ".mp3", ".wav", ".ogv",
        ".svg", ".ttf", ".glb", ".fbx", ".obj")

SKIP_DIRS = {".git", ".godot", "reference", "tools", "precompiled_astc_imports",
             "precompiled_texture_imports", "precompiled_lightmap_imports"}


def walk_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            yield os.path.join(dirpath, f)


def rel(p):
    return "res://" + os.path.relpath(p, ROOT).replace(os.sep, "/")


def main():
    only = [a.rstrip("/") for a in sys.argv[1:]]

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
        if p is None or os.path.splitext(cur)[1].lower() not in TEXT_RES:
            continue
        text = open(p, encoding="utf-8", errors="replace").read()
        for tok in re.findall(r'"((?:res|uid)://[^"]+)"', text):
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

    def code_reaches(r):
        if r in named:
            return True
        if any(r.startswith(d) for d in named_dirs):
            return True
        return any(r.startswith(d) for d in model_dirs)

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


if __name__ == "__main__":
    main()
