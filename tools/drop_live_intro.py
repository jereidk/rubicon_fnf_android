#!/usr/bin/env python3
"""Removes Safety Lullaby's live intro cutscene, which nothing can reach.

The video was wired in ec9aee1 as an OVERLAY, not a replacement:
LullabyCutsceneVideo leaves the live scene in the tree and only disables its
process_mode. That was the cautious thing to do at the time, because
`prefer_cutscene_video` was off in Medium and High and the live scene was still
the path those presets took.

It is not off anywhere any more. All four quality presets set it to true, and
the flag is not exposed in the settings UI - `graphics_prefer_cutscene_video`
is written by LullabyQualityPreset and read by this one node, nothing else. So
there is no configuration a player can reach in which those 8.2 MB of sprites
are drawn. They are loaded, they take RAM, they ship in the APK, and the video
covers every frame they would have produced.

What comes out, and why each piece is safe:

  * the `IntroCutscene` instance and its ext_resource. Only sng_safety_lullaby
    references intro.tscn - checked by path AND by uid, since a scene can be
    reached either way.

  * `IntroCutscene:visible`, in three animations. Nothing else reads it.

  * `IntroCutscene/Scene/Camera2D:enabled`, in RESET and in `play`. This is the
    one that needed checking rather than assuming, because deleting a camera
    normally changes what you see. It does not here: the gameplay camera is
    `enabled = false` at 0 and `true` at 31.533333, exactly where the intro
    camera switches off, so with the intro camera gone NO 2D camera is enabled
    during the intro at all. That is fine, because everything visible in that
    window is the video, and a VideoStreamPlayer inside a CanvasLayer is not
    transformed by a Camera2D. `Environment:visible` is false until 31.533333
    anyway, so there is nothing behind it to frame.

  * the TYPE_ANIMATION track firing `cutscene` on `IntroCutscene/Timeline`.
    That is what STARTED the live cutscene. The video does not depend on it:
    LullabyCutsceneVideo calls play() in its own _ready() and syncs against
    `../Clock/AnimationPlayer`, which is untouched.

The RESET at Animation_djtvt has exactly one track and it is one of these, so
it is left behind empty rather than deleted - an AnimationPlayer that names a
RESET which does not exist is a worse failure than an empty one.

Usage:
    python3 tools/drop_live_intro.py [--dry-run]
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SONG = "lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn"
LIVE = "res://lullaby_mod/songs/safety_lullaby/scenes/intro.tscn"

## Toda pista cuyo NodePath entre en la cutscene viva.
DEAD_TRACK = re.compile(r'NodePath\("\.{0,2}/?IntroCutscene[:/"]')


def split_tracks(block):
    """`block` partido en (cabecera, [pista, ...]).

    Las claves de una pista son un bloque MULTILINEA - `tracks/N/keys = {` y
    luego "times"/"values" hasta un `}` suelto - y esas lineas de dentro NO
    empiezan por `tracks/N/`. Agrupar solo por prefijo las escupe fuera de su
    pista y deja el .tscn malformado; ya paso dos veces esta sesion, en la
    cutscene de closeup y en step_4. Asi que se sigue en que bloque se esta.
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

    if "IntroCutscene" not in text:
        print("ya retirada")
        return

    # --- el ext_resource de la escena viva, y su id.
    m = re.search(r'(?m)^\[ext_resource[^\]]*path="%s"[^\]]*id="([^"]+)"\]\n'
                  % re.escape(LIVE), text)
    if m is None:
        sys.exit("no encuentro el ext_resource de %s" % LIVE)
    live_id = m.group(1)
    text = text[:m.start()] + text[m.end():]

    # --- el nodo. Va desde su cabecera hasta la siguiente.
    node = re.search(r'(?m)^\[node name="IntroCutscene"[^\]]*\]\n', text)
    if node is None:
        sys.exit("no encuentro el nodo IntroCutscene")
    nxt = text.find("\n[node ", node.end())
    end = nxt + 1 if nxt > 0 else len(text)
    text = text[:node.start()] + text[end:]

    if 'ExtResource("%s")' % live_id in text:
        sys.exit("el ext_resource %s sigue en uso tras quitar el nodo" % live_id)

    # --- las pistas, animacion por animacion, renumerando cada una.
    dropped = 0
    out, at = [], 0
    for anim in re.finditer(r'(?m)^\[sub_resource type="Animation" id="[^"]+"\]\n', text):
        stop = text.find("\n[", anim.end())
        stop = stop + 1 if stop > 0 else len(text)
        body = text[anim.end():stop]
        if not DEAD_TRACK.search(body):
            continue

        head, tracks = split_tracks(body)
        keep = [t for t in tracks if not DEAD_TRACK.search("\n".join(t))]
        dropped += len(tracks) - len(keep)

        # Las lineas en blanco del FINAL del bloque son suyas y tienen que
        # seguir al final. split_tracks las mete en `head` porque no empiezan
        # por `tracks/N/`, y volver a unir sin sacarlas las deja en medio: el
        # bloque acaba entonces en una linea de pista sin salto, y la cabecera
        # `[sub_resource]` siguiente se pega a ella. La primera version hizo
        # justo eso y fundio dos animaciones en una - 52 pistas seguidas de 60.
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

    # --- y el export que apuntaba a ella. El nodo del video se queda; solo
    # pierde el companero al que apagaba el process_mode.
    text = text.replace(
        ' node_paths=PackedStringArray("live_cutscene", "clock")',
        ' node_paths=PackedStringArray("clock")')
    text = re.sub(r'(?m)^live_cutscene = NodePath\("\.\./IntroCutscene"\)\n', "", text)

    left = len(DEAD_TRACK.findall(text)) + text.count('"IntroCutscene"')
    if left:
        sys.exit("quedan %d referencias a IntroCutscene" % left)

    print("fuera: 1 nodo, 1 ext_resource, %d pistas" % dropped)
    if args.dry_run:
        return
    open(path, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()
