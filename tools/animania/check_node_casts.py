#!/usr/bin/env python3
"""Comprueba que cada `get_node_or_null("X") as T` del script casa con el tipo real de X.

Este fallo ya ha salido siete veces en el puerto y siempre igual de callado: en GDScript,
`nodo as Tipo` con un tipo que no cuadra NO da error, devuelve null. Y como todo el codigo
que lo usa esta detras de un `if x != null`, la funcion entera desaparece sin una sola
linea en la consola. Asi se perdieron `disk_player`, `disk_player_mask`, `tv_back_bg`, y
asi se perdio el destello blanco del encendido: `TvSpriteFlash` es un ColorRect y el script
lo pedia como Sprite2D.

    python3 tools/animania/check_node_casts.py [escena.tscn ...]

Sin argumentos mira las parejas .gd/.tscn del mod que compartan nombre.
"""

import re
import sys
from pathlib import Path

# Lo que un nodo del tipo <clave> puede aceptar como casteo, además de su propio nombre.
BASES = {
    "Sprite2D": ["Node2D", "CanvasItem", "Node"],
    "AnimatedSprite2D": ["Node2D", "CanvasItem", "Node"],
    "Node2D": ["CanvasItem", "Node"],
    "ColorRect": ["Control", "CanvasItem", "Node"],
    "Label": ["Control", "CanvasItem", "Node"],
    "Control": ["CanvasItem", "Node"],
    "AudioStreamPlayer": ["Node"],
    "AnimationPlayer": ["Node"],
    "Node": [],
    "CanvasLayer": ["Node"],
    "Camera2D": ["Node2D", "CanvasItem", "Node"],
}

CAST = re.compile(r'get_node_or_null\(\s*"([^"]+)"\s*\)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)')
NODE = re.compile(
    r'^\[node name="([^"]+)" type="([^"]+)"(?: parent="([^"]+)")?[^\]]*\]\n((?:(?!\[)[^\n]*\n)*)',
    re.M)


def scene_types(path: Path) -> dict:
    out = {}
    for name, kind, parent, body in NODE.findall(path.read_text(encoding="utf-8")):
        # Un nodo con `script =` es de una clase propia -AnimateSymbol y compania-, y el
        # .tscn solo guarda la clase base. No se puede decir nada de su casteo, asi que se
        # deja pasar en vez de dar un falso positivo.
        if re.search(r'^script = ', body, re.M):
            kind = None
        key = name if parent in (None, "", ".") else "%s/%s" % (parent, name)
        out[key] = kind
    return out


def check(script: Path, scene: Path) -> int:
    types = scene_types(scene)
    bad = 0
    for i, line in enumerate(script.read_text(encoding="utf-8").splitlines(), 1):
        for node, wanted in CAST.findall(line):
            if node in types and types[node] is None:
                continue
            real = types.get(node)
            if real is None:
                print("OUT %s:%d  %-24s NO EXISTE en %s" % (script.name, i, node, scene.name))
                bad += 1
            elif wanted != real and wanted not in BASES.get(real, []):
                print("OUT %s:%d  %-24s es %s, se pide %s -> null"
                      % (script.name, i, node, real, wanted))
                bad += 1
    return bad


def main() -> int:
    if len(sys.argv) > 1:
        pairs = [(Path(a).with_suffix(".gd"), Path(a)) for a in sys.argv[1:]]
    else:
        pairs = [(p.with_suffix(".gd"), p)
                 for p in sorted(Path("animania_mod").rglob("*.tscn"))
                 if p.with_suffix(".gd").exists()]
    bad = 0
    for script, scene in pairs:
        bad += check(script, scene)
    print("OUT %d casteos que devuelven null" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
