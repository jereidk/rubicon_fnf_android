#!/usr/bin/env python3
"""Cuelga el `MenuVirtualPad` de cada escena de menu, editando el .tscn A MANO.

Mismo motivo que en add_difficulty_node.py y conviene repetirlo porque cuesta un dia
entenderlo: `instantiate()` seguido de `pack()` NO es la identidad. Los nodos que vienen de
una sub-escena instanciada pierden sus sobrescrituras al reempaquetar, y aqui hay escenas
-el freeplay sin ir mas lejos- construidas justo asi. Se toca el texto y nada mas.

Lo que lleva cada pantalla va por pantalla y no es capricho: sale de que teclas LEE ese
menu, y los nombres son los del enum de FlxVirtualPad de Indie Cross para poder compararlos
de un vistazo con lo que hace alli la pantalla equivalente. Un boton que no hace nada
estorba mas que ayuda.

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
# La escena -> (cruz, acciones), y por que. Entre parentesis, lo que usa Indie Cross en la
# pantalla equivalente, que casi siempre coincide.
LAYOUTS = {
    # Semanas arriba y abajo, dificultad a los lados. (alli: LEFT_FULL, A_B_C)
    "animania_mod/menus/story/story_menu.tscn": ("LEFT_FULL", "A_B"),
    # Las filas se mueven con ui_up/ui_down y el VALOR de cada una con ui_left/ui_right
    # -base_sub_menu 68-84-, asi que aqui hacen falta las cuatro. (alli: LEFT_FULL, A_B_C)
    "animania_mod/menus/options/options_screen.tscn": ("LEFT_FULL", "A_B"),
    # Los creditos son UNA lista: la 490 lee izquierda Y arriba para lo mismo, y la 492
    # derecha Y abajo. Con arriba y abajo se recorre entera, asi que las de los lados
    # sobran. (alli directamente: NONE, A_B_C)
    "animania_mod/menus/credits/credits_menu.tscn": ("UP_DOWN", "A_B"),
    # Lista vertical y ya. (alli: UP_DOWN, A_B, igual)
    "animania_mod/menus/pause/pause_menu.tscn": ("UP_DOWN", "A_B"),
}


def patch(path: Path, modes: tuple) -> str:
    text = path.read_text(encoding="utf-8")
    props = 'dpad = "%s"\naction = "%s"\n' % modes
    if NAME in text:
        # Ya esta puesto: se le REESCRIBEN las propiedades en vez de dejarlo como estaba.
        # Si no, cambiar aqui la cruz de una pantalla no cambiaba nada y el script mentia
        # con un "ya lo tenia" mientras la escena seguia con lo de antes.
        head = re.search(r'^\[node name="%s".*\]\n' % NAME, text, re.M)
        if head is None:
            return "FALLO el nodo esta pero no se encuentra"
        rest = text[head.end():]
        body = re.match(r'(?:[a-z_]+ = .*\n)*', rest).group(0)
        if body == props:
            return "ya estaba al dia"
        text = text[:head.end()] + props + rest[len(body):]
        path.write_text(text, encoding="utf-8")
        return "actualizado (%s/%s)" % modes

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
    node = ('\n[node name="%s" parent="." instance=ExtResource("%s")]\n%s'
            % (NAME, RES_ID, props))
    first = re.search(r'^\[editable path=', text, re.M)
    if first is not None:
        text = text[:first.start()] + node.lstrip("\n") + "\n" + text[first.start():]
    else:
        text += node
    path.write_text(text, encoding="utf-8")
    return "anadido (%s/%s)" % modes


def main() -> int:
    args = sys.argv[1:]
    targets = [Path(a) for a in args] if args else [Path(p) for p in LAYOUTS]
    for path in targets:
        modes = LAYOUTS.get(str(path), ("UP_DOWN", "A_B"))
        print("OUT %-22s %s" % (patch(path, modes), path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
