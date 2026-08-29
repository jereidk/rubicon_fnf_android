#!/usr/bin/env python3
"""Bakes a Chimera death step into an .ogv, from the game's own assets.

Chimera's deaths cost 97 MB of PNG in the tree and 34 MB of ASTC on the
device, for five animations that never change and that nobody can interact
with. steps 1-3 are the clean cases: a black ColorRect, ONE AnimatedSprite2D
of 13 frames, a still image over the top, and a sound. Baking each into a
video drops the sprite sheets entirely - and with them their ASTC compression,
which is what made one CI import take 12m29s.

Why not a screen capture from YouTube, which is the obvious shortcut: we have
the originals. A capture is a lossy re-encode of a lossy stream, framed by
somebody else, at somebody else's timing, and quite possibly of a different
death - there are five and which one you see depends on how many times you
have died. Compositing from the atlas is both exact and faster.

Why not the engine's own render harness: it drives a RubiconLevelClock these
scenes do not have. They self-start off a one-shot Timer instead, so the
harness has nothing to seek. The timeline is small enough to read straight out
of the .tscn, which is what this does.

What it reproduces, from step_N.tscn rather than from memory:

  * the main AnimationPlayer's `StepImage:visible` and `AnimatedSprite2D:visible`
    value tracks, which is what decides who is on screen when;
  * its TYPE_ANIMATION track, whose keys fire the sub-clip on the sprite's own
    AnimationPlayer - three of them in step_1, at 6.21s, 7.42s and 8.42s, each
    restarting the 13-frame cycle from zero;
  * the draw order. StepImage is a LATER SIBLING than AnimatedSprite2D, so for
    the first 6.2 seconds the still image covers the sprite completely. Getting
    that backwards would put the animation on top of a picture it is supposed
    to be hidden behind.

Only the ANIMATED window is baked - from the first sub-clip key to the frame
the sprite is hidden - and not the whole scene. The first six seconds are a
still title card that is already a PNG, and that PNG is the worst thing a
video codec could be handed: thin white serif text on black, whose edges
Theora rings around visibly at 960x540. Rendered a second time into the clip
it would look worse than the file it came from, cost most of the bitrate, and
gain nothing. So the card stays a card and the video starts where the art
starts - which is dark, organic and almost free to encode.

Audio is deliberately NOT muxed. The scene keeps its AudioStreamPlayer, so
nothing is re-encoded and the existing autoplay wiring is untouched.

Delivery is 960x540 at 60fps, matching the two cutscenes this project already
ships (safety_lullaby/intro.ogv and chimera/prelude.ogv are both exactly that,
at ~850 kbps). That is a decode-cost decision, not a taste one: the project's
measured curve is ms = 1.32 + 3.49 x Mpx, so 0.494 Mpx costs ~3ms on desktop
and ~9ms on a weak phone at the 3x factor this project carries. A game over
has nothing else drawing, so it is comfortable - and 1280x720 would not be.

Usage:
    python3 tools/render_gameover_video.py 1
    python3 tools/render_gameover_video.py 1 --quality 8 --keep-frames
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

try:
    from PIL import Image
except ImportError:
    sys.exit("hace falta Pillow: pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = "lullaby_mod/songs/chimera/scenes"
GAMEOVER = "lullaby_mod/assets/funkin/chimera/gameover"

## The design space every position and scale in these scenes is written in.
DESIGN = (1920, 1080)
## Delivery size, and the reason for it is in the module docstring.
OUT = (960, 540)
FPS = 60


def res_path(p):
    return os.path.join(ROOT, p.replace("res://", ""))


def read(p):
    return open(res_path(p), encoding="utf-8", errors="replace").read()


def ext_resources(text):
    """id -> path, for every ext_resource in a .tscn/.tres."""
    return {m.group(2): m.group(1) for m in re.finditer(
        r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"\]', text)}


def sprite_frames(tres_path):
    """The animation's frames, in order, as cropped PIL images."""
    text = read(tres_path)
    ext = ext_resources(text)

    regions = {}
    for m in re.finditer(
            r'\[sub_resource type="AtlasTexture" id="([^"]+)"\](.*?)(?=\n\[|\Z)',
            text, re.S):
        body = m.group(2)
        atlas = re.search(r'atlas = ExtResource\("([^"]+)"\)', body).group(1)
        rect = [float(v) for v in
                re.search(r'region = Rect2\(([^)]+)\)', body).group(1).split(",")]
        regions[m.group(1)] = (ext[atlas], rect)

    # The order the animation plays them in, which is NOT the order the
    # sub_resources happen to be declared in.
    order = re.findall(r'"texture": SubResource\("([^"]+)"\)', text)

    sheets = {}
    frames = []
    for sid in order:
        path, (x, y, w, h) = regions[sid]
        if path not in sheets:
            sheets[path] = Image.open(res_path(path)).convert("RGBA")
        # The regions carry a fractional part; the whole-pixel box is what the
        # sheet actually stores, and it is what the engine samples from.
        box = (int(round(x)), int(round(y)),
               int(round(x + w)), int(round(y + h)))
        frames.append(sheets[path].crop(box))
    return frames


def timeline(step):
    """What is on screen when, read out of the step's own .tscn."""
    text = read(os.path.join(SCENES, "step_%d.tscn" % step))
    ext = ext_resources(text)

    body = text[text.find('resource_name = "animation"'):]
    end = body.find("\n[sub_resource")
    if end > 0:
        body = body[:end]

    out = {"length": float(re.search(r'length = ([\d.]+)', body).group(1))}

    for m in re.finditer(
            r'tracks/(\d+)/path = NodePath\("([^"]+)"\)[\s\S]*?'
            r'tracks/\1/keys = \{(.*?)\n\}', body, re.S):
        path, keys = m.group(2), m.group(3)
        times = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys)
        times = [float(v) for v in times.group(1).split(",")] if times else []
        vals = re.search(r'"values": \[([^\]]*)\]', keys)

        if path.endswith(":visible"):
            out[path] = list(zip(times, [
                v.strip() == "true" for v in vals.group(1).split(",")]))
        elif "AnimationPlayer" in path:
            out["clips"] = times

    # The sprite's transform, and the still image behind it.
    m = re.search(r'\[node name="AnimatedSprite2D"[^\]]*\](.*?)(?=\n\[node)',
                  text, re.S)
    pos = re.search(r'position = Vector2\(([^)]+)\)', m.group(1))
    scale = re.search(r'scale = Vector2\(([^)]+)\)', m.group(1))
    out["sprite_pos"] = [float(v) for v in pos.group(1).split(",")]
    out["sprite_scale"] = [float(v) for v in scale.group(1).split(",")]
    out["sprite_frames"] = ext[
        re.search(r'sprite_frames = ExtResource\("([^"]+)"\)', m.group(1)).group(1)]

    m = re.search(r'\[node name="StepImage"[^\]]*\](.*?)(?=\n\[node)', text, re.S)
    out["still"] = ext[
        re.search(r'texture = ExtResource\("([^"]+)"\)', m.group(1)).group(1)]
    sm = re.search(r'stretch_mode = (\d+)', m.group(1))
    # Leido de la escena y no fijado aqui, para que un step con otro encuadre
    # no salga mal en silencio.
    out["stretch"] = int(sm.group(1)) if sm else STRETCH_KEEP_ASPECT_CENTERED
    return out


def visible_at(track, t):
    """The last keyed value at or before t. update=1 on these tracks, so they
    step rather than interpolate."""
    state = False
    for time, value in track:
        if t + 1e-6 >= time:
            state = value
        else:
            break
    return state


## TextureRect.StretchMode, straight from the engine rather than from memory.
## The first version of this assumed 5 was KEEP_ASPECT_COVERED and cropped the
## still image; 5 is KEEP_ASPECT_CENTERED, which FITS it and letterboxes. The
## sample frame is what caught it - step_1's still is a title card, and COVERED
## was slicing the Japanese line off the bottom.
STRETCH_KEEP_ASPECT = 4
STRETCH_KEEP_ASPECT_CENTERED = 5
STRETCH_KEEP_ASPECT_COVERED = 6


def fit(img, size, mode):
    """Places `img` in a rect of `size` the way TextureRect would."""
    sw, sh = img.size
    if mode == STRETCH_KEEP_ASPECT_COVERED:
        scale = max(size[0] / sw, size[1] / sh)
    elif mode in (STRETCH_KEEP_ASPECT, STRETCH_KEEP_ASPECT_CENTERED):
        scale = min(size[0] / sw, size[1] / sh)
    else:
        # STRETCH_SCALE and anything else: fill the rect outright.
        return img.resize(size, Image.LANCZOS)

    scaled = img.resize((max(1, round(sw * scale)), max(1, round(sh * scale))),
                        Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(scaled, ((size[0] - scaled.width) // 2,
                                    (size[1] - scaled.height) // 2))
    if mode == STRETCH_KEEP_ASPECT_COVERED:
        left = (scaled.width - size[0]) // 2
        top = (scaled.height - size[1]) // 2
        return scaled.crop((left, top, left + size[0], top + size[1]))
    return canvas


def build(step, quality, keep_frames, full=False):
    tl = timeline(step)
    frames = sprite_frames(tl["sprite_frames"])
    # Solo para comprobar que la ventana animada empieza justo cuando la
    # tarjeta se va: si no coincidieran, el vídeo taparia texto o al reves.
    still_gone = next((time for time, vis in tl.get("StepImage:visible", [])
                       if not vis), None)

    # Design space -> delivery. Everything below is in delivery pixels.
    k = OUT[0] / DESIGN[0]
    sx, sy = tl["sprite_scale"]
    fw = int(round(frames[0].width * sx * k))
    fh = int(round(frames[0].height * sy * k))
    cx = tl["sprite_pos"][0] * k
    cy = tl["sprite_pos"][1] * k
    sprite_box = (int(round(cx - fw / 2)), int(round(cy - fh / 2)))
    sized = [f.resize((fw, fh), Image.LANCZOS) for f in frames]

    clips = tl.get("clips", [])
    if not clips:
        sys.exit("step_%d no tiene pista de sub-clips" % step)
    # Each sub-clip is 1.2s long and restarts the 13-frame cycle from zero.
    clip_len = 1.2

    still_track = tl.get("StepImage:visible", [])
    sprite_track = tl.get("AnimatedSprite2D:visible", [])

    # La ventana animada: del primer sub-clip a cuando el sprite se esconde.
    start = clips[0]
    end = next((time for time, vis in sprite_track if not vis and time > start),
               tl["length"])
    if full:
        # De 0 al final de la escena. El negro de cabecera y de cola es lo que
        # permite arrancar el vídeo en la MISMA llamada que la animación, sin
        # ninguna constante de tiempo en el código ni en las pistas.
        start, end = 0.0, tl["length"]

    total = int(round((end - start) * FPS))
    work = tempfile.mkdtemp(prefix="gameover_%d_" % step)
    anim_start = clips[0]
    if still_gone is not None and abs(still_gone - anim_start) > 1.0 / FPS:
        print("  AVISO: la tarjeta se va en %.4fs pero la animacion empieza en "
              "%.4fs - revisa la escena" % (still_gone, anim_start))

    print("step_%d: escena %.3fs, ventana animada %.3f-%.3fs (%.3fs), "
          "%d fotogramas a %dfps, sprite %dx%d en %s" % (
              step, tl["length"], start, end, end - start,
              total, FPS, fw, fh, sprite_box))

    for i in range(total):
        t = start + i / FPS
        canvas = Image.new("RGBA", OUT, (0, 0, 0, 255))

        # Draw order is scene order: ColorRect, AnimatedSprite2D, StepImage.
        # The still is a LATER sibling, so it covers the sprite.
        if visible_at(sprite_track, t) and clips:
            started = [c for c in clips if t + 1e-6 >= c]
            if started:
                u = t - started[-1]
                if u < clip_len:
                    idx = min(int(u / clip_len * len(sized)), len(sized) - 1)
                    canvas.alpha_composite(sized[idx], sprite_box)

        # La tarjeta NUNCA se dibuja aqui. Sigue siendo un PNG en la escena,
        # encima del vídeo, por dos motivos: es lo peor que se le puede dar a
        # un códec -texto serif fino, blanco sobre negro, con los bordes
        # destellando a 960x540- y ademas es estatica, asi que meterla en el
        # clip la empeora y se lleva la mayor parte del bitrate. Medido: con
        # ella el clip de step_1 pesa 2.03 MB; sin ella, 0.66 MB.
        canvas.convert("RGB").save(os.path.join(work, "%05d.png" % i))

    out_dir = os.path.join(ROOT, GAMEOVER, "step_%d" % step)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "death_%d.ogv" % step)

    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
           "-framerate", str(FPS), "-i", os.path.join(work, "%05d.png"),
           "-an", "-c:v", "libtheora", "-q:v", str(quality),
           "-pix_fmt", "yuv420p", out_path]
    subprocess.run(cmd, check=True)

    size = os.path.getsize(out_path)
    print("  -> %s  %.2f MB  (q=%d)" % (
        os.path.relpath(out_path, ROOT), size / 1048576.0, quality))
    print("  la escena tiene que arrancarlo en %.4fs y esconderlo en %.4fs"
          % (start, end))

    if keep_frames:
        print("  fotogramas en", work)
    else:
        shutil.rmtree(work)
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("step", type=int, choices=[1, 2, 3])
    ap.add_argument("--quality", type=int, default=8,
                    help="libtheora -q:v, 0-10 (por defecto 8)")
    ap.add_argument("--keep-frames", action="store_true")
    ap.add_argument("--full", action="store_true",
                    help="clip de la escena entera (negro incluido) en vez de "
                         "solo la ventana animada")
    args = ap.parse_args()
    build(args.step, args.quality, args.keep_frames, args.full)


if __name__ == "__main__":
    main()
