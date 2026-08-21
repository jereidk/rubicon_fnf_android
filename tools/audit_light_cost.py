#!/usr/bin/env python3
"""How many lights reach the average fragment, which is what a 3D pixel costs.

Forward Mobile has no deferred pass: every light that reaches a fragment is
evaluated in that fragment's shader. Measured on the phone's path (Vulkan,
Forward Mobile, 1600x720, one surface covering the whole screen, omnis whose
range covers all of it):

    luces   0     1     2     4     6      8     10     12
    gpu  14.6  32.7  54.6  80.5 108.6  134.8  134.0  134.3

**Zero lights is 14.6ms and eight is 134.8ms - 9x**, about 15ms per light per
full screen. So what makes a 3D pixel expensive is not its resolution, it is
how many lights land on it. `graphics_render_scale` is the emergency lever;
this is the one that decides whether scale 1.0 is reachable at all.

Two things that curve says and nothing in this repo said before:

  * **It saturates at 8.** Forward Mobile caps the lights applied per object,
    so a ninth costs nothing - and does not light the object either. A scene
    whose CENSUS reports more than 8 visible lights is both paying the maximum
    and silently dropping some. Chimera reports lights=10..13.

  * **`light_energy = 0` costs full price.** Eight lights at energy 0.35 and
    eight at 0.0 measured 135.8ms and 135.1ms - identical. The same eight
    hidden measured 16.3ms. A light that emits nothing still occupies a slot;
    only `visible = false` takes it out.

    python3 tools/audit_light_cost.py [file.tscn ...]

With no arguments it sweeps every .tscn in lullaby_mod/.

Scope, stated rather than implied: lights that live inside an instanced
sub-scene or a .gltf are invisible to a text sweep and are not counted, so the
per-point counts here are a **lower bound**. The CENSUS line's `lights=N` is
the runtime truth.
"""
import re, sys, glob, math

# Forward Mobile applies at most this many lights to one object.
SATURATION = 8

LIGHT_TYPES = ("OmniLight3D", "SpotLight3D", "AreaLight3D")


def blocks(text):
    for part in re.split(r"^\[node ", text, flags=re.M)[1:]:
        head, _, body = part.partition("\n")
        yield head, body.split("\n[")[0]


def prop(body, name):
    m = re.search(r"^%s = (.+)$" % re.escape(name), body, re.M)
    return m.group(1).strip() if m else None


def origin(body):
    """The translation of a Transform3D, which is its last three numbers."""
    raw = prop(body, "transform")
    if not raw:
        return (0.0, 0.0, 0.0)
    nums = [float(x) for x in re.findall(r"-?[\d.]+(?:e-?\d+)?", raw)]
    return tuple(nums[-3:]) if len(nums) >= 12 else (0.0, 0.0, 0.0)


def script_driven(text):
    """Light node names some script in this scene holds and writes energy on.

    A `light_energy` written from GDScript is invisible to a text sweep, and
    reporting one of those as dead is how this repo has been broken before.
    Both of the first run's shop findings were exactly that: `power_console.gd`
    drives the TV light between 0 and 0.241, and `mch_picturetaking.gd` drives
    the camera-flash spot. Only one of the three was real.
    """
    import os
    scripts = {}
    for m in re.finditer(r'\[ext_resource type="Script"[^\]]*path="([^"]*)"[^\]]*id="([^"]*)"\]', text):
        scripts[m.group(2)] = m.group(1)

    driven = set()
    for head, body in blocks(text):
        sid = re.search(r'script = ExtResource\("([^"]*)"\)', body)
        if not sid:
            continue
        local = (scripts.get(sid.group(1)) or "").replace("res://", "")
        if not local or not os.path.exists(local):
            continue
        source = open(local, encoding="utf-8", errors="replace").read()
        if "light_energy" not in source:
            continue
        # Every node this scripted node holds by NodePath is a candidate, and
        # so is a bare name - an @export NodePath is often written that way.
        for m in re.finditer(r'NodePath\("([^"]*)"\)', body):
            target = m.group(1).split(":")[0].rstrip("/").split("/")[-1]
            if target:
                driven.add(target)
    return driven


def collect(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    # Which node names an animation drives, and on what.
    animated = {}
    for m in re.finditer(r'tracks/\d+/path = NodePath\("([^"]*)"\)', text):
        p = m.group(1)
        if ":" in p:
            node, _, sub = p.partition(":")
            animated.setdefault(node.split("/")[-1], set()).add(sub)

    scripted = script_driven(text)

    # Node name -> (parent path, origin), so a parent's offset can be added.
    offsets = {}
    lights = []
    for head, body in blocks(text):
        name = re.search(r'name="([^"]*)"', head)
        parent = re.search(r'parent="([^"]*)"', head)
        if not name:
            continue
        key = (parent.group(1) if parent else ".") + "/" + name.group(1)
        offsets[key.lstrip("./")] = origin(body)

        kind = re.search(r'type="([^"]*)"', head)
        if not kind or kind.group(1) not in LIGHT_TYPES:
            continue
        if prop(body, "visible") == "false":
            continue
        if prop(body, "editor_only") == "true":
            continue
        rng = prop(body, "omni_range") or prop(body, "spot_range") \
            or prop(body, "area_range")
        energy = prop(body, "light_energy")
        lights.append({
            "name": name.group(1),
            "kind": kind.group(1),
            "key": key.lstrip("./"),
            "range": float(rng) if rng else 5.0,
            "energy": 0.0 if energy is None else float(energy),
            "drives": animated.get(name.group(1), set()),
            "scripted": name.group(1) in scripted,
        })

    # Compose ancestor translations that live in this same file.
    for light in lights:
        x, y, z = 0.0, 0.0, 0.0
        parts = light["key"].split("/")
        for depth in range(1, len(parts) + 1):
            off = offsets.get("/".join(parts[:depth]))
            if off:
                x, y, z = x + off[0], y + off[1], z + off[2]
        light["pos"] = (x, y, z)
    return lights


def report(path, lights):
    if not lights:
        return 0
    findings = 0
    header_shown = False

    def head():
        nonlocal header_shown
        if not header_shown:
            print("== %s" % path)
            header_shown = True

    # 1. Lights that never emit and are never turned up.
    for light in lights:
        if light["energy"] > 0.0:
            continue
        if "light_energy" in light["drives"] or light["scripted"]:
            who = "una animacion" if "light_energy" in light["drives"] else "un script"
            head()
            print("   [aviso] %-24s energia 0 al arrancar, radio %.1f - %s "
                  "la sube" % (light["name"][:24], light["range"], who))
            findings += 1
            continue
        head()
        print("   [COSTE] %-24s energia 0 y nadie la sube, radio %.1f - ocupa "
              "un hueco del bucle sin emitir nada" % (light["name"][:24], light["range"]))
        findings += 1

    # 2. How many lights reach the same point. Sampled on a grid over the
    #    volume the lights themselves span, which is the scene they light.
    xs = [l["pos"][0] for l in lights]
    ys = [l["pos"][1] for l in lights]
    zs = [l["pos"][2] for l in lights]
    steps = 12
    worst, worst_at, counts = 0, None, []
    for i in range(steps):
        for j in range(steps):
            for k in range(steps):
                p = (min(xs) + (max(xs) - min(xs)) * i / max(1, steps - 1),
                     min(ys) + (max(ys) - min(ys)) * j / max(1, steps - 1),
                     min(zs) + (max(zs) - min(zs)) * k / max(1, steps - 1))
                n = 0
                for light in lights:
                    d = math.dist(p, light["pos"])
                    if d <= light["range"]:
                        n += 1
                counts.append(n)
                if n > worst:
                    worst, worst_at = n, p
    counts.sort()
    median = counts[len(counts) // 2]
    if worst > SATURATION or median >= 4:
        head()
        print("   [luces] %d visibles en el fichero | por punto: mediana %d, "
              "peor %d%s" % (len(lights), median, worst,
              "  <- por encima del tope de %d de Forward Mobile" % SATURATION
              if worst > SATURATION else ""))
        findings += 1
    return findings


paths = sys.argv[1:] or sorted(glob.glob("lullaby_mod/**/*.tscn", recursive=True))
total = 0
for path in paths:
    total += report(path, collect(path))
print("\n%d ficheros barridos, %d hallazgos" % (len(paths), total))
