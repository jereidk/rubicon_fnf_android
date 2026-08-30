#!/usr/bin/env python3
"""Repara los bloques de animación de step_1..3, que quedaron malformados.

Lo que pasó, y es mío: al hornear las muertes 1-3 a vídeo (b6a447e) quité las
pistas del AnimatedSprite2D borrando las líneas que empiezan por `tracks/N/`.
El cuerpo de una pista NO empieza por eso - `tracks/N/keys = {` abre un bloque
multilínea de "times"/"values"/"clips" que sigue hasta un `}` suelto - así que
las cabeceras se fueron y los cuerpos se quedaron, pegados a la pista siguiente:

    tracks/0/keys = {
    tracks/0/use_blend = true          <- el bloque de keys quedó vacío y abierto

El resultado no es una animación rara, es un .tscn que NO PARSEA:

    step_1.tscn:39 - Parse Error: Unexpected identifier 'tracks'.
    Failed loading resource: res://lullaby_mod/songs/chimera/scenes/step_1.tscn.

O sea que morir en Chimera en los steps 1, 2 o 3 no llevaba a ninguna parte. Se
vio en el log del dispositivo, no en CI: la guarda leía las escenas como TEXTO
-FileAccess.get_file_as_string- y un fichero que no parsea se lee igual de bien
que uno que sí. Por eso ahora la guarda las carga de verdad.

El mismo fallo se arregló después para la cutscene de closeup y para step_4,
cuando volvió a aparecer. Estas tres se quedaron atrás porque fueron antes.

La reparación no reescribe a mano lo roto: coge el bloque de animación del
commit ANTERIOR al horneado, le quita las pistas del AnimatedSprite2D con un
agrupado que sí entiende las llaves, renumera, y lo empalma en el fichero
actual - que ya tiene bien el nodo VideoPlayer y los ext_resource podados.

Uso:
    python3 tools/repair_step_animations.py            # lee los originales de git
    python3 tools/repair_step_animations.py --dry-run
"""

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEFORE = "b6a447e^"
STEPS = [1, 2, 3]
DEAD = "AnimatedSprite2D"


def split_tracks(block):
    """(cabecera, [pista, ...]) entendiendo los bloques `keys = {`.

    Una pista son sus líneas `tracks/N/...` MÁS el cuerpo multilínea que abre
    `keys = {` y cierra un `}` suelto. `use_blend` viene DESPUÉS de ese cierre y
    también es suya, así que se recoge por prefijo como el resto.
    """
    head, groups, order = [], {}, []
    cur, in_keys = None, False
    for line in block.split("\n"):
        m = re.match(r'tracks/(\d+)/', line)
        if m and not in_keys:
            cur = int(m.group(1))
            if cur not in groups:
                groups[cur] = []
                order.append(cur)
            groups[cur].append(line)
            in_keys = line.rstrip().endswith("{")
            continue
        if in_keys and cur is not None:
            groups[cur].append(line)
            if line.strip() == "}":
                in_keys = False
            continue
        head.append(line)
    return head, [groups[i] for i in order]


def animation_blocks(text):
    """{id: (inicio, fin, cuerpo)} de cada sub_resource de tipo Animation.

    Por ID y no por `resource_name`: la animación RESET no lleva esa línea, así
    que buscarla por nombre la dejaba fuera - y estaba rota exactamente igual,
    con el cuerpo de su segunda pista huérfano detrás de la primera. La primera
    versión de esta reparación arregló `animation` en los tres steps, movió el
    error de la línea 39 a la 63, y los tres siguieron sin cargar.
    """
    out = {}
    for m in re.finditer(r'(?m)^\[sub_resource type="Animation" id="([^"]+)"\]\n', text):
        end = text.find("\n[", m.end())
        end = end + 1 if end > 0 else len(text)
        out[m.group(1)] = (m.start(), end, text[m.start():end])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for step in STEPS:
        rel = "lullaby_mod/songs/chimera/scenes/step_%d.tscn" % step
        path = os.path.join(ROOT, rel)
        current = open(path, encoding="utf-8").read()

        original = subprocess.run(
            ["git", "show", "%s:%s" % (BEFORE, rel)],
            cwd=ROOT, capture_output=True, text=True, check=True).stdout

        src_blocks = animation_blocks(original)
        # De atrás hacia adelante, para que los offsets de los que quedan no se
        # muevan al reescribir.
        for aid in sorted(animation_blocks(current),
                          key=lambda k: animation_blocks(current)[k][0], reverse=True):
            dst = animation_blocks(current)[aid]
            src = src_blocks.get(aid)
            if src is None:
                continue

            head, tracks = split_tracks(src[2])
            keep = [t for t in tracks if DEAD not in "\n".join(t)]
            dropped = len(tracks) - len(keep)

            tail = 0
            while head and head[-1].strip() == "":
                head.pop()
                tail += 1

            lines = list(head)
            for i, tr in enumerate(keep):
                for l in tr:
                    lines.append(re.sub(r'^tracks/\d+/', 'tracks/%d/' % i, l))
            lines += [""] * tail

            rebuilt = "\n".join(lines)
            current = current[:dst[0]] + rebuilt + current[dst[1]:]
            print("  step_%d %-22s %d pistas -> %d (%d fuera)"
                  % (step, aid, len(tracks), len(keep), dropped))

        if DEAD in current:
            sys.exit("step_%d: sigue quedando %s" % (step, DEAD))

        if not args.dry_run:
            open(path, "w", encoding="utf-8").write(current)

    print("(dry-run, no se escribe)" if args.dry_run else "escrito")


if __name__ == "__main__":
    main()
