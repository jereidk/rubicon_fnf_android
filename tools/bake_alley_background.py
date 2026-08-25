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

    # El borde izquierdo del lienzo esta 1px (el margen) a la izquierda de minx;
    # el relleno a multiplo de 8 queda a la derecha. La posicion del sprite es
    # el centro del LIENZO en unidades de mundo, no el centro de la union.
    ox = minx - S
    oy = miny - S
    cx = ox + cw * S / 2
    cy = oy + ch * S / 2

    _bake_bglight(canvas, ox, oy)

    canvas.save(OUT)
    print(f"lienzo {cw}x{ch} centro_mundo=({cx:.3f}, {cy:.3f})")
    print(f"sprite: position = Vector2({cx:.3f}, {cy:.3f}) scale = Vector2({S}, {S})")
    return 0


## El BgLight del callejon (PointLight2D, blend MIX) es estatico durante toda
## la cancion: la pista de `play` solo reafirma energy=0.75 y la de modulate
## esta vacia; RESET dice lo mismo. Su efecto sobre el fondo se puede hornear
## en la textura y sacar al fondo de su mascara - la luz se queda para Lamp1 y
## los personajes, que es lo unico que se mueve.
##
## La formula esta MEDIDA, no supuesta: renderizando ColorRect de grises
## conocidos bajo un clon de la luz (tools/harness/calib_light2d_maps.gd) el
## resultado es, texel a texel,
##
##     salida = base * [(1 - alfa) + alfa * rgb_gradiente * energy]
##
## con error <= 1/255 en los cinco puntos probados, incluidos los de alfa < 1.
##
## La energia es la de la CANCION (0.75), no la del alley suelto (1.0 por
## defecto): la unica instancia real del escenario es la de
## sng_safety_lullaby.tscn, y es la que manda. Si alguien cambia ese override
## hay que rehornear - el guard compara los dos numeros.
LIGHT_POS = (801.0, 449.0)
LIGHT_TEX = (1049.0, 480.0)
LIGHT_SCALE = 4.0
LIGHT_ENERGY = 0.75


def _bake_bglight(canvas: Image.Image, ox: float, oy: float) -> None:
    import numpy as np

    grad = np.array(Image.open(BASE + "darkness_gradient.png").convert("RGBA")).astype(np.float64) / 255.0
    a = np.array(canvas).astype(np.float64) / 255.0

    h, w = a.shape[:2]
    # Posicion de mundo del centro de cada texel del lienzo
    ys = oy + (np.arange(h) + 0.5) * S
    xs = ox + (np.arange(w) + 0.5) * S
    # uv en la textura de la luz, con la misma cuenta que PointLight2D
    us = (xs - LIGHT_POS[0]) / (LIGHT_TEX[0] * LIGHT_SCALE) + 0.5
    vs = (ys - LIGHT_POS[1]) / (LIGHT_TEX[1] * LIGHT_SCALE) + 0.5

    # Muestreo bilineal del gradiente (el mismo filtro que aplica el motor)
    gx = np.clip(us * LIGHT_TEX[0] - 0.5, -1, LIGHT_TEX[0])
    gy = np.clip(vs * LIGHT_TEX[1] - 0.5, -1, LIGHT_TEX[1])

    def bilinear(channel: np.ndarray, gy2d: np.ndarray, gx2d: np.ndarray) -> np.ndarray:
        x0 = np.floor(gx2d).astype(int)
        y0 = np.floor(gy2d).astype(int)
        x1 = x0 + 1
        y1 = y0 + 1
        fx = gx2d - x0
        fy = gy2d - y0
        h2, w2 = channel.shape
        x0c = np.clip(x0, 0, w2 - 1)
        x1c = np.clip(x1, 0, w2 - 1)
        y0c = np.clip(y0, 0, h2 - 1)
        y1c = np.clip(y1, 0, h2 - 1)
        c00 = channel[y0c, x0c]
        c10 = channel[y0c, x1c]
        c01 = channel[y1c, x0c]
        c11 = channel[y1c, x1c]
        return (c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy)
                + c01 * (1 - fx) * fy + c11 * fx * fy)

    gxs, gys = np.meshgrid(gx, gy)
    alpha = bilinear(grad[..., 3], gys, gxs)
    inside = ((gxs >= 0) & (gxs <= LIGHT_TEX[0] - 1)
              & (gys >= 0) & (gys <= LIGHT_TEX[1] - 1))

    for ch in range(3):
        gch = bilinear(grad[..., ch], gys, gxs)
        m = (1.0 - alpha) + alpha * gch * LIGHT_ENERGY
        a[..., ch] = np.where(inside, a[..., ch] * m, a[..., ch])

    out = np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)
    canvas.paste(Image.fromarray(out, "RGBA"))


if __name__ == "__main__":
    sys.exit(main())
