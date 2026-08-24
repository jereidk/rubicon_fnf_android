#!/usr/bin/env python3
"""Compone el fondo del callejon de Safety Lullaby en una sola textura.

Las siete capas del Parallax2 (scroll 1.0, z -1, estaticas, ninguna pista las
toca) pasan a ser un unico sprite. Lamp1 se queda fuera: lleva lamp_flicker.gd
y las tres luces.

El lienzo se hornea a escala 1/2.2 del mundo (la escala dominante), asi que el
sprite fusionado lleva scale 2.2 y el GPU hace el mismo muestreo que hacia con
las capas sueltas. Las dos excepciones de escala (Street en Y, Bench) se
remuestrean en el horneado y el guard las mide.
"""
import os
import sys

from PIL import Image

BASE = "lullaby_mod/assets/funkin/safety_lullaby/maps/alley/"
OUT = BASE + "back_merged.png"

S = 2.2  # escala dominante; el sprite fusionado la lleva

# (nombre, fichero, x, y, sx, sy) en orden de hermanos = orden de pintor
LAYERS = [
    ("Street", "street.png", 936.0, 968.0, 2.2, 2.38791),
    ("Trees", "trees.png", 854.0, 155.0, 2.2, 2.2),
    ("LongFence", "longfence.png", 1715.0, 532.0, 2.2, 2.2),
    ("Bench", "bench.png", 1518.0, 722.0, 2.11864, 2.11864),
    ("Pokecenter", "pokecenter.png", 414.0, 415.0, 2.2, 2.2),
    ("Lamp2", "lampoff.png", 1063.0, 253.0, 2.2, 2.2),
    ("BrokenLamp", "lampbroken.png", -231.0, 603.0, 2.2, 2.2),
]


def main() -> int:
    # Cajas en unidades de mundo (centro = posicion, Sprite2D centrado)
    boxes = []
    for name, f, x, y, sx, sy in LAYERS:
        im = Image.open(BASE + f)
        w, h = im.size
        dw, dh = w * sx, h * sy
        boxes.append((x - dw / 2, y - dh / 2, x + dw / 2, y + dh / 2))

    minx = min(b[0] for b in boxes)
    miny = min(b[1] for b in boxes)
    maxx = max(b[2] for b in boxes)
    maxy = max(b[3] for b in boxes)

    # Lienzo en pixeles de textura (mundo / S), con 1px de margen para el
    # muestreo bilineal de los bordes, redondeado a multiplo de 8 (ASTC 8x8).
    cw = int((maxx - minx) / S + 0.5) + 2
    ch = int((maxy - miny) / S + 0.5) + 2
    cw = (cw + 7) // 8 * 8
    ch = (ch + 7) // 8 * 8

    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    for (name, f, x, y, sx, sy), (bx0, by0, bx1, by1) in zip(LAYERS, boxes):
        im = Image.open(BASE + f).convert("RGBA")
        # Tamano en el lienzo: caja de mundo / S
        tw = max(1, round((bx1 - bx0) / S))
        th = max(1, round((by1 - by0) / S))
        if (tw, th) != im.size:
            im = im.resize((tw, th), Image.LANCZOS)
        px = round((bx0 - minx) / S) + 1
        py = round((by0 - miny) / S) + 1
        canvas.alpha_composite(im, (px, py))
        print(f"  {name:11s} -> ({px:4d},{py:4d}) {tw}x{th}")

    canvas.save(OUT)
    # El borde izquierdo del lienzo esta 1px (el margen) a la izquierda de minx;
    # el relleno a multiplo de 8 queda a la derecha. La posicion del sprite es
    # el centro del LIENZO en unidades de mundo, no el centro de la union.
    ox = minx - S
    oy = miny - S
    cx = ox + cw * S / 2
    cy = oy + ch * S / 2
    print(f"lienzo {cw}x{ch} centro_mundo=({cx:.3f}, {cy:.3f})")
    print(f"sprite: position = Vector2({cx:.3f}, {cy:.3f}) scale = Vector2({S}, {S})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
