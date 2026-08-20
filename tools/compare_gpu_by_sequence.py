#!/usr/bin/env python3
"""Compare two device logs shot by shot, so a graphics A/B can actually be read.

Every previous attempt at "does this setting help" in this project compared one
run's average against another's, and every one of them was uninterpretable. Two
reasons, both of which this pairs around.

**Chimera is not uniformly slow; four or five shots are.** In
`10152-665dedd4` the same song runs 14.8ms in `113_reaching` and 48.7ms in
`104_photographysesh` - a 3.3x spread within one playthrough. An average over
that is dominated by how long the player lingered in each section, so two runs
of the same build differ by more than most settings do. Pairing by `seq=` name
compares the same shot against itself, which is the only comparison that means
anything.

**The device changes underneath you.** Android's touch-boost governor drops the
clocks when nobody is touching the screen, and thermal throttling drops them
across a session; `SUMMARY vs_first` cannot tell either from a scene that got
heavier. `bench=` exists for exactly this - fixed arithmetic, timed - and this
reports it first, before any gpu number, because if `bench` moved by the same
factor as `gpu` then the device changed and the scene did not. In the log this
was written against, `bench` spans 187us to 960us *within one session*, so this
is not a theoretical caveat.

Two smaller things it has to get right:

- **Read the applied render scale, not the requested one.** `scale=` is what
  the setting asked for and `vp=[mode5@0.50 ...]` is what the viewport actually
  uses; 186e17f exists because those disagreed. The expected pixel ratio is
  computed from `vp=`.
- **Keep `(parado)` out of the comparison.** It is the precache and the
  loading screen, not gameplay, and it is where the most expensive frames of
  the whole session live.

Usage:
    python3 tools/compare_gpu_by_sequence.py A.log B.log [--scene sng_chimera]
"""

import re
import statistics as st
import sys
from pathlib import Path

HEARTBEAT = re.compile(r"^\[ *([0-9.]+)s\] HEARTBEAT")
FIELDS = {
    "gpu": r" gpu=([\d.]+)ms",
    "cpu_render": r"cpu_render=([\d.]+)ms",
    "bench": r"bench=(\d+)us",
    "fps": r"fps_now=(\d+)",
    "median": r"median=([\d.]+)ms",
    "draw": r"draw=(\d+)",
    "prims": r"prims=(\d+)",
}
SEQ = re.compile(r"seq=(\S+)")
SCENE = re.compile(r"scene=(\S+)\s*$")
VP_SCALE = re.compile(r"vp=\[mode\d+@([\d.]+)")


class Run:
    def __init__(self, path: Path, scene_filter: str):
        self.path = path
        self.rows = []
        self.header = {}
        self.window = None
        self._read(scene_filter)

    def _read(self, scene_filter: str) -> None:
        for line in self.path.read_text(encoding="utf-8", errors="replace").splitlines():
            head = re.match(r"^(\w[\w ]*?)\s*: (.+)$", line)
            if head and not line.startswith("["):
                self.header.setdefault(head.group(1).strip(), head.group(2).strip())
            m = HEARTBEAT.match(line)
            if not m:
                continue
            scene = SCENE.search(line)
            if scene_filter and (not scene or scene_filter not in scene.group(1)):
                continue
            row = {"t": float(m.group(1))}
            for name, pattern in FIELDS.items():
                hit = re.search(pattern, line)
                row[name] = float(hit.group(1)) if hit else None
            seq = SEQ.search(line)
            # "122_fall@6.8s" -> "122_fall". The position within the sequence is
            # what makes a stall locatable, but for pairing it is noise: two runs
            # never land their heartbeats on the same second of a cutscene.
            row["seq"] = seq.group(1).split("@")[0] if seq else "-"
            vp = VP_SCALE.search(line)
            row["scale"] = float(vp.group(1)) if vp else None
            self.rows.append(row)
        win = re.search(r"\((\d+), (\d+)\)", self.header.get("window", ""))
        if win:
            self.window = (int(win.group(1)), int(win.group(2)))

    def scale(self):
        seen = [r["scale"] for r in self.rows if r["scale"] is not None]
        return st.median(seen) if seen else None

    def bench(self):
        seen = [r["bench"] for r in self.rows if r["bench"]]
        return st.median(seen) if seen else None

    def by_sequence(self):
        out = {}
        for r in self.rows:
            if r["seq"] in ("-", "(parado)") or r["gpu"] is None:
                continue
            out.setdefault(r["seq"], []).append(r["gpu"])
        return out

    def pixels(self):
        s = self.scale()
        if not s or not self.window:
            return None
        return round(self.window[0] * s) * round(self.window[1] * s)


def ratio(a, b):
    return (b / a) if a else float("nan")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    scene = "sng_chimera"
    for a in sys.argv[1:]:
        if a.startswith("--scene"):
            scene = a.split("=", 1)[1] if "=" in a else scene
    if len(args) != 2:
        print(__doc__)
        return 2

    a, b = Run(Path(args[0]), scene), Run(Path(args[1]), scene)
    if not a.rows or not b.rows:
        print("sin latidos de '%s' en %s" % (
            scene, args[0] if not a.rows else args[1]))
        return 1

    print("=" * 78)
    for label, run in (("A", a), ("B", b)):
        print("%s  %-34s  %s  %s  escala aplicada %.2f  %d latidos" % (
            label, run.path.name[-34:], run.header.get("version", "?"),
            run.header.get("template", "?"), run.scale() or 0.0, len(run.rows)))

    # First, and on its own, because every number below is worthless if it fails.
    print("\n--- control: ¿es el mismo telefono en las dos pasadas? ---")
    ba, bb = a.bench(), b.bench()
    if ba and bb:
        br = ratio(ba, bb)
        print("  bench   A=%dus  B=%dus  razon=%.2fx" % (ba, bb, br))
        if abs(br - 1.0) > 0.25:
            print("  AVISO: bench se movio %.0f%%. El gobernador o el termico cambiaron entre" % ((br - 1.0) * 100))
            print("         pasadas, asi que parte de cualquier diferencia de gpu es del telefono")
            print("         y no de la escena. Repite las dos seguidas y tocando la pantalla igual.")
        else:
            print("  ok: dentro del 25%, las dos pasadas son comparables")
    else:
        print("  bench ausente en algun log - sin control, lee lo de abajo con pinzas")

    pa, pb = a.pixels(), b.pixels()
    expected = ratio(pa, pb) if pa and pb else None
    if expected:
        print("\n--- pixeles 3D ---")
        print("  A=%.2f Mpx  B=%.2f Mpx  razon esperada si el coste fuera 100%% por pixel: %.2fx"
              % (pa / 1e6, pb / 1e6, expected))

    sa, sb = a.by_sequence(), b.by_sequence()
    shared = sorted(set(sa) & set(sb))
    print("\n--- gpu por secuencia (mediana) ---")
    if not shared:
        print("  ninguna secuencia en comun - ¿llegaron las dos pasadas al mismo tramo?")
        return 1
    print("  %-24s %5s %9s %9s %8s" % ("secuencia", "n", "A", "B", "B/A"))
    ratios = []
    for name in shared:
        ga, gb = st.median(sa[name]), st.median(sb[name])
        r = ratio(ga, gb)
        ratios.append(r)
        print("  %-24s %2d/%-2d %8.1fms %8.1fms %7.2fx" % (
            name, len(sa[name]), len(sb[name]), ga, gb, r))

    only = sorted((set(sa) | set(sb)) - (set(sa) & set(sb)))
    if only:
        print("\n  (solo en una pasada, no comparadas: %s)" % ", ".join(only))

    med = st.median(ratios)
    print("\n--- veredicto ---")
    print("  razon mediana observada: %.2fx" % med)

    # The degenerate case is not a rounding problem, it is the experiment not
    # having been run: with one scale in both logs the expected ratio is 1.00,
    # the share is 0/0, and every branch below reads as a finding. Say what
    # actually happened instead.
    if not expected:
        print("  sin escala aplicada legible en algun log - no se puede pronunciar")
        return 0
    if abs(expected - 1.0) < 0.05:
        print("  las dos pasadas corrieron a la MISMA escala (%.2f), asi que esto no es un A/B."
              % (a.scale() or 0.0))
        print("  Sirve como control - una razon lejos de 1.00x aqui mide el ruido del")
        print("  telefono entre pasadas, no un cambio de la escena.")
        return 0

    share = (med - 1.0) / (expected - 1.0)
    print("  razon esperada si todo fuera por pixel: %.2fx" % expected)
    print("  o sea que el coste por pixel explica ~%.0f%% del frame"
          % (max(0.0, min(1.0, share)) * 100))
    if share >= 0.6:
        print("  -> fill-rate. El siguiente paso son las luces por fragmento y el overdraw 3D.")
    elif share >= 0.25:
        print("  -> mitad por pixel, mitad fijo. La escala es una palanca real pero no la unica.")
    else:
        print("  -> NO es por pixel. El techo es geometria, estado o sincronizacion CPU-GPU,")
        print("     y todo lo escrito sobre fill-rate en CLAUDE.md hay que tacharlo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
