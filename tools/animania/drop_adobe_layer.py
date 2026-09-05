#!/usr/bin/env python3
"""Quita una capa de un Animation.json de Adobe Animate, dejando dicho por que.

gdanimate dibuja el arbol de simbolos de un atlas de Adobe, pero NO aplica ni los filtros
de Animate ni sus modos de mezcla. Casi nunca importa. Cuando importa, importa mucho.

El caso que motivo esto: `bf-animania` tiene una capa con una sola instancia,
`symbols/green light`, llamada `add` y con un filtro de desenfoque de 89x89. Es el reflejo
verde del televisor sobre el personaje. Sin desenfoque y sin mezcla aditiva sale un ovalo
verde OPACO y de bordes duros pegado a la cara, que esta mas lejos del aspecto del mod que
no dibujar nada. `gf-animania` no tiene ninguna capa asi.

Esto NO borra nada del build del mod: opera sobre la copia vendorizada, y deja constancia
en el propio JSON de que capa se quito y por que, para que la siguiente persona no crea
que el atlas venia asi.

    python3 tools/animania/drop_adobe_layer.py <carpeta_atlas> <simbolo> <capa>

Comprobar antes con --list, que enumera las capas y marca las que llevan filtro.
"""

import argparse
import json
import sys
from pathlib import Path


def symbols(data):
    """Los simbolos del diccionario, mas el de la raiz."""
    out = list(data.get("SD", {}).get("S", []))
    root = data.get("AN")
    if root:
        out.append(root)
    return out


def layers_of(symbol):
    return symbol.get("TL", {}).get("L", [])


def filtered(layer):
    """Nombres de instancia de esa capa que llevan filtro de Animate."""
    names = []
    for frame in layer.get("FR", []):
        for element in frame.get("E", []):
            info = element.get("SI") or {}
            if isinstance(info.get("F"), dict):
                names.append("%s (%s, %s)" % (
                    info.get("SN"), info.get("IN"), ",".join(sorted(info["F"]))))
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("symbol", nargs="?")
    parser.add_argument("layer", nargs="?")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    path = args.folder / "Animation.json"
    data = json.loads(path.read_text(encoding="utf-8"))

    if args.list or not args.symbol:
        for symbol in symbols(data):
            for layer in layers_of(symbol):
                marks = filtered(layer)
                print("%-42s %-12s fr=%-3d %s" % (
                    symbol.get("SN"), layer.get("LN"), len(layer.get("FR", [])),
                    "  FILTRO: " + "; ".join(sorted(set(marks))) if marks else ""))
        return

    for symbol in symbols(data):
        if symbol.get("SN") != args.symbol:
            continue
        layers = layers_of(symbol)
        keep = [l for l in layers if l.get("LN") != args.layer]
        if len(keep) == len(layers):
            sys.exit("%r no tiene la capa %r" % (args.symbol, args.layer))
        symbol["TL"]["L"] = keep
        # Que quede en el fichero, no solo en el commit.
        data.setdefault("_porteo", []).append(
            "capa %r quitada de %r: gdanimate no aplica su filtro ni su mezcla" % (
                args.layer, args.symbol))
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        print("quitada %r de %r (%d capas -> %d)" % (
            args.layer, args.symbol, len(layers), len(keep)))
        # El cache derivado deja de valer.
        cache = args.folder / "animation_cache.res"
        if cache.exists():
            cache.unlink()
            print("borrado el cache derivado", cache)
        return

    sys.exit("no hay ningun simbolo %r" % args.symbol)


if __name__ == "__main__":
    main()
