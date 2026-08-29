#!/usr/bin/env python3
"""Swaps a Chimera death step's sprite animation for its baked .ogv.

Run tools/render_gameover_video.py first; this wires up what that produced.

What changes in step_N.tscn:

  * the AnimatedSprite2D and its child AnimationPlayer are replaced by ONE
    VideoStreamPlayer, in the same place in the child order. That placement is
    the whole ballgame: StepImage is the next sibling, and 2D siblings draw in
    order, so the title card has to keep covering the video exactly the way it
    covered the sprite. Put the video after StepImage and the card vanishes
    behind the death animation.
  * the two tracks that drove the sprite go: `AnimatedSprite2D:visible` and the
    TYPE_ANIMATION track that fired the 13-frame cycle. The clip carries its own
    black head and tail, so it needs neither.
  * the SpriteFrames and AnimationLibrary ext_resources go, and a VideoStream
    one arrives.
  * the root gains `video_player`, which chimera_gameover.gd starts in the SAME
    call that starts the animation - so the two cannot drift. That is why the
    clip runs the full length of the scene rather than just the animated
    window: 7 seconds of black cost 30 KB, and buying sync for 30 KB is a good
    trade against threading a start time through the scene and the script.

Track indices are renumbered after a removal. Godot writes them as
tracks/0..N-1 and a gap is not something to find out about at runtime.

Usage:
    python3 tools/wire_gameover_video.py 1 2 3
    python3 tools/wire_gameover_video.py 1 --dry-run
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = "lullaby_mod/songs/chimera/scenes"
GAMEOVER = "lullaby_mod/assets/funkin/chimera/gameover"

## The node the sprite is replaced by. Named for what it is; the step_4 scene
## already has a `VideoPlayer`, so the name is consistent with the one death
## that always used video.
VIDEO_NODE = "VideoPlayer"


def blocks(text):
    """(start, end, header) for every [node ...] block."""
    heads = list(re.finditer(r'(?m)^\[node .*?\]', text))
    out = []
    for i, h in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        out.append((h.start(), end, h.group(0)))
    return out


def drop_tracks(body, unwanted):
    """Removes every track whose path matches `unwanted`, then renumbers."""
    groups = {}
    order = []
    other = []
    for line in body.split("\n"):
        m = re.match(r'tracks/(\d+)/', line)
        if not m:
            other.append((len(order), line))
            continue
        idx = int(m.group(1))
        if idx not in groups:
            groups[idx] = []
            order.append(idx)
        groups[idx].append(line)

    keep = []
    for idx in order:
        lines = groups[idx]
        path = next((l for l in lines if "/path = " in l), "")
        if unwanted.search(path):
            continue
        keep.append(lines)

    # Rebuild: the non-track lines keep their relative position, the tracks are
    # renumbered into a contiguous run.
    out = []
    emitted = False
    for pos, line in other:
        if not emitted and pos > 0 and keep:
            for new_idx, lines in enumerate(keep):
                for l in lines:
                    out.append(re.sub(r'^tracks/\d+/', 'tracks/%d/' % new_idx, l))
            emitted = True
        out.append(line)
    if not emitted:
        for new_idx, lines in enumerate(keep):
            for l in lines:
                out.append(re.sub(r'^tracks/\d+/', 'tracks/%d/' % new_idx, l))
    return "\n".join(out), len(order) - len(keep)


def prune_sub_resources(text):
    """Drops every sub_resource no node can reach.

    Quitar el AnimationPlayer del sprite deja su AnimationLibrary sin nadie que
    la use, y esa libreria a su vez sujeta un Animation cuyas pistas apuntan a
    un nodo que ya no existe. Godot lo carga sin quejarse y no se ve, pero es
    peso muerto que apunta a la nada.

    Por alcanzabilidad y no por "no aparece en ningun sitio": la libreria SI
    aparece - dentro de si misma y en el Animation que cuelga de ella - asi que
    un conteo de menciones la daria por viva. Las raices son las referencias
    desde los bloques [node].
    """
    spans = {}
    for m in re.finditer(r'(?m)^\[sub_resource type="[^"]+" id="([^"]+)"\]\n', text):
        nxt = text.find("\n[", m.end())
        nxt = nxt + 1 if nxt > 0 else len(text)
        spans[m.group(1)] = (m.start(), nxt, text[m.end():nxt])

    node_at = min([b[0] for b in blocks(text)] or [len(text)])
    alive = set(re.findall(r'SubResource\("([^"]+)"\)', text[node_at:]))

    frontier = list(alive)
    while frontier:
        sid = frontier.pop()
        if sid not in spans:
            continue
        for ref in re.findall(r'SubResource\("([^"]+)"\)', spans[sid][2]):
            if ref not in alive:
                alive.add(ref)
                frontier.append(ref)

    dead = [sid for sid in spans if sid not in alive]
    for sid in sorted(dead, key=lambda s: -spans[s][0]):
        start, end, _ = spans[sid]
        text = text[:start] + text[end:]
    return text, len(dead)


def rewire(step, dry_run):
    path = os.path.join(ROOT, SCENES, "step_%d.tscn" % step)
    text = open(path, encoding="utf-8").read()
    ogv = "res://%s/step_%d/death_%d.ogv" % (GAMEOVER, step, step)

    if not os.path.exists(os.path.join(ROOT, ogv.replace("res://", ""))):
        sys.exit("falta %s - corre render_gameover_video.py primero" % ogv)
    if VIDEO_NODE in text:
        print("step_%d: ya reconectado" % step)
        return

    # --- ext_resources: fuera SpriteFrames y AnimationLibrary, dentro el video.
    doomed = []
    for m in re.finditer(r'(?m)^\[ext_resource type="(SpriteFrames|AnimationLibrary)"'
                         r'[^\]]*id="([^"]+)"\]\n', text):
        doomed.append(m.group(2))
        text = text.replace(m.group(0), "")

    vid_id = "%d_video" % step
    last = list(re.finditer(r'(?m)^\[ext_resource .*\]\n', text))[-1]
    text = (text[:last.end()]
            + '[ext_resource type="VideoStream" path="%s" id="%s"]\n' % (ogv, vid_id)
            + text[last.end():])

    # --- el nodo del sprite y su AnimationPlayer hijo -> un VideoStreamPlayer.
    spans = []
    header = None
    for start, end, head in blocks(text):
        if 'name="AnimatedSprite2D"' in head and 'parent="."' in head:
            spans.append((start, end))
            header = head
        elif 'parent="AnimatedSprite2D"' in head:
            spans.append((start, end))
    if not spans:
        sys.exit("step_%d: no encuentro el AnimatedSprite2D" % step)

    uid = re.search(r'unique_id=(\d+)', header)
    node = ('[node name="%s" type="VideoStreamPlayer" parent="."%s]\n'
            'layout_mode = 1\n'
            'anchors_preset = 15\n'
            'anchor_right = 1.0\n'
            'anchor_bottom = 1.0\n'
            'grow_horizontal = 2\n'
            'grow_vertical = 2\n'
            'mouse_filter = 2\n'
            'stream = ExtResource("%s")\n'
            'expand = true\n\n' % (
                VIDEO_NODE,
                " unique_id=%s" % uid.group(1) if uid else "",
                vid_id))

    spans.sort()
    text = text[:spans[0][0]] + node + text[spans[-1][1]:]

    # --- las pistas que conducian al sprite.
    unwanted = re.compile(r'AnimatedSprite2D')
    removed = 0
    out = []
    pos = 0
    for m in re.finditer(r'(?m)^\[sub_resource type="Animation" [^\]]*\]\n', text):
        nxt = text.find("\n[", m.end())
        nxt = nxt + 1 if nxt > 0 else len(text)
        body, n = drop_tracks(text[m.end():nxt], unwanted)
        removed += n
        out.append(text[pos:m.end()])
        out.append(body)
        pos = nxt
    out.append(text[pos:])
    text = "".join(out)

    # --- y el enlace desde la raiz, DESPUES de script= o se pierde en silencio.
    m = re.search(r'(?m)^script = ExtResource\("[^"]+"\)\n', text)
    text = text[:m.end()] + 'video_player = NodePath("%s")\n' % VIDEO_NODE + text[m.end():]

    node_paths = re.search(r'(\[node name="Step%d"[^\]]*node_paths=PackedStringArray\()'
                           r'([^)]*)\)' % step, text)
    if node_paths and "video_player" not in node_paths.group(2):
        text = text.replace(node_paths.group(0),
                            node_paths.group(1) + node_paths.group(2)
                            + ', "video_player")')

    text, orphans = prune_sub_resources(text)

    print("step_%d: %d ext_resource fuera, %d pistas fuera, %d sub_resource "
          "huerfanos fuera, %s puesto" % (
              step, len(doomed), removed, orphans, VIDEO_NODE))
    if dry_run:
        return
    open(path, "w", encoding="utf-8").write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("steps", type=int, nargs="+", choices=[1, 2, 3])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    for s in args.steps:
        rewire(s, args.dry_run)


if __name__ == "__main__":
    main()
