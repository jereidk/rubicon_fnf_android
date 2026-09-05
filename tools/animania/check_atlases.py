#!/usr/bin/env python3
"""Compara cada atlas vendorizado con su original del build del mod.

Existe por un fallo que no avisa de nada. `optimize_atlas.py` reescribia el XML emitiendo
solo name/x/y/width/height y tiraba los atributos de RECORTE -frameX, frameY, frameWidth,
frameHeight-. Un sparrow recortado guarda solo los pixeles opacos de cada fotograma y usa
esos cuatro para decir donde va ese trozo dentro del fotograma logico. Sin ellos cada
fotograma se dibuja pegado a la esquina de su fotograma logico: no hay error, no hay
aviso, solo un sprite que aparece donde no toca. Con el indicador de jefe eran 407 px.

Lo que mira:

  - recorte: si el original trae frameX y el vendorizado no, es el fallo de arriba.
  - fotogramas: cuantos tenia y cuantos quedan. Una diferencia puede ser deliberada
    -TVNOISE se quedo con 24 de 111 a proposito- pero tiene que salir a la vista.

Los originales se buscan en TODO el build, no solo en assets/images: hay atlas en
assets/shared/images y emparejar solo por una de las dos ramas deja media docena fuera y
da un "todo bien" que no vale nada. Tambien se normaliza el nombre, porque al vendorizar
se cambian espacios por guiones bajos ("bottom capsule" -> "bottom_capsule").

    python3 tools/animania/check_atlases.py [--build <ruta>] [--port <ruta>]
"""

import argparse
import struct
import sys
from pathlib import Path


def key(stem):
    return stem.lower().replace("_", " ").strip()


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def png_size(path):
    """Ancho y alto de un PNG, leyendo solo la cabecera."""
    try:
        head = path.read_bytes()[:24]
        return struct.unpack(">II", head[16:24])
    except Exception:
        return None


def pick(vendored, cands):
    """Cual de los originales homonimos es de verdad el de este.

    El desempate importa y el obvio esta MAL. La primera version se quedaba con el que
    mas recorte tuviera, y el build tiene dos `leafs`: uno del escenario de la llamada,
    337x264 y con recorte, y otro de las hojas del menu, 128x256 y sin el. El del puerto
    es el segundo, copiado tal cual, y aquel desempate lo emparejaba con el primero y
    cantaba un "RECORTE PERDIDO" que no existia.

    Manda la GEOMETRIA del PNG: si coincide, es ese. Solo si ninguno coincide se cae al
    parecido de ruta, y entonces se dice.
    """
    mine = png_size(vendored.with_suffix(".png"))
    if mine is not None:
        same = [o for o in cands if png_size(o.with_suffix(".png")) == mine]
        if len(same) == 1:
            return same[0]
        if same:
            cands = same
    if len(cands) == 1:
        return cands[0]
    # Parecido de ruta: cuantos segmentos finales comparten.
    def score(o):
        a, b = list(vendored.parts)[::-1], list(o.parts)[::-1]
        n = 0
        for x, y in zip(a, b):
            if x.lower() != y.lower():
                break
            n += 1
        return n
    return max(cands, key=score)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", type=Path,
                        default=Path("/home/user/animania_build"))
    parser.add_argument("--port", type=Path,
                        default=Path("animania_mod/source/images"))
    args = parser.parse_args()

    index = {}
    for p in args.build.rglob("*.xml"):
        index.setdefault(key(p.stem), []).append(p)

    perdidos, huerfanos, distintos = [], [], []
    for v in sorted(args.port.rglob("*.xml")):
        vt = read(v)
        if "<SubTexture" not in vt:
            continue
        cands = index.get(key(v.stem), [])
        if not cands:
            huerfanos.append(v)
            continue
        best = pick(v, cands)
        if best is None:
            huerfanos.append(v)
            continue
        ot = read(best)
        if ot.count("frameX") > 0 and vt.count("frameX") == 0:
            perdidos.append((v, best, ot.count("frameX")))
        if ot.count("<SubTexture") != vt.count("<SubTexture"):
            distintos.append((v, ot.count("<SubTexture"), vt.count("<SubTexture")))

    if perdidos:
        print("RECORTE PERDIDO (el original lo trae, el vendorizado no):")
        for v, o, n in perdidos:
            print("  %s   original %s tiene %d" % (v, o, n))
    else:
        print("recorte: ningun atlas perdio sus frameX/frameY")

    if distintos:
        print("\nnumero de fotogramas distinto (puede ser a proposito, mirarlo):")
        for v, a, b in distintos:
            print("  %-58s %d -> %d" % (str(v), a, b))

    if huerfanos:
        print("\nsin original en el build (revisar a mano):")
        for v in huerfanos:
            print("  %s" % v)

    return 1 if perdidos else 0


if __name__ == "__main__":
    sys.exit(main())
