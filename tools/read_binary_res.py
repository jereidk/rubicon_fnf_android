#!/usr/bin/env python3
"""Reads the external references out of Godot's binary .res/.scn files.

Why this has to exist: a .tres is text and a grep finds everything in it, but a
.res is a binary resource and this project's are `RSCC` - compressed - so even
`strings` comes back empty. Every tool in tools/ that walks references stops
dead at one, and that blind spot hid a real port bug for the whole port.

`spr_serena_scared.res`, which the Chimera song loads for its heartbeat
mechanic, points at:

    res://assets/funkin/chimera/textures/serena/heartbeat_mechanic/...

That is the PC pck's root. In this repo the mod lives under res://lullaby_mod/,
and every reference had to be rewritten when it was ported - the .tscn and
.tres were, the .res were not, because nothing could read them.

The format, from Godot's FileAccessCompressed::open_after_magic():

    "RSCC"      magic
    u32         compression mode - 2 is MODE_ZSTD, which is what these use
    u32         block size
    u32         total decompressed size
    u32 * bc    compressed size of each block, bc = total/block + 1
    ...         the blocks, back to back

Each block decompresses to `block size`, except the last, which is the
remainder. Uncompressed resources start with "RSRC" instead and are read as-is.

Usage:
    python3 tools/read_binary_res.py <file.res> [...]
    python3 tools/read_binary_res.py --scan          # todo el arbol
    python3 tools/read_binary_res.py --scan --bad    # solo los que apuntan mal
"""

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = re.compile(rb'(?:res|uid)://[\x20-\x7e]+')


def payload(path):
    """El contenido del recurso, descomprimido si hace falta."""
    data = open(path, "rb").read()
    if data[:4] != b"RSCC":
        return data
    try:
        import zstandard
    except ImportError:
        sys.exit("hace falta el modulo zstandard para leer un .res comprimido")

    cmode, block, total = struct.unpack_from("<III", data, 4)
    if cmode != 2:
        # Godot tambien sabe FASTLZ, deflate, gzip y brotli. Aqui no aparecen, y
        # es mejor decirlo que devolver basura que parezca una respuesta.
        raise ValueError("%s usa el modo de compresion %d, no ZSTD" % (path, cmode))

    count = total // block + 1
    at = 16
    sizes = [struct.unpack_from("<I", data, at + 4 * i)[0] for i in range(count)]
    at += 4 * count

    dc = zstandard.ZstdDecompressor()
    out = b""
    for i, csize in enumerate(sizes):
        want = min(block, total - i * block)
        out += dc.decompress(data[at:at + csize], max_output_size=want)
        at += csize
    return out


def refs(path):
    """Las rutas res:// y uid:// que `path` menciona, sin contarse a si mismo."""
    me = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    out = []
    for m in REF.findall(payload(path)):
        r = m.decode("ascii", "replace")
        if r != me:
            out.append(r)
    return sorted(set(out))


def main():
    args = sys.argv[1:]
    only_bad = "--bad" in args
    if only_bad:
        args.remove("--bad")

    if "--scan" in args:
        files = []
        for dp, dn, fn in os.walk(ROOT):
            dn[:] = [d for d in dn if d not in (".git", ".godot", "reference")]
            files += [os.path.join(dp, f) for f in fn
                      if f.endswith((".res", ".scn"))]
    else:
        files = [a if os.path.isabs(a) else os.path.join(ROOT, a) for a in args]
    if not files:
        sys.exit(__doc__)

    bad = 0
    for p in sorted(files):
        rel = os.path.relpath(p, ROOT)
        try:
            got = refs(p)
        except Exception as e:
            print("%s: NO SE LEE - %s" % (rel, e))
            bad += 1
            continue

        # Una ruta a res://assets/ o res://songs/ es la raiz del pck de PC, no
        # la de este repo. Es lo que se busca.
        wrong = [r for r in got if r.startswith(("res://assets/", "res://songs/",
                                                 "res://scripts/", "res://resources/"))]
        missing = [r for r in got
                   if r.startswith("res://")
                   and not os.path.exists(os.path.join(ROOT, r[6:]))]
        if only_bad and not wrong and not missing:
            continue

        print("%s%s" % (rel, "   <-- RUTA DE PCK" if wrong else ""))
        for r in got:
            mark = ""
            if r in wrong:
                mark = "  [pck]"
            if r in missing:
                mark += "  [NO EXISTE]"
            print("    %s%s" % (r, mark))
        if wrong or missing:
            bad += 1

    print("\n%d ficheros, %d con rutas de pck o rotas" % (len(files), bad))


if __name__ == "__main__":
    main()


## --- La tabla de recursos externos, leida de verdad -------------------------
##
## El regex de arriba saca las rutas, y para "que menciona esto" basta. Pero no
## contesta la pregunta que importa cuando una ruta no existe en disco: Godot
## resuelve un recurso externo POR UID primero y solo cae a la ruta si el uid no
## esta o no resuelve. Un uid va como entero de 64 bits, no como texto, asi que
## un regex no lo ve y no se puede distinguir "roto" de "resuelve por uid".
##
## Formato, de ResourceLoaderBinary::open():
##
##     "RSRC"  u32 big_endian  u32 use_real64
##     u32 ver_major  u32 ver_minor  u32 ver_format
##     str type   u64 importmd_ofs   u32 flags
##     u64 uid                       (si flags trae FORMAT_FLAG_UIDS)
##     u32 script_class              (si flags trae FORMAT_FLAG_HAS_SCRIPT_CLASS)
##     u32 * 11                      reservados
##     u32 n  +  n cadenas           tabla de cadenas
##     u32 m  +  m * (str type, str path, u64 uid si FLAG_UIDS)
##
## Una cadena es u32 de longitud y luego esos bytes.

FLAG_NAMED_SCENE_IDS = 1
FLAG_UIDS = 2
FLAG_REAL_T_IS_DOUBLE = 4
FLAG_HAS_SCRIPT_CLASS = 8

NO_UID = 0xFFFFFFFFFFFFFFFF


def _u32(d, at):
    return struct.unpack_from("<I", d, at)[0], at + 4


def _u64(d, at):
    return struct.unpack_from("<Q", d, at)[0], at + 8


def _str(d, at):
    n, at = _u32(d, at)
    return d[at:at + n].split(b"\0")[0].decode("utf-8", "replace"), at + n


def externals(path):
    """[(tipo, ruta, uid_o_None), ...] tal como el fichero los declara."""
    d = payload(path)

    # Un fichero comprimido NO repite el magic dentro del flujo. Godot lee
    # "RSCC" del fichero real, monta un FileAccessCompressed encima y sigue
    # leyendo `big_endian` directamente del flujo descomprimido, asi que ahi el
    # contenido empieza en el offset 0 y no en el 4. Comprobarlo costo un error:
    # exigir "RSRC" rechazaba todos los comprimidos, que son justo los que hay.
    at = 0
    if d[:4] == b"RSRC":
        at = 4
    _big, at = _u32(d, at)
    _r64, at = _u32(d, at)
    _maj, at = _u32(d, at)
    _min, at = _u32(d, at)
    _fmt, at = _u32(d, at)
    _type, at = _str(d, at)
    _imd, at = _u64(d, at)
    flags, at = _u32(d, at)

    if flags & FLAG_UIDS:
        _uid, at = _u64(d, at)
    if flags & FLAG_HAS_SCRIPT_CLASS:
        _sc, at = _str(d, at)
    at += 4 * 11

    n, at = _u32(d, at)
    for _ in range(n):
        _s, at = _str(d, at)

    m, at = _u32(d, at)
    out = []
    for _ in range(m):
        typ, at = _str(d, at)
        p, at = _str(d, at)
        uid = None
        if flags & FLAG_UIDS:
            uid, at = _u64(d, at)
            if uid == NO_UID:
                uid = None
        out.append((typ, p, uid))
    return out


def uid_to_text(v):
    """El uid como lo escribe Godot. base = ('z'-'a') + ('9'-'0') = 34."""
    if v is None:
        return "(sin uid)"
    s = ""
    while v:
        c = v % 34
        s = (chr(ord("a") + c) if c < 25 else chr(ord("0") + c - 25)) + s
        v //= 34
    return "uid://" + s
