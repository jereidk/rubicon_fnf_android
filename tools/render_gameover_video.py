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
  * its TYPE_ANIMATION track, whose keys fire sub-clips on the sprite's own
    AnimationPlayer - three of them in step_1, at 6.21s, 7.42s and 8.42s - and
    the LIBRARY those keys name, because the keys do not all name the same
    thing. The first is "Final Exports_", frames 0..8, the body opening; the
    other two are "loop", frames 9..12 and nothing else, the ribcage moving.
    Reading only the times and assuming one 1.2s cycle spread over all 13
    frames is what the first version did, and it made the body close and open
    again twice - which is what shipped, and what this now fixes;
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
import io
import math
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


## La revisión de la que se leen los assets, o None para el árbol de trabajo.
##
## Las hojas de sprites y las escenas originales ya no están en HEAD: las quitó
## el propio horneado (b6a447e). Para poder REhornear hace falta volver a
## leerlas, y sacarlas de git es mejor que restaurarlas al árbol - no hay que
## acordarse de borrarlas después, y la orden queda escrita con la revisión
## dentro, así que se puede repetir tal cual dentro de un año.
SOURCE_REV = None


def blob(p):
    """El fichero, del árbol de trabajo o de SOURCE_REV."""
    rel = p.replace("res://", "")
    if SOURCE_REV is None:
        return open(os.path.join(ROOT, rel), "rb").read()
    return subprocess.run(
        ["git", "-C", ROOT, "show", "%s:%s" % (SOURCE_REV, rel)],
        check=True, stdout=subprocess.PIPE).stdout


def read(p):
    return blob(p).decode("utf-8", errors="replace")


def image(p):
    return Image.open(io.BytesIO(blob(p))).convert("RGBA")


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
        # `margin` es el hueco que el empaquetador RECORTÓ y que el motor vuelve
        # a poner al dibujar. Ignorarlo no da error, da un fotograma del tamaño
        # equivocado: el 5 de death_1 es una región de 1x1 con un margen de
        # 2042x1543, o sea un fotograma en blanco, y sin esto se estiraba ese
        # único píxel hasta ocupar el cuerpo entero.
        mm = re.search(r'margin = Rect2\(([^)]+)\)', body)
        margin = [float(v) for v in mm.group(1).split(",")] if mm else [0, 0, 0, 0]
        regions[m.group(1)] = (ext[atlas], rect, margin)

    # The order the animation plays them in, which is NOT the order the
    # sub_resources happen to be declared in.
    order = re.findall(r'"texture": SubResource\("([^"]+)"\)', text)

    sheets = {}
    frames = []
    for sid in order:
        path, (x, y, w, h), (mx, my, mw, mh) = regions[sid]
        if path not in sheets:
            sheets[path] = image(path)
        # The regions carry a fractional part; the whole-pixel box is what the
        # sheet actually stores, and it is what the engine samples from.
        box = (int(round(x)), int(round(y)),
               int(round(x + w)), int(round(y + h)))
        crop = sheets[path].crop(box)
        if mw or mh:
            full = Image.new("RGBA", (crop.width + int(round(mw)),
                                      crop.height + int(round(mh))), (0, 0, 0, 0))
            full.alpha_composite(crop, (int(round(mx)), int(round(my))))
            crop = full
        frames.append(crop)
    return frames


def library(tres_path):
    """Las sub-animaciones de la librería: nombre -> pista de `.:frame`.

    Esto es lo que la primera versión de este tool NO leía, y es el fallo que
    dejó los tres clips mal horneados. La escena dispara sus sub-clips por
    NOMBRE - en step_1, "Final Exports_" a los 6.21s y "loop" a los 7.42s y a
    los 8.42s - y el tool se quedaba solo con los tiempos, así que suponía que
    las tres claves eran la misma animación reiniciada y repartía los 13
    fotogramas por igual en 1.2s.

    No son la misma. "Final Exports_" enseña los fotogramas 0..8, que es el
    cuerpo abriéndose, y "loop" enseña SOLO 9, 10, 11 y 12, que es la caja
    torácica moviéndose. Al tratar la segunda como la primera, el vídeo volvía
    al fotograma 0 y el cuerpo se cerraba y se abría otra vez, tres veces.
    """
    text = read(tres_path)

    anims = {}
    for m in re.finditer(
            r'\[sub_resource type="Animation" id="([^"]+)"\](.*?)(?=\n\[|\Z)',
            text, re.S):
        sid, body = m.group(1), m.group(2)
        length = re.search(r'\nlength = ([\d.]+)', body)
        loop_mode = re.search(r'\nloop_mode = (\d+)', body)
        clip = {
            # Sin `length` escrito, un Animation mide 1.0s. Las dos "loop" de
            # death_2 y death_3 están así.
            "length": float(length.group(1)) if length else 1.0,
            "loop": bool(loop_mode and int(loop_mode.group(1))),
            "times": [], "values": [], "interp": 1, "update": 0,
        }
        for t in re.finditer(r'tracks/(\d+)/path = NodePath\("\.:frame"\)', body):
            n = t.group(1)
            keys = re.search(r'tracks/%s/keys = \{(.*?)\n\}' % n, body, re.S).group(1)
            clip["times"] = [float(v) for v in re.search(
                r'"times": PackedFloat32Array\(([^)]*)\)', keys).group(1).split(",")]
            clip["values"] = [int(v) for v in re.search(
                r'"values": \[([^\]]*)\]', keys).group(1).split(",")]
            interp = re.search(r'tracks/%s/interp = (\d+)' % n, body)
            clip["interp"] = int(interp.group(1)) if interp else 1
            update = re.search(r'"update": (\d+)', keys)
            clip["update"] = int(update.group(1)) if update else 0
        anims[sid] = clip

    data = re.search(r'_data = \{(.*?)\n\}', text, re.S).group(1)
    return {name: anims[sid] for name, sid in
            re.findall(r'&?"([^"]+)": SubResource\("([^"]+)"\)', data)}


def frame_at(clip, u):
    """El fotograma que una sub-animación enseña `u` segundos después de
    arrancar, con las mismas reglas que usa el motor."""
    if clip["loop"] and clip["length"] > 0.0:
        u = math.fmod(u, clip["length"])
        if u < 0.0:
            u += clip["length"]
    else:
        # Una animación que no cicla se queda en su último valor, no se apaga.
        u = min(u, clip["length"])

    times, values = clip["times"], clip["values"]
    if not times:
        return 0
    if clip["update"] == 1:
        # DISCRETE: la última clave en u o antes. Es lo que llevan las "loop".
        idx = 0
        for i, key in enumerate(times):
            if u + 1e-6 >= key:
                idx = i
            else:
                break
        return values[idx]
    if clip["interp"] == 0:
        # NEAREST, que es lo que llevan las "Final Exports_": la clave más
        # cercana, no la anterior. Cambia los bordes en medio paso de clave.
        return values[min(range(len(times)), key=lambda i: abs(times[i] - u))]
    # LINEAR sobre un entero: interpola y redondea.
    for i in range(len(times) - 1):
        if times[i] <= u <= times[i + 1]:
            span = times[i + 1] - times[i]
            w = 0.0 if span <= 0.0 else (u - times[i]) / span
            return int(round(values[i] + (values[i + 1] - values[i]) * w))
    return values[0] if u < times[0] else values[-1]


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
            # Los NOMBRES, no solo los tiempos. Vienen como "libreria/animacion"
            # y se guardan emparejados con su instante: cada clave dispara la
            # animación que nombra, y dos claves seguidas pueden nombrar cosas
            # distintas - que es exactamente lo que pasa aquí.
            names = re.search(r'"clips": PackedStringArray\(([^)]*)\)', keys)
            names = re.findall(r'"([^"]*)"', names.group(1)) if names else []
            out["clips"] = list(zip(times, [n.split("/", 1)[-1] for n in names]))

    # The sprite's transform, and the still image behind it.
    m = re.search(r'\[node name="AnimatedSprite2D"[^\]]*\](.*?)(?=\n\[node)',
                  text, re.S)
    pos = re.search(r'position = Vector2\(([^)]+)\)', m.group(1))
    scale = re.search(r'scale = Vector2\(([^)]+)\)', m.group(1))
    out["sprite_pos"] = [float(v) for v in pos.group(1).split(",")]
    out["sprite_scale"] = [float(v) for v in scale.group(1).split(",")]
    out["sprite_frames"] = ext[
        re.search(r'sprite_frames = ExtResource\("([^"]+)"\)', m.group(1)).group(1)]

    # El AnimationPlayer hijo del sprite, que es quien tiene la librería con las
    # sub-animaciones que la pista de arriba nombra.
    m = re.search(r'\[node name="AnimationPlayer"[^\]]*parent="AnimatedSprite2D"'
                  r'[^\]]*\](.*?)(?=\n\[node|\n\[connection|\Z)', text, re.S)
    if m is None:
        sys.exit("step_%d: el sprite no tiene AnimationPlayer hijo" % step)
    lib = re.search(r'libraries/\w+ = ExtResource\("([^"]+)"\)', m.group(1))
    if lib is None:
        sys.exit("step_%d: el AnimationPlayer del sprite no carga librería" % step)
    out["library"] = ext[lib.group(1)]
    # step_4 lo lleva a 1.5. Leerlo en vez de suponer 1.0 es lo mismo que
    # costó los tres clips mal: una constante escrita a mano donde había un dato.
    speed = re.search(r'speed_scale = ([\d.]+)', m.group(1))
    out["sub_speed"] = float(speed.group(1)) if speed else 1.0

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
    lib = library(tl["library"])
    missing = sorted({n for _, n in clips} - set(lib))
    if missing:
        sys.exit("step_%d: la librería no tiene %s" % (step, ", ".join(missing)))
    speed = tl["sub_speed"]

    still_track = tl.get("StepImage:visible", [])
    sprite_track = tl.get("AnimatedSprite2D:visible", [])

    # La ventana animada: del primer sub-clip a cuando el sprite se esconde.
    start = clips[0][0]
    end = next((time for time, vis in sprite_track if not vis and time > start),
               tl["length"])
    if full:
        # De 0 al final de la escena. El negro de cabecera y de cola es lo que
        # permite arrancar el vídeo en la MISMA llamada que la animación, sin
        # ninguna constante de tiempo en el código ni en las pistas.
        start, end = 0.0, tl["length"]

    total = int(round((end - start) * FPS))
    work = tempfile.mkdtemp(prefix="gameover_%d_" % step)
    anim_start = clips[0][0]
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
            started = [c for c in clips if t + 1e-6 >= c[0]]
            if started:
                when, name = started[-1]
                idx = frame_at(lib[name], (t - when) * speed)
                if 0 <= idx < len(sized):
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
    ap.add_argument("--from-git", metavar="REV",
                    help="lee escenas y hojas de esa revisión en vez del árbol "
                         "de trabajo (b6a447e^ para las de antes del horneado)")
    args = ap.parse_args()

    global SOURCE_REV
    SOURCE_REV = args.from_git
    build(args.step, args.quality, args.keep_frames, args.full)


if __name__ == "__main__":
    main()
