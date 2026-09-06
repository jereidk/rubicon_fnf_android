#!/usr/bin/env python3
"""Cuelga el nodo `DifficultyCharts` de cada escena de cancion, editando el .tscn A MANO.

La primera version de esto lo hacia bien: cargaba la escena, le anadia el nodo y la volvia
a empaquetar con PackedScene.pack(). Y se comia la escena. Un `instantiate()` seguido de un
`pack()` NO es la identidad: los nodos que vienen de una sub-escena instanciada pierden sus
sobrescrituras y `bopeebo.tscn` paso de 330 lineas a 102 sin dar un solo error. Un builder
que reescribe lo que no entiende es peor que no tener builder.

Asi que aqui se toca el texto y nada mas: una linea de `ext_resource` detras de la cabecera
y un bloque de nodo al final. Lo que ya estaba no se lee, no se interpreta y no se vuelve a
escribir.

    python3 tools/animania/add_difficulty_node.py [ruta.tscn ...]
"""

import re
import sys
from pathlib import Path

SCRIPT = "res://animania_mod/songs/difficulty_charts.gd"
NAME = "DifficultyCharts"
# Un id que no puede chocar con los que genera Godot, que son "<n>_<5 chars>".
RES_ID = "difficulty_charts"


def patch(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if NAME in text:
        return "ya lo tenia"

    ext = '[ext_resource type="Script" path="%s" id="%s"]\n' % (SCRIPT, RES_ID)
    # Detras del ultimo ext_resource si los hay; si no, detras de la cabecera.
    last = None
    for m in re.finditer(r'^\[ext_resource .*\]\n', text, re.M):
        last = m
    if last is not None:
        text = text[:last.end()] + ext + text[last.end():]
    else:
        head = re.search(r'^\[gd_scene[^\]]*\]\n', text, re.M)
        if head is None:
            return "FALLO sin cabecera gd_scene"
        text = text[:head.end()] + "\n" + ext + text[head.end():]

    if not text.endswith("\n"):
        text += "\n"
    node = '\n[node name="%s" type="Node" parent="."]\nscript = ExtResource("%s")\n' % (
        NAME, RES_ID)
    # Los `[editable path=...]` van SIEMPRE al final del fichero, detras del ultimo nodo, y
    # asi es como Godot lo reescribe. Meter el nodo despues de ellos carga igual, pero deja
    # el .tscn con una forma que el editor no genera nunca; se pone justo antes.
    first = re.search(r'^\[editable path=', text, re.M)
    if first is not None:
        text = text[:first.start()] + node.lstrip("\n") + "\n" + text[first.start():]
    else:
        text += node
    path.write_text(text, encoding="utf-8")
    return "anadido"


def main() -> int:
    args = sys.argv[1:]
    if args:
        targets = [Path(a) for a in args]
    else:
        targets = sorted(Path("songs").glob("*/*.tscn"))
    for path in targets:
        print("OUT %-14s %s" % (patch(path), path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
