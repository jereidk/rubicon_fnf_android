#!/usr/bin/env python3
"""Swaps Monochrome's MonoCloseup cutscene for its rendered .ogv.

Measured before it was chosen, against the real chart: the cutscene runs
266.5-294.6s and the song has 800 player notes, NONE of them inside that
window. It is a 28.8-second interlude nobody can affect - which is the test
that also ruled out the BloodCutscene next door, where 45 player notes land
inside its 12.2 seconds and the characters carry `singing_should_sing`.

cut_mono_closeup.tscn pulls 44.5 MB of texture across ~35 nodes to draw it.
The clip is 6.0 MB.

The scene keeps exactly three things, and each for a reason:

  * the root, `MonoCloseup`, with its name, type and 1.7778 ratio. The song
    reaches into this scene by NodePath - `../MonoCloseup/Cutscene` - so
    renaming or retyping the root breaks the trigger from the outside.
  * `Cutscene`, the AnimationPlayer the song fires. The song's track names the
    clip `cutscene`, so that animation has to keep existing under that name.
  * `AudioStreamPlayer`, and the disabled audio track that points at it. That
    track is `enabled = false` in the original, so it plays nothing and costs
    nothing - the sound during this cutscene comes from the song. It is kept
    verbatim rather than pruned because it records which stream the authors
    meant and at what offset, and deleting a disabled track throws that away
    for no gain.

Everything else the animation drove was visual: eleven clips fired at
`Sequences` and one `[stop]` at the vultures. Those two tracks go, and so do
the node subtrees they drove.

The video is started by a METHOD track calling play() at t=0 of the same
animation the song fires, so there is no start time written anywhere and no
second thing to keep in sync. That a method key at exactly 0.0 does fire on
play() was checked against this engine rather than assumed - it runs once.

Usage:
    python3 tools/wire_closeup_video.py
    python3 tools/wire_closeup_video.py --dry-run
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENE = "lullaby_mod/resources/funkin/songs/monochrome/cutscene/cut_mono_closeup.tscn"
OGV = "res://lullaby_mod/songs/monochrome/video/closeup.ogv"

## Los unicos nodos que sobreviven, y por que en el docstring de arriba.
KEEP = {"MonoCloseup", "AudioStreamPlayer", "Cutscene"}
VIDEO_NODE = "VideoPlayer"


def node_blocks(text):
    heads = list(re.finditer(r'(?m)^\[node .*?\]', text))
    out = []
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        name = re.search(r'name="([^"]+)"', h.group(0)).group(1)
        parent = re.search(r'parent="([^"]+)"', h.group(0))
        out.append((h.start(), end, name, parent.group(1) if parent else None))
    return out


def prune_refs(text):
    """Drops sub_resources and ext_resources no node can reach."""
    dropped = 0
    for _ in range(8):  # a fixpoint; the graph here is two levels deep at most
        node_at = min([b[0] for b in node_blocks(text)] or [len(text)])
        body = text[node_at:]

        spans = {}
        for m in re.finditer(r'(?m)^\[sub_resource type="[^"]+" id="([^"]+)"\]\n', text):
            nxt = text.find("\n[", m.end())
            nxt = nxt + 1 if nxt > 0 else len(text)
            spans[m.group(1)] = (m.start(), nxt, text[m.end():nxt])

        alive = set(re.findall(r'SubResource\("([^"]+)"\)', body))
        frontier = list(alive)
        while frontier:
            sid = frontier.pop()
            if sid not in spans:
                continue
            for ref in re.findall(r'SubResource\("([^"]+)"\)', spans[sid][2]):
                if ref not in alive:
                    alive.add(ref)
                    frontier.append(ref)

        dead = [s for s in spans if s not in alive]
        for sid in sorted(dead, key=lambda s: -spans[sid][0] if False else -spans[s][0]):
            a, b, _ = spans[sid]
            text = text[:a] + text[b:]
        dropped += len(dead)

        # Y los ext_resource que ya no menciona nadie.
        ext_dead = []
        for m in list(re.finditer(r'(?m)^\[ext_resource[^\]]*id="([^"]+)"\]\n', text)):
            rid = m.group(1)
            uses = len(re.findall(r'ExtResource\("%s"\)' % re.escape(rid), text))
            if uses == 0:
                ext_dead.append(m.group(0))
        for line in ext_dead:
            text = text.replace(line, "")
        dropped += len(ext_dead)

        if not dead and not ext_dead:
            break
    return text, dropped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    path = os.path.join(ROOT, SCENE)
    text = open(path, encoding="utf-8").read()

    if not os.path.exists(os.path.join(ROOT, OGV.replace("res://", ""))):
        sys.exit("falta %s - renderiza la cutscene primero" % OGV)
    if VIDEO_NODE in text:
        print("ya reconectado")
        return

    before_nodes = len(node_blocks(text))

    # --- fuera todo nodo que no este en KEEP.
    kept = []
    for start, end, name, parent in node_blocks(text):
        if name in KEEP and (parent in (None, ".")):
            kept.append((start, end))
    if len(kept) != len(KEEP):
        sys.exit("esperaba %d nodos que conservar, encontre %d" % (len(KEEP), len(kept)))

    first = min(s for s, _ in kept)
    head = text[:first]
    body = "".join(text[s:e] for s, e in sorted(kept))

    # --- el video, entre el audio y el reproductor que lo arranca.
    video = ('[node name="%s" type="VideoStreamPlayer" parent="."]\n'
             'layout_mode = 1\n'
             'anchors_preset = 15\n'
             'anchor_right = 1.0\n'
             'anchor_bottom = 1.0\n'
             'grow_horizontal = 2\n'
             'grow_vertical = 2\n'
             'mouse_filter = 2\n'
             'stream = ExtResource("video")\n'
             'expand = true\n\n' % VIDEO_NODE)
    text = head + body.rstrip("\n") + "\n\n" + video

    # --- el ext_resource del video.
    last = list(re.finditer(r'(?m)^\[ext_resource .*\]\n', text))[-1]
    text = (text[:last.end()]
            + '[ext_resource type="VideoStream" path="%s" id="video"]\n' % OGV
            + text[last.end():])

    # --- la animacion: fuera lo visual, dentro la llamada a play().
    i = text.find('resource_name = "cutscene"')
    end = text.find("\n[", i)
    end = end + 1 if end > 0 else len(text)
    anim = text[i:end]

    # Las claves de una pista son un bloque MULTILINEA - `tracks/N/keys = {`
    # y luego "clips"/"times"/"values" hasta un `}` suelto - y esas lineas de
    # dentro no empiezan por `tracks/N/`. La primera version las trato como
    # lineas sueltas y las escupio fuera de su pista, dejando el .tscn
    # malformado. Asi que se sigue en que bloque se esta.
    groups, order = {}, []
    other = []
    cur = None
    in_keys = False
    for line in anim.split("\n"):
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
        other.append(line)

    keep_tracks = [groups[i] for i in order
                   if not any('/type = "animation"' in l for l in groups[i])]
    dropped_tracks = len(order) - len(keep_tracks)

    lines = list(other)
    for new_idx, tr in enumerate(keep_tracks):
        for l in tr:
            lines.append(re.sub(r'^tracks/\d+/', 'tracks/%d/' % new_idx, l))

    lines += [
        'tracks/%d/type = "method"' % len(keep_tracks),
        'tracks/%d/imported = false' % len(keep_tracks),
        'tracks/%d/enabled = true' % len(keep_tracks),
        'tracks/%d/path = NodePath("%s")' % (len(keep_tracks), VIDEO_NODE),
        'tracks/%d/interp = 1' % len(keep_tracks),
        'tracks/%d/loop_wrap = true' % len(keep_tracks),
        'tracks/%d/keys = {' % len(keep_tracks),
        '"times": PackedFloat32Array(0),',
        '"transitions": PackedFloat32Array(1),',
        '"values": [{',
        '"args": [],',
        '"method": &"play"',
        '}]',
        '}',
        '',
    ]
    text = text[:i] + "\n".join(lines) + text[end:]

    text, pruned = prune_refs(text)

    print("nodos %d -> %d, %d pistas visuales fuera, %d recursos podados"
          % (before_nodes, len(node_blocks(text)), dropped_tracks, pruned))
    if args.dry_run:
        return
    open(path, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()
