#!/usr/bin/env python3
"""Lists or extracts files from a Godot .pck, without Godot.

The reference PC build sits in lullaby_mod/original_pck/Lullaby.pck. It is the
game this mod was ported from, so anything the port did not re-author is still
in there byte for byte - which makes it a source for files the working tree is
missing.

That is not a theory anyone should act on blind, so extraction prints the
sha256 of what it pulled out. A Git LFS pointer carries the object's sha256,
so a match is proof the extracted file is the identical object and not merely
a plausible one.

PCK format, pack version 4 (Godot 4.7): "GDPC", the pack version, three engine
version fields, a flags word, a u64 file base, and a u64 offset to the
directory - which lives at the END of the file, not after the header, which is
where an older reading of this format looks for it and finds a file count of
zero. The directory itself is a count followed by, per entry, a length-prefixed
path, a u64 offset, a u64 size, an md5 and a flags word.

Offsets are relative to the file base when the pack sets PACK_REL_FILEBASE
(bit 1), which this one does.

Usage:
    python3 tools/pck_extract.py list [substring]
    python3 tools/pck_extract.py get <res://path> <destination>
"""

import hashlib
import struct
import sys
from pathlib import Path

PCK = Path("lullaby_mod/original_pck/Lullaby.pck")


PACK_REL_FILEBASE = 1 << 1


def entries(f):
    magic = f.read(4)
    if magic != b"GDPC":
        raise SystemExit("no es un .pck (magic %r)" % magic)

    pack_version = struct.unpack("<I", f.read(4))[0]
    major, minor, patch = struct.unpack("<III", f.read(12))

    pack_flags = struct.unpack("<I", f.read(4))[0]
    file_base = struct.unpack("<Q", f.read(8))[0]
    dir_offset = struct.unpack("<Q", f.read(8))[0]

    if pack_version < 3:
        raise SystemExit("este lector solo entiende pack v3+ (este es v%d)" % pack_version)

    base = file_base if (pack_flags & PACK_REL_FILEBASE) else 0

    f.seek(dir_offset)
    count = struct.unpack("<I", f.read(4))[0]

    out = []
    for _ in range(count):
        path_len = struct.unpack("<I", f.read(4))[0]
        raw = f.read(path_len)
        offset, size = struct.unpack("<QQ", f.read(16))
        f.read(16)  # md5
        f.read(4)   # per-file flags
        out.append((raw.rstrip(b"\0").decode("utf-8", "replace"), base + offset, size))
    return pack_version, (major, minor, patch), out


def main():
    if not PCK.exists():
        raise SystemExit("no encuentro %s" % PCK)
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)

    with open(PCK, "rb") as f:
        version, engine, items = entries(f)

        if sys.argv[1] == "list":
            needle = sys.argv[2] if len(sys.argv) > 2 else ""
            print("pck v%d, Godot %d.%d.%d, %d archivos"
                  % (version, engine[0], engine[1], engine[2], len(items)))
            hits = [i for i in items if needle in i[0]]
            print("%d coinciden con %r" % (len(hits), needle))
            for path, _, size in sorted(hits)[:60]:
                print("   %10d  %s" % (size, path))
            return

        if sys.argv[1] == "get":
            wanted, dest = sys.argv[2], Path(sys.argv[3])
            for path, offset, size in items:
                if path != wanted:
                    continue
                f.seek(offset)
                data = f.read(size)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
                print("%s -> %s" % (path, dest))
                print("   %d bytes" % len(data))
                print("   sha256 %s" % hashlib.sha256(data).hexdigest())
                return
            raise SystemExit("no esta en el pck: %s" % wanted)

    raise SystemExit(__doc__)


main()
