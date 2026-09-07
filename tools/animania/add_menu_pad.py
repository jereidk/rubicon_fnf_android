#!/usr/bin/env python3
"""Cuelga el `MenuVirtualPad` de cada escena de menu, editando el .tscn A MANO.

Mismo motivo que en add_difficulty_node.py y conviene repetirlo porque cuesta un dia
entenderlo: `instantiate()` seguido de `pack()` NO es la identidad. Los nodos que vienen de
una sub-escena instanciada pierden sus sobrescrituras al reempaquetar, y aqui hay escenas
-el freeplay sin ir mas lejos- construidas justo asi. Se toca el texto y nada mas.

El `layout` va por pantalla y no es capricho: sale de que teclas lee cada menu.
`Full` -con izquierda y derecha- para las que las usan de verdad, `Vertical` para las que
son una lista de arriba a abajo. Un boton que no hace nada estorba mas que ayuda.

    python3 tools/animania/add_menu_pad.py [ruta.tscn ...]
"""

import re
import sys
from pathlib import Path

PAD = "res://animania_mod/ui/menu_virtual_pad.tscn"
NAME = "MenuVirtualPad"
RES_ID = "menu_virtual_pad"

# El menu PRINCIPAL tampoco esta, y no por olvido: esa pantalla esta pensada para tocarla.
# Sus ocho placas son rectangulos con su `_touch` y el disco de la OST tambien; ponerle
# encima un mando de flechas es repetir con botones lo que la pantalla ya hace mejor, y
# ademas taparle una esquina del arte. Donde hace falta el mando es donde no hay nada que
# tocar.
#
# El freeplay NO esta aqui a proposito: su escena la GENERA build_freeplay_scene.gd, y un
# builder que no conoce un nodo lo borra en la siguiente pasada. Su mando se monta alli,
# junto al resto de la pantalla.
#
# La escena -> el layout, y por que.
LAYOUTS = {
    # La fila de semanas.
    "animania_mod/menus/story/story_menu.tscn": "Full",
    # Las paginas de creditos.
    "animania_mod/menus/credits/credits_menu.tscn": "Full",
    # Las opciones mueven el VALOR con izquierda y derecha -base_sub_menu 82-84, por accion
    # `ui_left`/`ui_right` y no por keycode, que tambien le llega la tecla sintetica-.
    "animania_mod/menus/options/options_screen.tscn": "Full",
    # Lista vertical y ya: aqui no hay nada a los lados.
    "animania_mod/menus/pause/pause_menu.tscn": "Vertical",
}


def patch(path: Path, layout: str) -> str:
    text = path.read_text(encoding="utf-8")
    if NAME in text:
        return "ya lo tenia"

    ext = '[ext_resource type="PackedScene" path="%s" id="%s"]\n' % (PAD, RES_ID)
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
    node = ('\n[node name="%s" parent="." instance=ExtResource("%s")]\nlayout = "%s"\n'
            % (NAME, RES_ID, layout))
    first = re.search(r'^\[editable path=', text, re.M)
    if first is not None:
        text = text[:first.start()] + node.lstrip("\n") + "\n" + text[first.start():]
    else:
        text += node
    path.write_text(text, encoding="utf-8")
    return "anadido (%s)" % layout


def main() -> int:
    args = sys.argv[1:]
    targets = [Path(a) for a in args] if args else [Path(p) for p in LAYOUTS]
    for path in targets:
        layout = LAYOUTS.get(str(path), "Vertical")
        print("OUT %-18s %s" % (patch(path, layout), path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
