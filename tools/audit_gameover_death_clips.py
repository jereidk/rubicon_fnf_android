#!/usr/bin/env python3
"""Fail if the gameover baker goes back to treating sub-clips as one cycle.

Chimera's deaths 1-3 were an AnimatedSprite2D of 13 frames driven by a
TYPE_ANIMATION track with three keys. The keys do NOT all name the same
animation:

    death_1_library/Final Exports_   at 6.21s   frames 0..8, the body opening
    death_1_library/loop             at 7.42s   frames 9..12, the ribcage
    death_1_library/loop             at 8.42s   frames 9..12 again

The first version of render_gameover_video.py read the key TIMES and threw
the names away, then assumed every key restarted the whole 13-frame set
spread evenly over 1.2 seconds:

    clip_len = 1.2
    idx = min(int(u / clip_len * len(sized)), len(sized) - 1)

So the baked video went back to frame 0 twice: the body closed up and was
opened again, three times over. It shipped that way, and it was reported from
the device as "the death video plays on a loop". The loop is real and is in
the original mod - but it is a FOUR frame loop of the ribcage, not the whole
sequence.

This guard has two halves, because either one alone can be satisfied by
accident:

  * the behaviour. library() and frame_at() are exercised against a fixture
    that mirrors death_N_library.tres, and "loop" must never yield a frame
    below 9 - at any offset, past its own length, and after a re-trigger.
  * the shape. build() must actually CALL frame_at(), checked through the
    AST rather than by searching the text, because this module's own
    docstring quotes the line it forbids and a textual search would find it
    there. That has caught out three guards in this repository already.

Run with:
    python3 tools/audit_gameover_death_clips.py
"""

import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BAKER = ROOT / "tools" / "render_gameover_video.py"

## Un recorte fiel de death_1_library.tres: las dos sub-animaciones tal cual,
## con sus interp/update, que es donde estaba la informacion que el tool tiraba.
FIXTURE = '''[gd_resource type="AnimationLibrary" format=3]

[sub_resource type="Animation" id="Animation_open"]
length = 1.2
step = 0.06666667
tracks/0/type = "value"
tracks/0/path = NodePath(".:animation")
tracks/0/interp = 0
tracks/0/keys = {
"times": PackedFloat32Array(0),
"update": 0,
"values": ["Final Exports_"]
}
tracks/1/type = "value"
tracks/1/path = NodePath(".:frame")
tracks/1/interp = 0
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.06666667, 0.13333334, 0.20000002, 0.26666668, 0.33333334, 0.40000004, 0.46666667, 0.53333336, 0.6, 0.6666667, 0.73333335, 0.8000001, 0.8666667, 0.9333334, 1, 1.0666667, 1.1333333),
"update": 0,
"values": [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8]
}

[sub_resource type="Animation" id="Animation_loop"]
resource_name = "loop"
loop_mode = 1
step = 0.083333336
tracks/0/type = "value"
tracks/0/path = NodePath(".:animation")
tracks/0/interp = 1
tracks/0/keys = {
"times": PackedFloat32Array(0),
"update": 1,
"values": [&"Final Exports_"]
}
tracks/1/type = "value"
tracks/1/path = NodePath(".:frame")
tracks/1/interp = 1
tracks/1/keys = {
"times": PackedFloat32Array(0, 0.083333336, 0.16666667, 0.25, 0.33333334, 0.4166667, 0.5, 0.5833334, 0.6666667, 0.75, 0.8333334, 0.9166667),
"update": 1,
"values": [9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 12]
}

[resource]
_data = {
&"Final Exports_": SubResource("Animation_open"),
&"loop": SubResource("Animation_loop")
}
'''

## Los fotogramas que cada sub-animacion PUEDE ensenar, y ninguno mas. Son la
## union de los valores de su propia pista, leidos del mod original.
OPENING_FRAMES = set(range(0, 9))
LOOP_FRAMES = {9, 10, 11, 12}


def load_baker(tmp_fixture: Path):
    spec = importlib.util.spec_from_file_location("gameover_baker", BAKER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # library() lee por res://, asi que el fixture se le pasa como una ruta
    # dentro del arbol y se borra despues.
    return module


def check_behaviour(baker, fixture_rel: str) -> list[str]:
    bad = []
    clips = baker.library(fixture_rel)

    for name in ("Final Exports_", "loop"):
        if name not in clips:
            bad.append("library() no encontro la sub-animacion %r" % name)
    if bad:
        return bad

    opening, loop = clips["Final Exports_"], clips["loop"]

    if not loop["loop"]:
        bad.append("la sub-animacion 'loop' se leyo como no ciclica")
    if abs(opening["length"] - 1.2) > 1e-6:
        bad.append("'Final Exports_' mide %.4fs, deberia medir 1.2s"
                   % opening["length"])
    if abs(loop["length"] - 1.0) > 1e-6:
        # Sin `length` escrito vale 1.0. death_2 y death_3 estan asi.
        bad.append("'loop' mide %.4fs, sin length escrito deberia medir 1.0s"
                   % loop["length"])

    # Un barrido denso, y bastante mas alla del final de cada clip: la escena
    # vuelve a disparar "loop" antes de que termine, pero nada garantiza que
    # siempre sea asi, y una animacion que no cicla se queda en su ultimo
    # valor en vez de apagarse.
    steps = [i / 240.0 for i in range(0, 241 * 3)]

    seen_open = {baker.frame_at(opening, u) for u in steps}
    if not seen_open <= OPENING_FRAMES:
        bad.append("'Final Exports_' enseno fotogramas fuera de 0..8: %s"
                   % sorted(seen_open - OPENING_FRAMES))
    if not OPENING_FRAMES <= seen_open:
        bad.append("'Final Exports_' nunca enseno %s"
                   % sorted(OPENING_FRAMES - seen_open))

    seen_loop = {baker.frame_at(loop, u) for u in steps}
    if not seen_loop <= LOOP_FRAMES:
        # ESTE es el fallo que se envio: el 0 aqui es el cuerpo cerrandose.
        bad.append("'loop' enseno fotogramas fuera de 9..12: %s - eso es la "
                   "secuencia entera reiniciandose, que es el bug de origen"
                   % sorted(seen_loop - LOOP_FRAMES))
    if not LOOP_FRAMES <= seen_loop:
        bad.append("'loop' nunca enseno %s" % sorted(LOOP_FRAMES - seen_loop))

    # El orden dentro de una vuelta, no solo el conjunto. El rango es abierto
    # por arriba a proposito: en u = 1.0 exacto el ciclo YA ha dado la vuelta
    # y vuelve al 9, que es lo correcto, no un quinto tramo.
    walk = [baker.frame_at(loop, i / 240.0) for i in range(0, 240)]
    runs = [f for i, f in enumerate(walk) if i == 0 or f != walk[i - 1]]
    if runs != [9, 10, 11, 12]:
        bad.append("una vuelta de 'loop' da %s, deberia dar [9, 10, 11, 12]"
                   % runs)

    return bad


def check_shape() -> list[str]:
    """Que build() llame de verdad a frame_at(), leido del AST.

    Por texto no vale: el docstring de este mismo fichero cita la linea que
    prohibe, y buscarla a pelo la encuentra aqui dentro.
    """
    bad = []
    tree = ast.parse(BAKER.read_text(encoding="utf-8"))
    build = next((n for n in ast.walk(tree)
                  if isinstance(n, ast.FunctionDef) and n.name == "build"), None)
    if build is None:
        return ["render_gameover_video.py ya no tiene build()"]

    called = {n.func.id for n in ast.walk(build)
              if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
    for wanted in ("frame_at", "library"):
        if wanted not in called:
            bad.append("build() no llama a %s() - esta eligiendo el fotograma "
                       "por su cuenta otra vez" % wanted)

    assigned = {t.id for n in ast.walk(build) if isinstance(n, ast.Assign)
                for t in n.targets if isinstance(t, ast.Name)}
    if "clip_len" in assigned:
        bad.append("build() vuelve a tener clip_len: eso es suponer que todas "
                   "las claves son la misma animacion repartida por igual")

    return bad


def main() -> int:
    fixture_rel = "tools/_death_library_fixture.tres"
    fixture = ROOT / fixture_rel
    fixture.write_text(FIXTURE, encoding="utf-8")
    try:
        baker = load_baker(fixture)
        bad = check_behaviour(baker, fixture_rel) + check_shape()
    finally:
        fixture.unlink(missing_ok=True)

    if bad:
        print("el horneado de las muertes volvio a perder los sub-clips:")
        for line in bad:
            print("  - " + line)
        return 1
    print("todo OK - 'Final Exports_' da 0..8 y 'loop' da 9..12 y nada mas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
