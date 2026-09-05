#!/usr/bin/env python3
"""Adelgaza un atlas Sparrow (png + xml) sin que se note en pantalla.

Los dos atlas de televisor de freeplay estaban fuera del puerto por presupuesto de
textura: TVBACK son 5492x8192 RGBA (171.6 MB descomprimido) y TVNOISE 5279x2528
(50.9 MB). La idea de "reempaquetar para quitar el hueco que sobra" no da nada -
medidos, van al 92% y al 94% de ocupacion, ya vienen apretados-. Lo que sí da es
mirar de qué está hecho cada uno:

  TVBACK   98 fotogramas de 668x721, de los cuales 86 son regiones distintas. El
           contenido son bandas de scanline: el gradiente vertical medio es 3.51 y
           el horizontal 0.54, o sea 6.45 veces mas informacion a lo alto que a lo
           ancho. Reducir SOLO el ancho conserva casi todo. A igualdad de memoria,
           167x721 saca 44.9 dB de PSNR y un 334x360 isotropico solo 40.4 dB.

  TVNOISE  111 fotogramas de 373x301 de nieve de televisor. La correlacion entre
           el perfil de brillo por fila de dos fotogramas cualesquiera es 0.05: no
           hay ninguna estructura que se desplace, cada fotograma es un sorteo
           independiente. Tirar fotogramas es gratis; reducir la resolucion no lo
           es, porque cambia el tamano del grano.

Uso:

    python3 tools/animania/optimize_atlas.py ENTRADA.png SALIDA.png \\
        [--scale-x F] [--scale-y F] [--frames N] [--bits N] [--no-dedupe]

El xml se lee y se escribe junto al png. Con --frames N se queda con N fotogramas
repartidos por toda la secuencia (para ruido, donde el orden da igual) y renumera.

Medir antes de elegir: --report imprime el PSNR de cada tamano candidato compuesto
sobre negro al tamano al que el puerto lo dibuja, que es lo unico que importa.
"""

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
from PIL import Image

# El puerto dibuja a 1920x1080 lo que el mod dibuja a 1280x720.
FUNKIN_TO_RUBICON = 1.5

# Limite de lado de textura seguro en GLES3 sobre Android.
MAX_SIDE = 4096


def read_atlas(png: Path):
    """Devuelve (imagen, [ {name,x,y,width,height,...} ]) de un Sparrow.

    El modo se respeta: TVNOISE viene en LA (gris + alfa) y convertirlo a RGBA
    duplicaba su peso en disco sin anadir un solo color.
    """
    xml = png.with_suffix(".xml")
    root = ET.fromstring(xml.read_text(encoding="utf-8", errors="replace"))
    frames = [dict(node.attrib) for node in root.iter("SubTexture")]
    if not frames:
        sys.exit("%s no tiene SubTexture" % xml)
    image = Image.open(png)
    if image.mode not in ("RGBA", "LA"):
        image = image.convert("RGBA")
    return image, frames


def cut(image, frame):
    x, y = int(frame["x"]), int(frame["y"])
    w, h = int(frame["width"]), int(frame["height"])
    return image.crop((x, y, x + w, y + h))


def resize(tile, scale_x, scale_y):
    """Lanczos sobre RGBA recta.

    Premultiplicar y deshacerlo despues suena mejor y es peor: el alfa de estos
    atlas es binario al 99.5%, asi que dividir por un alfa pequeno en el borde
    dispara el RGB y aparece un halo. Sin premultiplicar no hay halo - lo que
    parecia halo en una primera medicion era el arnes, que hacia convert('RGB') y
    tiraba el alfa en vez de componer.
    """
    w = max(1, round(tile.width * scale_x))
    h = max(1, round(tile.height * scale_y))
    if (w, h) == tile.size:
        return tile
    return tile.resize((w, h), Image.LANCZOS)


def quantize(image, bits):
    """Recorta la profundidad de color dejando el alfa intacto.

    El remuestreo de Lanczos deja 1.26 millones de colores distintos donde el arte
    original tenia bandas bastante planas, y eso es lo que hincha el PNG: los tres
    canales de color cuestan 3.5-3.8 MB cada uno comprimidos por separado y el alfa
    solo 0.06 MB. A 64 niveles por canal el PNG baja de 7.8 a 4.4 MB y se pierden
    1.8 dB, sin banding visible. Se reconstruye al centro del escalon para no
    oscurecer la imagen entera medio nivel.
    """
    if bits >= 8:
        return image
    a = np.asarray(image).astype(np.uint8).copy()
    step = 1 << (8 - bits)
    channels = 3 if image.mode == "RGBA" else 1
    a[..., :channels] = np.clip(
        (a[..., :channels].astype(np.uint16) // step) * step + step // 2,
        0, 255).astype(np.uint8)
    return Image.fromarray(a, image.mode)


def pack(tiles, padding=1):
    """Empaquetado por estanterias, ordenando por altura.

    Los fotogramas de un atlas de animacion son todos del mismo tamano, asi que un
    empaquetador de estanterias llega al mismo sitio que uno bueno.
    """
    order = sorted(range(len(tiles)), key=lambda i: -tiles[i].height)
    cell_w = max(t.width for t in tiles) + padding
    cell_h = max(t.height for t in tiles) + padding

    # Todos los fotogramas miden lo mismo, asi que el empaquetado se reduce a elegir
    # cuantos caben por fila. Se prueban todos los repartos que no pasen de MAX_SIDE
    # y se coge el de menos area: la ultima fila a medias es todo el desperdicio, y
    # 22x4 desperdicia dos huecos donde 19x5 desperdicia nueve.
    best = None
    for per_row in range(1, len(tiles) + 1):
        w = per_row * cell_w + padding
        rows = -(-len(tiles) // per_row)
        h = rows * cell_h + padding
        if w > MAX_SIDE or h > MAX_SIDE:
            continue
        if best is None or w * h < best[0]:
            best = (w * h, per_row)
    if best is None:
        sys.exit("no cabe en %dx%d ni con una sola fila" % (MAX_SIDE, MAX_SIDE))
    width = best[1] * cell_w + padding

    places = [None] * len(tiles)
    x = y = padding
    row_height = 0
    for i in order:
        tile = tiles[i]
        if x + tile.width + padding > width:
            x = padding
            y += row_height + padding
            row_height = 0
        places[i] = (x, y)
        x += tile.width + padding
        row_height = max(row_height, tile.height)
    height = y + row_height + padding

    mode = tiles[0].mode
    sheet = Image.new(mode, (width, height), (0,) * len(mode))
    for tile, (px, py) in zip(tiles, places):
        sheet.paste(tile, (px, py))
    return sheet, places


def psnr(reference, test):
    a = np.asarray(reference).astype(np.float32)
    b = np.asarray(test).astype(np.float32)
    mse = ((a - b) ** 2).mean()
    return 10 * np.log10(255 * 255 / max(mse, 1e-9))


def over_black(image):
    rgba = image.convert("RGBA")
    return Image.alpha_composite(
        Image.new("RGBA", rgba.size, (0, 0, 0, 255)), rgba).convert("RGB")


def report(image, frames, candidates):
    """PSNR de cada candidato, compuesto sobre negro al tamano de pantalla."""
    sample = [frames[i] for i in range(0, len(frames), max(1, len(frames) // 5))][:5]
    print("%-14s %10s %10s  %s" % ("tamano", "px/fot.", "MB RGBA", "PSNR"))
    for scale_x, scale_y in candidates:
        scores = []
        for frame in sample:
            tile = cut(image, frame)
            drawn = (round(tile.width * FUNKIN_TO_RUBICON),
                     round(tile.height * FUNKIN_TO_RUBICON))
            reference = over_black(tile.resize(drawn, Image.BILINEAR))
            small = resize(tile, scale_x, scale_y)
            scores.append(psnr(reference,
                               over_black(small.resize(drawn, Image.BILINEAR))))
        w = round(int(sample[0]["width"]) * scale_x)
        h = round(int(sample[0]["height"]) * scale_y)
        print("%-14s %10d %10.1f  %.1f dB" % (
            "%dx%d" % (w, h), w * h, len(frames) * w * h * 4 / 1048576,
            sum(scores) / len(scores)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path, nargs="?")
    parser.add_argument("--scale-x", type=float, default=1.0)
    parser.add_argument("--scale-y", type=float, default=1.0)
    parser.add_argument("--frames", type=int, default=0,
                        help="quedarse con N fotogramas repartidos por la secuencia")
    parser.add_argument("--no-dedupe", action="store_true")
    parser.add_argument("--bits", type=int, default=8,
                        help="niveles por canal de color, 8 = sin tocar")
    parser.add_argument("--report", action="store_true",
                        help="solo medir, sin escribir nada")
    args = parser.parse_args()

    image, frames = read_atlas(args.source)
    before = image.width * image.height * 4 / 1048576
    print("entrada  %s  %dx%d %s  %d fotogramas  %.1f MB RGBA en GPU  %.2f MB en disco"
          % (args.source.name, image.width, image.height, image.mode, len(frames),
             before, args.source.stat().st_size / 1048576))

    if args.report:
        report(image, frames, [(1.0, 1.0), (0.5, 0.5), (0.25, 1.0),
                               (0.25, 0.8), (0.2, 0.8), (0.15, 0.75)])
        return

    if not args.target:
        sys.exit("hace falta un destino (o --report)")

    kept = frames
    if args.frames and args.frames < len(frames):
        step = len(frames) / args.frames
        kept = [frames[int(i * step)] for i in range(args.frames)]
        print("  fotogramas %d -> %d (uno de cada %.1f)"
              % (len(frames), len(kept), step))

    # Deduplicado por contenido, no por region: dos SubTexture pueden apuntar al
    # mismo sitio del png y tambien puede haber copias en sitios distintos.
    tiles = []
    index = []
    seen = {}
    for frame in kept:
        tile = cut(image, frame)
        key = tile.tobytes() if not args.no_dedupe else object()
        if key in seen:
            index.append(seen[key])
            continue
        seen[key] = len(tiles)
        index.append(len(tiles))
        tiles.append(resize(tile, args.scale_x, args.scale_y))
    if len(tiles) != len(kept):
        print("  regiones %d -> %d tras deduplicar" % (len(kept), len(tiles)))

    sheet, places = pack(tiles)
    sheet = quantize(sheet, args.bits)
    args.target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.target, optimize=True)

    root = ET.Element("TextureAtlas", {"imagePath": args.target.name})
    prefix = re.sub(r"\d+$", "", kept[0]["name"])
    for i, frame in enumerate(kept):
        tile = tiles[index[i]]
        x, y = places[index[i]]
        ET.SubElement(root, "SubTexture", {
            "name": "%s%04d" % (prefix, i),
            "x": str(x), "y": str(y),
            "width": str(tile.width), "height": str(tile.height),
        })
    ET.indent(root, space="\t")
    args.target.with_suffix(".xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        + ET.tostring(root, encoding="unicode") + "\n", encoding="utf-8")

    after = sheet.width * sheet.height * 4 / 1048576
    used = sum(t.width * t.height for t in tiles)
    print("salida   %s  %dx%d  %d fotogramas  %.1f MB RGBA en GPU  %.2f MB en disco"
          % (args.target.name, sheet.width, sheet.height, len(kept), after,
             args.target.stat().st_size / 1048576))
    print("         %.1fx menos memoria, %.0f%% de la hoja ocupada, %d niveles por canal"
          % (before / after, 100.0 * used / (sheet.width * sheet.height), 1 << args.bits))


if __name__ == "__main__":
    main()
