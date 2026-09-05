#!/usr/bin/env python3
"""Vuelca un metodo compilado de hxcpp como una tabla de una fila por linea de Haxe.

hxcpp escribe el numero de linea en el marco de pila antes del codigo de cada linea
(`movl $0xNNN,-0x40(%rbp)`, o a un hueco de %rsp segun el prologo), asi que se puede
agrupar todo lo que hace un metodo por la linea del fuente que lo generó. Para un metodo
de construccion -buildBg son 14018 bytes- eso convierte una lectura instruccion a
instruccion en algo que se lee de una pasada:

    1241   =>darkOverlay  esi=-16777216  set_color
    1243   z=8
    1244   0.4  set_alpha

Por cada linea saca lo que suele importar: el campo del objeto al que se escribe, el
zIndex inmediato, los enteros que van por esi (los argumentos de los constructores de
hxcpp llegan asi), las cadenas y los dobles que se cargan relativos a rip, el hueco de
vtable de cada llamada indirecta y el nombre de las llamadas directas.

    python3 tools/animania/hxlines.py FreeplayScreen_obj::buildBg
    python3 tools/animania/hxlines.py 0x34b8df0 0x34b9705 --fields freeplay

`--fields` elige la tabla de nombres de campo; sin ella los offsets salen crudos. Las
tablas salen de `__GetFields` mas `__Mark`, como explica PORTING.md.

Dos limites que conviene tener presentes al leer la salida:

- La tabla de campos se aplica a CUALQUIER base que no sea la pila, no solo a `this`, asi
  que un `.curSelected` justo detras de un `.tvSprite` casi siempre es en realidad
  `tvSprite.animation` (0x108 en FlxSprite choca con 0x108 en FreeplayScreen). El offset
  manda; el nombre es una pista.
- Una linea de Haxe que genera mucho codigo -un FlxTween.tween con su objeto anonimo-
  sale como una fila larga y desordenada. Para esas hay que bajar al desensamblado.
"""

import argparse
import re
import struct
import subprocess
import sys
from pathlib import Path

BINARY = Path("/home/user/animania_build/Animania")

# offset -> nombre, de FreeplayScreen_obj::__GetFields cruzado con __Mark. Base 0xe0.
FREEPLAY_FIELDS = {
    0xE0: "currentCharacterId", 0xE8: "currentCharacter", 0xF0: "stickerSubState",
    # OJO: hxcpp NO respeta el orden de declaracion aqui. Se declaran totalDiffs (Int),
    # curSelectedFloat (Float) y curSelected (Int), y quedan con el double DELANTE de los
    # dos enteros. Probado en changeSelection (0x34c8f30): `mov %eax,0x100(%rbx)` es una
    # escritura de 4 bytes, y `cvtsi2sdl 0x100(%rbx),%xmm0; movsd %xmm0,0xf8(%rbx)` es
    # literalmente `curSelectedFloat = curSelected`.
    0xF8: "curSelectedFloat", 0x100: "curSelected", 0x104: "totalDiffs",
    0x110: "currentDifficulty", 0x118: "currentDiffsIds", 0x120: "songs",
    0x128: "freeplayTweens", 0x130: "freeplayTimers", 0x138: "lerpCompletion",
    0x140: "intendedCompletion", 0x148: "lerpScore", 0x150: "intendedScore",
    0x154: "_prevDisplayedScore", 0x158: "_prevDisplayedCompletion",
    0x160: "mouseEvents", 0x168: "bgWall", 0x170: "bgBed", 0x178: "tvGlow",
    0x180: "shadowsOnBed", 0x188: "currentPlayer", 0x190: "currentGirlfriend",
    0x198: "currentPhone", 0x1A0: "helpButton", 0x1A8: "charactersButtons",
    0x1B0: "clearBoxSprite", 0x1B8: "completionText", 0x1C0: "freeplayScore",
    0x1C8: "tvIntroDone", 0x1D0: "tvNoiseBack", 0x1D8: "tvBackBG", 0x1E0: "tvSprite",
    0x1E8: "tvSpriteFlash", 0x1F0: "tvNoiseForward", 0x1F8: "tvBg", 0x200: "diskPlayer",
    0x208: "diskPlayerMask", 0x210: "albumRoll", 0x218: "highScoreSpr",
    0x220: "difficultyStars", 0x228: "bossfightSkull", 0x230: "bossSound",
    0x238: "grpDisks", 0x240: "selectableDisks", 0x248: "darkOverlay",
    0x250: "selectorsGroup", 0x258: "dotsGrp", 0x260: "songInfoCapsule",
    0x268: "infoBpmText", 0x270: "infoTitleText", 0x278: "infoDiffText",
    0x280: "currentFilteredSongs", 0x298: "oldThemeName", 0x2A8: "oldThemeLayerName",
    0x2B0: "layerSound", 0x2B8: "diffTween", 0x2C0: "_glowTargetTimer",
    0x2C8: "_glowFlickerTimer", 0x2D0: "_alphaTarget", 0x2D8: "allowInput",
    0x2E0: "spamTimer", 0x2E8: "spamming", 0x2F0: "scrollCooldown",
}

FIELD_TABLES = {"freeplay": FREEPLAY_FIELDS}

# Huecos de vtable ya identificados, desde el puntero del objeto (o sea vtable + 0x10).
# Acciones de funkin::input::Controls, de su __GetFields. Los 0x30..0x88 son las cuatro
# direcciones en sus cuatro formas (sostenida, P de pulsada, R de soltada).
CONTROLS = {
    0x30: "UI_UP", 0x38: "UI_LEFT", 0x40: "UI_RIGHT", 0x48: "UI_DOWN",
    0x90: "NOTE_UP", 0x98: "NOTE_LEFT", 0xA0: "NOTE_RIGHT", 0xA8: "NOTE_DOWN",
    0xF0: "MECHANIC", 0x108: "ACCEPT", 0x110: "BACK", 0x118: "PAUSE", 0x120: "RESET",
    0x128: "WINDOW_SCREENSHOT", 0x130: "WINDOW_FULLSCREEN", 0x138: "FREEPLAY_FAVORITE",
    0x140: "FREEPLAY_LEFT", 0x148: "FREEPLAY_RIGHT", 0x150: "CUTSCENE_ADVANCE",
    0x158: "DEBUG_MENU", 0x160: "DEBUG_CHART", 0x168: "DEBUG_STAGE",
}

VTABLE = {
    0x100: "destroy", 0x118: "point.set_x", 0x120: "point.set_y", 0x128: "set_visible",
    0x188: "add", 0x210: "set_x", 0x218: "set_y", 0x230: "get_width",
    0x238: "get_height", 0x250: "set_moves", 0x2B0: "setGraphicSize",
    0x2B8: "updateHitbox", 0x370: "refresh", 0x388: "changePresence",
    0x3A8: "set_alpha", 0x3B0: "set_color", 0x3C8: "set_clipRect", 0x440: "initHitbox",
    0x448: "loadTexture", 0x4F8: "makeGraphic",
}

# FunkinAction: check() es VIRTUAL y checkPressed()/checkJustPressed() son llamadas
# directas, asi que buscar solo por nombre se deja tres condiciones fuera. En freeplay,
# ACCEPT, BACK y DEBUG_CHART se leen las tres por este hueco.
FUNKIN_ACTION_CHECK = 0x100

SKIP_CALLS = ("operator->", "StackFrame", "popFrame", "NullReference", "ObjectPtr",
              "pthread", "stack_chk", "__ToInt", "Dynamic::Dynamic")


def sections():
    out = subprocess.run(["readelf", "-S", "-W", str(BINARY)],
                         capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("["):
            continue
        parts = line.split("]", 1)[1].split()
        try:
            found.append((int(parts[2], 16), int(parts[3], 16), int(parts[4], 16)))
        except (IndexError, ValueError):
            pass
    return found


class Reader:
    def __init__(self):
        self.sections = sections()
        self.file = open(BINARY, "rb")

    def at(self, va):
        """Una cadena o un double en esa direccion, si parece uno u otro."""
        for addr, off, size in self.sections:
            if addr and addr <= va < addr + size:
                self.file.seek(off + va - addr)
                raw = self.file.read(48)
                text = raw.split(b"\0")[0]
                if 1 <= len(text) <= 44 and all(32 <= c < 127 for c in text):
                    return "'%s'" % text.decode()
                value = struct.unpack("<d", raw[:8])[0]
                # Los punteros leidos como double salen absurdos; los reales no.
                if value == value and 1e-6 < abs(value) < 1e8 or value == 0.0:
                    return "%g" % value
                return None
        return None


def resolve(name):
    """Direccion y tamano de un simbolo por nombre parcial."""
    out = subprocess.run(["nm", "-C", "--defined-only", "--print-size", str(BINARY)],
                         capture_output=True, text=True).stdout
    # Empareja el nombre EXACTO del metodo: `build` es subcadena de `buildBg`, y sin esto
    # pedir uno devuelve el otro sin decir nada. Se acepta "Clase::metodo" o "metodo".
    want = name.split("::")[-1]
    hits = []
    for line in out.splitlines():
        parts = line.split(" ", 3)
        if len(parts) < 4 or name not in parts[3]:
            continue
        symbol = parts[3].split("(")[0]
        if symbol.split("::")[-1] != want:
            continue
        if "_dyn" in parts[3] or "[clone .cold]" in parts[3]:
            continue
        try:
            hits.append((int(parts[0], 16), int(parts[1], 16), parts[3].strip()))
        except ValueError:
            pass
    if not hits:
        sys.exit("ningun simbolo contiene %r" % name)
    # El mod y el juego base declaran los mismos nombres de metodo. Auditamos el mod,
    # asi que `animania::` gana siempre; a igualdad, el simbolo mas grande.
    hits.sort(key=lambda h: (not h[2].startswith("animania::"), -h[1]))
    if len(hits) > 1:
        print("# %d simbolos coinciden, se usa el primero:" % len(hits), file=sys.stderr)
        for addr, size, sym in hits[:5]:
            print("#   0x%x  %6d  %s" % (addr, size, sym[:90]), file=sys.stderr)
    return hits[0][0], hits[0][1]


def dump(start, stop, fields, reader):
    asm = subprocess.run(
        ["objdump", "-d", "--start-address=%d" % start, "--stop-address=%d" % stop,
         "-C", str(BINARY)], capture_output=True, text=True).stdout

    current, parts = None, []
    # Registros que ahora mismo llevan un puntero de vtable. Ver mas abajo.
    vt_regs: set = set()
    for line in asm.splitlines():
        # El marcador de linea: a -0x40(%rbp) o a un hueco de %rsp, segun el prologo.
        mark = re.search(r"movl\s+\$0x([0-9a-f]+),(?:-0x40\(%rbp\)|0x[0-9a-f]+\(%rsp\))",
                         line)
        if mark and 0x100 < int(mark.group(1), 16) < 0x10000:
            if current is not None and parts:
                print("%-6d %s" % (current, "  ".join(parts)))
            current, parts = int(mark.group(1), 16), []
            continue
        if current is None:
            continue

        # Ojo con la base: `mov %rax,0x1f0(%rsp)` es un hueco de pila, no un campo, y
        # colarlo en la tabla saca nombres de campo que no estan en juego.
        store = re.search(r"mov\s+%rax,0x([0-9a-f]+)\((%r\w+)\)", line)
        if store and store.group(2) in ("%rsp", "%rbp"):
            store = None
        if store:
            off = int(store.group(1), 16)
            if off in fields:
                parts.append("=>" + fields[off])
            elif fields and 0xE0 <= off <= 0x300:
                parts.append("=>0x%x" % off)

        # `mov (%rX),%rY` saca el puntero de vtable de un objeto. Lo que se lea DESPUES
        # con ese registro como base es un hueco de vtable, no un campo, y confundir las
        # dos cosas es grave: los huecos 0x188/0x190/0x198 caen justo encima de
        # shadowsOnBed/currentGirlfriend/currentPhone. Asi salio en su dia un
        # "changeTheme toca currentPhone" que era `call *0x198(vtable)`.
        vtload = re.search(r"mov\s+\((%r\w+)\),(%r\w+)$", line.split("\t")[-1].strip())
        if vtload:
            vt_regs.add(vtload.group(2))
            continue
        # Las LECTURAS de campo son la otra mitad: sin ellas se ve que algo se hace
        # visible pero no que cosa. Se filtran las repetidas dentro de la misma linea.
        load = re.search(r"mov\s+0x([0-9a-f]+)\((%r\w+)\),%r\w+", line)
        if load and load.group(2) in ("%rsp", "%rbp"):
            load = None
        if load:
            off = int(load.group(1), 16)
            if load.group(2) in vt_regs:
                parts.append(VTABLE.get(off, "vt+0x%x" % off))
            elif off in fields:
                tag = "." + fields[off]
                if tag not in parts:
                    parts.append(tag)

        # El borrado va DESPUES de leer, no antes: `mov 0x198(%rax),%rax` lee por el
        # vtable y de paso pisa el registro, asi que descartarlo primero deshacia el
        # arreglo entero. Una llamada se lleva por delante los de guarda del llamante.
        if re.search(r"call\s", line):
            vt_regs.clear()
        else:
            dest = line.split("\t")[-1].strip()
            if "," in dest:
                vt_regs.discard(dest.rsplit(",", 1)[1].strip())

        z = re.search(r"movl\s+\$0x([0-9a-f]+),0x28\(%rax\)", line)
        if z:
            parts.append("z=%d" % int(z.group(1), 16))

        esi = re.search(r"mov\s+\$0x([0-9a-f]+),%esi", line)
        if esi:
            value = int(esi.group(1), 16)
            parts.append("esi=%d" % (value if value < 0x80000000 else value - (1 << 32)))
        if re.search(r"xor\s+%esi,%esi", line):
            parts.append("esi=0")

        colour = re.search(r"movabs\s+\$0x([0-9a-f]{9,16}),", line)
        if colour:
            parts.append("col=0x%08x" % (int(colour.group(1), 16) >> 32))

        indirect = re.search(r"call\s+\*0x([0-9a-f]+)\(%rax\)", line)
        if indirect:
            off = int(indirect.group(1), 16)
            parts.append(VTABLE.get(off, "vt+0x%x" % off))

        rip = re.search(r"(?:lea|mov|movsd)\s+0x[0-9a-f]+\(%rip\),%\w+\s+#\s*([0-9a-f]+)",
                        line)
        if rip:
            value = reader.at(int(rip.group(1), 16))
            if value:
                parts.append(value)

        call = re.search(r"call\s+[0-9a-f]+ <([^>]+)>", line)
        if call and not any(skip in call.group(1) for skip in SKIP_CALLS):
            parts.append("[" + call.group(1).split("(")[0].split("::")[-1] + "]")

    if current is not None and parts:
        print("%-6d %s" % (current, "  ".join(parts)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", help="nombre parcial de simbolo, o direccion inicial")
    parser.add_argument("stop", nargs="?", help="direccion final si target es una direccion")
    parser.add_argument("--fields", choices=sorted(FIELD_TABLES),
                        help="tabla de nombres de campo")
    args = parser.parse_args()

    if args.target.startswith("0x"):
        start = int(args.target, 16)
        stop = int(args.stop, 16) if args.stop else start + 0x1000
    else:
        start, size = resolve(args.target)
        stop = start + size
        print("# 0x%x .. 0x%x  (%d bytes)" % (start, stop, size), file=sys.stderr)

    dump(start, stop, FIELD_TABLES.get(args.fields, {}), Reader())


if __name__ == "__main__":
    main()
