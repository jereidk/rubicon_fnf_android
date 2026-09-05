#!/usr/bin/env python3
"""Extrae una fuente incrustada del ejecutable de Animania.

Lime empaqueta las fuentes DENTRO del binario: `assets/fonts/` no existe en disco, y
`find -name '*.ttf'` sobre el build no devuelve nada. Pero un sfnt es autodescriptivo -
cabecera, directorio de tablas, y un `name` con el nombre de familia - así que se pueden
localizar todas escaneando la firma y validando el directorio.

    python3 tools/animania/extract_font.py --list
    python3 tools/animania/extract_font.py Blueprint animania_mod/source/fonts/Blueprint.ttf

Encontradas así: VCR OSD Mono, Inconsolata (seis pesos), Blueprint, Comic Sans MS, Impact,
CCMeanwhile, 5by7, DS-Digital, Quantico, Fafo Sans, Ruthless Sketch, Dephunked BRK,
Linglong, Brusnika, Monsterrat, Nokia Cellphone FC, Pixel Arial 11, MP Manga, Funkin-options.
"""
import argparse
import re
import struct
import sys

BIN = "/home/user/animania_build/Animania"


def read_font(data: bytes, off: int):
    """Devuelve (longitud, nombres) si en `off` empieza un sfnt valido, o None."""
    try:
        version, count = struct.unpack_from(">IH", data, off)
    except struct.error:
        return None
    if version not in (0x00010000, 0x4F54544F) or not 4 <= count <= 64:
        return None

    tables, end = {}, off
    for i in range(count):
        try:
            tag, _checksum, start, length = struct.unpack_from(">4sIII", data, off + 12 + 16 * i)
        except struct.error:
            return None
        # Un directorio real no apunta a decenas de megabytes.
        if start > 40_000_000 or length > 40_000_000:
            return None
        tables[tag.decode("latin1")] = (off + start, length)
        end = max(end, off + start + length)
    if "name" not in tables or "head" not in tables:
        return None

    base = tables["name"][0]
    _fmt, entries, strings = struct.unpack_from(">HHH", data, base)
    names = set()
    for i in range(entries):
        pid, _eid, _lid, nid, length, noff = struct.unpack_from(">HHHHHH", data, base + 6 + 12 * i)
        raw = data[base + strings + noff: base + strings + noff + length]
        try:
            text = raw.decode("utf-16-be") if pid == 3 else raw.decode("latin1")
        except UnicodeDecodeError:
            continue
        # nameID 1 es la familia, 4 el nombre completo, 6 el PostScript.
        if nid in (1, 4, 6) and text.isprintable():
            names.add(text)
    return end - off, names


def scan(data: bytes):
    for match in re.finditer(rb"\x00\x01\x00\x00|OTTO", data):
        found = read_font(data, match.start())
        if found is not None:
            yield match.start(), found[0], found[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("family", nargs="?", help="nombre (o parte) de la familia")
    parser.add_argument("out", nargs="?", help="ruta de salida .ttf")
    parser.add_argument("--list", action="store_true", help="listar todas las incrustadas")
    parser.add_argument("--binary", default=BIN)
    args = parser.parse_args()

    data = open(args.binary, "rb").read()
    fonts = list(scan(data))

    if args.list or not args.family:
        for off, length, names in fonts:
            print("%#x  %8d  %s" % (off, length, ", ".join(sorted(names))))
        return 0

    wanted = args.family.lower()
    hits = [f for f in fonts if any(wanted in n.lower() for n in f[2])]
    if not hits:
        print("no hay ninguna fuente que contenga %r" % args.family, file=sys.stderr)
        return 1
    if len(hits) > 1:
        print("ambiguo, %d coinciden:" % len(hits), file=sys.stderr)
        for off, length, names in hits:
            print("  %#x  %s" % (off, ", ".join(sorted(names))), file=sys.stderr)
        return 1

    off, length, names = hits[0]
    if not args.out:
        print("%#x  %d  %s" % (off, length, ", ".join(sorted(names))))
        return 0
    open(args.out, "wb").write(data[off:off + length])
    print("escrita %s (%d bytes) desde %#x - %s" % (
        args.out, length, off, ", ".join(sorted(names))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
