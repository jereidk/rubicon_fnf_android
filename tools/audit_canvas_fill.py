#!/usr/bin/env python3
"""Full-screen CanvasItems that cost fill for nothing, or that could cost less.

The 2D canvas is the half of this project's frame that `graphics_render_scale`
cannot touch: at scale=0.50 on 1600x720 the entire 3D pass is 0.29 Mpx, while
one full-screen 2D layer is 1.15 Mpx and Chimera's CENSUS reaches `over=8.4x`.
Safety Lullaby draws `3d=0/0` and still costs 25.93ms of GPU.

Four rules, all measured on the phone's path (Vulkan, Forward Mobile, 1600x720,
8 stacked full-screen ColorRects unless said otherwise):

  1. modulate.a == 0        0.93ms   culled - free, same as visible=false
     self_modulate.a == 0  30.87ms   NOT culled
     color.a == 0          31.09ms   NOT culled
     opaque               28.98ms
     `modulate` propagates to children so Godot can skip the whole subtree;
     the other two only affect this item, so it is still drawn - and a
     full-screen blend of nothing costs slightly MORE than an opaque one.

  2. An effect ColorRect whose shader is at its identity values still pays a
     full-screen blend AND the backbuffer copy the engine inserts for
     `hint_screen_texture`. With the real shader over 40 rects:
         active 49.7ms draws=2 | identity 20.0ms draws=2 | hidden 6.7ms draws=1
     Hiding it takes the copy with it - unlike an explicit BackBufferCopy node,
     which copies whether anything reads it or not.

  3. `render_mode blend_disabled` is legal on a canvas_item shader and is
     pixel-identical for an opaque layer: 10.5ms -> 2.8ms for the same 8 layers
     doing the same fragment work.

  4. An opaque full-screen layer does NOT let the engine skip what is under it
     by itself - 7 heavy layers cost 89.8ms alone and 91.0ms with an opaque
     blend_mix layer on top. With `blend_disabled` on that top layer the same
     frame measured 18.4ms here, but that is the software rasteriser's
     deferred tile shading doing it. Godot's 2D has no depth buffer, so an
     Adreno or Mali cannot discard an earlier draw because a later one covers
     it. Do not count on it - the portable version is to hide the covered
     layers yourself.

    python3 tools/audit_canvas_fill.py [file.tscn ...]

With no arguments it sweeps every .tscn in lullaby_mod/ and addons/.
"""
import re, sys, os, glob

BASE_W = 1920.0
FULL_KINDS = ("ColorRect", "TextureRect", "Panel", "SubViewportContainer",
              "NinePatchRect")


def blocks(text):
    for part in re.split(r"^\[node ", text, flags=re.M)[1:]:
        head, _, body = part.partition("\n")
        yield head, body.split("\n[")[0]


def prop(body, name):
    m = re.search(r"^%s = (.+)$" % re.escape(name), body, re.M)
    return m.group(1).strip() if m else None


def alpha(value, default=1.0):
    if value is None:
        return default
    m = re.match(r"Color\(([^)]*)\)", value)
    if not m:
        return default
    parts = [float(x) for x in m.group(1).split(",")]
    return parts[3] if len(parts) == 4 else 1.0


def animated_properties(text):
    """Leaf node name -> set of properties some animation writes."""
    out = {}
    for m in re.finditer(r'tracks/\d+/path = NodePath\("([^"]*)"\)', text):
        path = m.group(1)
        if ":" not in path:
            continue
        node, _, sub = path.partition(":")
        out.setdefault(node.split("/")[-1], set()).add(sub)
    return out


def script_driven_nodes(text, scene_dir):
    """Node names some script in the scene holds by NodePath and toggles.

    A `visible` written from GDScript is invisible to a text sweep, and
    reporting one of those as dead cost is exactly how this repo has been
    broken before. Chimera's LowerHealthRect is the case: it is authored
    `self_modulate.a = 0` with an opaque `color`, which looks like a
    full-screen blend of nothing - but `lower_health_overlay.gd` holds it
    through an exported NodePath and sets `visible = health < max/2`.

    So: find every node exported by NodePath *without* a `:property` suffix,
    map it to the script of the node that exports it, and see whether that
    script mentions `visible`.
    """
    scripts = {}
    for m in re.finditer(r'\[ext_resource type="Script"[^\]]*path="([^"]*)"[^\]]*id="([^"]*)"\]', text):
        scripts[m.group(2)] = m.group(1)

    driven = set()
    for head, body in blocks(text):
        script_id = re.search(r'script = ExtResource\("([^"]*)"\)', body)
        if not script_id:
            continue
        path = scripts.get(script_id.group(1))
        if not path:
            continue
        local = path.replace("res://", "")
        if not os.path.exists(local):
            continue
        source = open(local, encoding="utf-8", errors="replace").read()
        if "visible" not in source:
            continue
        for m in re.finditer(r'NodePath\("([^":]*)"\)', body):
            target = m.group(1).rstrip("/").split("/")[-1]
            if target:
                driven.add(target)
    return driven


def is_full_screen(body):
    if prop(body, "anchors_preset") == "15":
        return True
    for name in ("size", "offset_right"):
        raw = prop(body, name)
        if not raw:
            continue
        nums = re.findall(r"[\d.]+", raw)
        if nums and float(nums[0]) >= BASE_W * 0.9:
            return True
    return False


def audit(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    animated = animated_properties(text)
    script_driven = script_driven_nodes(text, os.path.dirname(path))
    findings = []
    for head, body in blocks(text):
        name = re.search(r'name="([^"]*)"', head)
        kind = re.search(r'type="([^"]*)"', head)
        if not name or not kind or kind.group(1) not in FULL_KINDS:
            continue
        if not is_full_screen(body):
            continue
        if prop(body, "visible") == "false":
            continue

        name = name.group(1)
        drives = animated.get(name, set())
        col = alpha(prop(body, "color"))
        mod = alpha(prop(body, "modulate"))
        selfmod = alpha(prop(body, "self_modulate"))
        has_shader = prop(body, "material") is not None

        # Rule 1: pays a full-screen blend while painting nothing, and the one
        # level that would make it free is not the one set to zero. A shader
        # ignores `color`, so those are rule 2's business, not this one.
        if mod > 0.0 and not has_shader and (col == 0.0 or selfmod == 0.0):
            which = "color.a" if col == 0.0 else "self_modulate.a"
            if name in script_driven:
                pass
            elif "visible" in drives:
                findings.append((name, "aviso",
                    "%s=0 con modulate opaco, pero una animacion conduce su visible" % which))
            else:
                findings.append((name, "COSTE",
                    "%s=0 con modulate opaco y nadie apaga su visible: "
                    "mezcla a pantalla completa que no pinta nada" % which))

        # Rule 3: always opaque and nothing fades it -> blend_disabled is
        # pixel-identical. ColorRect only, deliberately: it fills its whole
        # rect with one colour, so "opaque" is a property of the node. A
        # TextureRect or NinePatchRect with an alpha-cut texture reads as
        # opaque here and is full of holes on screen, and a Panel's StyleBox
        # can be rounded or translucent.
        if (kind.group(1) == "ColorRect"
                and not has_shader and col == 1.0 and mod == 1.0 and selfmod == 1.0
                and not (drives & {"modulate", "color", "self_modulate"})):
            findings.append((name, "truco",
                "opaco y nada lo funde: candidato a render_mode blend_disabled"))
    return findings


paths = sys.argv[1:]
if not paths:
    paths = sorted(glob.glob("lullaby_mod/**/*.tscn", recursive=True)
                   + glob.glob("addons/**/*.tscn", recursive=True))

total = 0
for path in paths:
    hits = audit(path)
    if not hits:
        continue
    print("== %s" % path)
    for name, tag, why in hits:
        print("   [%-5s] %-30s %s" % (tag, name[:30], why))
        total += 1
print("\n%d ficheros barridos, %d hallazgos" % (len(paths), total))
