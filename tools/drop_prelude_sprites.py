#!/usr/bin/env python3
"""Removes the three photo cards Chimera's prelude video already draws.

The decision this implements was made deliberately: freeze the cutscene. The
.ogv becomes the only copy, so `prelude` can never be re-rendered from the live
scene again. That is the cost, and it was accepted in exchange for the space.

What goes: `Prelude/1`, `Prelude/2` and `Prelude/3`, three Sprite2D and their
5.5 MB of texture. They are touched by exactly two animations - `prelude`, whose
whole 16.5s the video covers, and a length-0.001 RESET - so nothing outside the
video's window can see them.

WHAT STAYS, and this is the point of doing it by hand rather than deleting the
Prelude node:

  * `Prelude/Black`. It looks like prelude scenery and is not. `113_reaching`
    animates its `modulate` through an eight-key fade, and 113 is far past the
    video's 34.708s window, so it is live gameplay furniture that happens to
    live under this parent. Deleting the parent would have taken it, and the
    symptom would have been a fade that silently stops resolving - the exact
    failure test_cutscene_assets_kept.gd was written about.
  * `Prelude` itself, as the parent of Black.
  * `Intro`, all eighteen nodes. `intro` and `taking_a_looksie` drive it, and
    whether `taking_a_looksie` falls inside the video window could not be
    established without running the game. Unverified is not the same as safe.

One thing this loses on purpose, recorded because it is not visible in a diff:
if those three cards carry the translatable photo-session text, that text is now
whatever language the .ogv was rendered in. That was already true before this
change - the video has covered them since 2107018 - but deleting the sprites is
what makes it permanent.

Usage:
    python3 tools/drop_prelude_sprites.py [--dry-run]
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SONG = "lullaby_mod/songs/chimera/sng_chimera.tscn"

## Los nodos que se van, por su ruta bajo la raiz de la cancion.
DEAD_NODES = ["Prelude/1", "Prelude/2", "Prelude/3"]
## Y lo que NO se toca aunque cuelgue del mismo padre.
KEEP = "Prelude/Black"

DEAD_TRACK = re.compile(r'NodePath\("\.\./Prelude/[123][:/"]')


def split_tracks(block):
    """`block` partido en (cabecera, [pista, ...]).

    Las claves de una pista son un bloque MULTILINEA - `tracks/N/keys = {` y
    luego "times"/"values" hasta un `}` suelto - y esas lineas de dentro no
    empiezan por `tracks/N/`. Agrupar solo por prefijo las escupe fuera de su
    pista y deja el .tscn malformado.
    """
    head, groups, order = [], {}, []
    cur, in_keys = None, False
    for line in block.split("\n"):
        m = re.match(r'tracks/(\d+)/', line)
        if m:
            cur = int(m.group(1))
            if cur not in groups:
                groups[cur] = []
                order.append(cur)
            groups[cur].append(line)
            in_keys = line.rstrip().endswith("{")
            continue
        if in_keys and cur is not None:
            groups[cur].append(line)
            if line.strip() == "}":
                in_keys = False
            continue
        head.append(line)
    return head, [groups[i] for i in order]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    path = os.path.join(ROOT, SONG)
    text = open(path, encoding="utf-8").read()

    # `[^\]]*` y no `\]` a secas: la linea del nodo lleva `unique_id=...` antes
    # de cerrar, asi que exigir el corchete pegado daba "ya retirados" sobre una
    # escena intacta y el script se iba sin hacer nada ni fallar.
    if not re.search(r'(?m)^\[node name="1" type="Sprite2D" parent="Prelude"[^\]]*\]', text):
        print("ya retirados")
        return

    # --- los nodos.
    dropped_ids = set()
    for name in DEAD_NODES:
        leaf = name.split("/")[-1]
        m = re.search(r'(?m)^\[node name="%s" type="Sprite2D" parent="Prelude"[^\]]*\]\n'
                      % re.escape(leaf), text)
        if m is None:
            sys.exit("no encuentro el nodo %s" % name)
        nxt = text.find("\n[node ", m.end())
        end = nxt + 1 if nxt > 0 else len(text)
        dropped_ids |= set(re.findall(r'ExtResource\("([^"]+)"\)', text[m.start():end]))
        text = text[:m.start()] + text[end:]

    # --- las pistas que los movian, animacion por animacion, renumerando.
    dropped_tracks = 0
    out, at = [], 0
    for anim in re.finditer(r'(?m)^\[sub_resource type="Animation" id="[^"]+"\]\n', text):
        stop = text.find("\n[", anim.end())
        stop = stop + 1 if stop > 0 else len(text)
        body = text[anim.end():stop]
        if not DEAD_TRACK.search(body):
            continue

        head, tracks = split_tracks(body)
        keep = [t for t in tracks if not DEAD_TRACK.search("\n".join(t))]
        dropped_tracks += len(tracks) - len(keep)

        # Las lineas en blanco finales son del bloque y tienen que quedarse al
        # final; split_tracks las deja en `head` y volver a unir sin sacarlas
        # pega la cabecera siguiente a la ultima pista.
        tail = 0
        while head and head[-1].strip() == "":
            head.pop()
            tail += 1

        lines = list(head)
        for i, tr in enumerate(keep):
            for l in tr:
                lines.append(re.sub(r'^tracks/\d+/', 'tracks/%d/' % i, l))
        lines += [""] * tail

        out.append(text[at:anim.end()])
        out.append("\n".join(lines))
        at = stop
    out.append(text[at:])
    text = "".join(out)

    # --- y los ext_resource que ya no menciona nadie.
    pruned = 0
    for rid in sorted(dropped_ids):
        if re.search(r'ExtResource\("%s"\)' % re.escape(rid), text):
            continue
        m = re.search(r'(?m)^\[ext_resource[^\]]*id="%s"\]\n' % re.escape(rid), text)
        if m:
            text = text[:m.start()] + text[m.end():]
            pruned += 1

    # --- y las comprobaciones que impiden pasarse de largo.
    if KEEP.split("/")[-1] not in text:
        sys.exit("se ha llevado %s por delante" % KEEP)
    if not re.search(r'(?m)^\[node name="Prelude" type="Node2D"', text):
        sys.exit("se ha llevado el nodo Prelude por delante")
    left = len(DEAD_TRACK.findall(text))
    if left:
        sys.exit("quedan %d pistas apuntando a los sprites borrados" % left)

    print("fuera: %d nodos, %d pistas, %d ext_resource"
          % (len(DEAD_NODES), dropped_tracks, pruned))
    if args.dry_run:
        return
    open(path, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()
