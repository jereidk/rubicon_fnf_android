#!/usr/bin/env python3
"""The results screen's full-screen layers must idle at the alpha `show` starts from.

LullabyResultsScreen sits on a CanvasLayer at layer 65 - above everything -
and it is in the tree for the whole song, not spawned at the end. Two of its
children cover the entire screen: FadingColor, a ColorRect, and Vingette, a
TextureRect holding a radial GradientTexture2D whose alpha runs 0.0 at the
centre to 0.588 at the edge.

Its `show` animation, the only thing that presents the screen, starts both of
them fully transparent and ramps them up over 0.583s. So the state before
`show` runs is unambiguous: transparent. FadingColor was authored that way.
Vingette was not - it had no modulate line at all, which means white at full
alpha, so every song was played under a vignette darkening the edges by up to
58.8%, on top of a full-screen textured blend on every frame.

That is the same shape of bug as the render mode this screen already had
fixed: the screen is present all song and something about it was left in its
end-of-song state. The author's intent is not in doubt in either case - the
animation says what the idle value is.

Run with:
    python3 tools/audit_results_screen_idle.py
"""

import re
import sys
from pathlib import Path

SCENE = Path("lullaby_mod/resources/funkin/ui/results/lullaby_results_screen.tscn")

# node name -> the property `show` animates it through
WATCHED = {
    "Vingette": "modulate",
    "FadingColor": "color",
}

COLOR = re.compile(r"Color\(([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+)\)")


def authored_alpha(text: str, node: str, prop: str) -> float | None:
    """The alpha the scene gives this node's property, or None if absent."""
    block = re.search(
        r'^\[node name="%s"[^\]]*\]\n((?:(?!\n\[).)*)' % re.escape(node),
        text, re.M | re.S)
    if block is None:
        return None
    line = re.search(r"^%s = (Color\([^)]*\))" % re.escape(prop), block.group(1), re.M)
    if line is None:
        # No line means the engine default: opaque white for modulate, and for
        # a ColorRect's colour, opaque white too.
        return 1.0
    return float(COLOR.search(line.group(1)).group(4))


def show_start_alpha(text: str, node: str, prop: str) -> float | None:
    """The alpha `show`'s first key gives it."""
    for block in re.split(r"\n(?=\[)", text):
        head = block.split("\n", 1)[0]
        if not head.startswith('[sub_resource type="Animation"'):
            continue
        name = re.search(r'^resource_name = "([^"]*)"', block, re.M)
        if name is None or name.group(1) != "show":
            continue
        for track in re.finditer(
                r'^tracks/(\d+)/path = NodePath\("%s:%s"\)' % (re.escape(node), re.escape(prop)),
                block, re.M):
            keys = re.search(r"^tracks/%s/keys = \{(.*?)\n\}" % track.group(1),
                             block, re.M | re.S)
            if keys is None:
                continue
            values = re.search(r'"values": \[(.*?)\]', keys.group(1), re.S)
            if values is None:
                continue
            first = COLOR.search(values.group(1))
            if first is not None:
                return float(first.group(4))
    return None


def main() -> int:
    if not SCENE.exists():
        print(f"{SCENE}: no existe")
        return 1

    text = SCENE.read_text(encoding="utf-8", errors="replace")
    bad = 0
    for node, prop in WATCHED.items():
        authored = authored_alpha(text, node, prop)
        start = show_start_alpha(text, node, prop)
        if authored is None:
            print(f"{node}: no esta en la escena")
            bad += 1
            continue
        if start is None:
            print(f"{node}: la animacion 'show' ya no toca {prop} - revisa este audit")
            bad += 1
            continue
        ok = abs(authored - start) < 0.001
        print("%-14s %-9s autorado alpha=%.2f  show empieza en %.2f  %s"
              % (node, prop, authored, start, "ok" if ok else "NO COINCIDE"))
        if not ok:
            bad += 1
            print("    Se dibuja a pantalla completa durante toda la cancion en un "
                  "CanvasLayer 65. Si 'show' arranca transparente, el estado en "
                  "reposo es transparente.")

    if bad:
        print(f"\n{bad} capa(s) en reposo con el alpha equivocado")
        return 1
    print("\ntodo OK - la pantalla de resultados no pinta nada mientras no toca")
    return 0


if __name__ == "__main__":
    sys.exit(main())
