#!/usr/bin/env python3
"""Names a vtable slot, so `call *0x210(%rax)` stops being a guess.

    python3 tools/animania/vtslot.py FunkinSprite 0x210 0x3a8 ...
    python3 tools/animania/vtslot.py FunkinSprite            # vuelca la tabla

El argumento de clase se busca dentro de "vtable for ...", asi que basta con
una parte del nombre mientras sea unica.

Dos trampas que costaron un rato:
  - el puntero que el objeto guarda apunta 0x10 MAS ALLA del simbolo "vtable
    for X" (se salta offset-to-top y el typeinfo), asi que la ranura N esta en
    simbolo + 0x10 + N;
  - la ranura depende de la CLASE del receptor. En createLock de
    StoryMenuSelectSubState las dos llamadas a 0x118 y 0x120 no son update() y
    draw() del sprite: el receptor es su `scale`, un FlxBasePoint, donde esas
    ranuras son set_x y set_y. Si el nombre que sale no tiene sentido para los
    argumentos, el receptor no es el que creias.
"""
import re, struct, subprocess, sys, os

BIN = os.environ.get("ANIMANIA_BIN", "/home/user/animania_build/Animania")


def sections():
    """(virtual address, file offset, size) por seccion, para traducir una VA."""
    out = subprocess.run(["readelf", "-S", "-W", BIN], capture_output=True, text=True).stdout
    maps = []
    for line in out.splitlines():
        m = re.match(r"\s*\[\s*\d+\]\s+\S+\s+\S+\s+([0-9a-f]{8,16})\s+"
                     r"([0-9a-f]{6,16})\s+([0-9a-f]{6,16})", line)
        if m:
            maps.append((int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)))
    return maps


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    want = sys.argv[1]
    slots = [int(a, 0) for a in sys.argv[2:]]

    nm = subprocess.run(["nm", "-C", "--defined-only", BIN], capture_output=True, text=True).stdout
    syms, vtables = {}, []
    for line in nm.splitlines():
        p = line.split(" ", 2)
        if len(p) != 3 or not p[0].strip():
            continue
        try:
            addr = int(p[0], 16)
        except ValueError:
            continue
        syms.setdefault(addr, p[2])
        if p[2].startswith("vtable for ") and want in p[2]:
            vtables.append((addr, p[2]))
    if not vtables:
        print("sin vtable que contenga %r" % want)
        return 1
    exact = [v for v in vtables if v[1] == "vtable for " + want]
    if exact:
        vtables = exact
    if len(vtables) > 1:
        print("ambiguo, %d coincidencias:" % len(vtables))
        for _, n in vtables[:12]:
            print("   ", n)
        return 1

    base, name = vtables[0]
    maps = sections()
    data = open(BIN, "rb").read()

    def ptr(va: int) -> int:
        for sva, off, size in maps:
            if sva <= va < sva + size:
                o = va - sva + off
                return struct.unpack("<Q", data[o:o + 8])[0]
        raise SystemExit("va %x fuera de toda seccion" % va)

    print(name)
    if not slots:
        slots = range(0, 0x600, 8)
    for s in slots:
        try:
            a = ptr(base + 0x10 + s)
        except SystemExit:
            break
        n = syms.get(a)
        if n or sys.argv[2:]:
            print("  0x%03x -> %s" % (s, n or "?? %x" % a))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
