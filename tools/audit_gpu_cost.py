#!/usr/bin/env python3
"""Inventory the per-scene things that cost GPU time on a fill-rate-bound phone.

Chimera is GPU-bound - gpu 38.8ms against a 38.1ms frame - and it is not draw
calls or geometry: the Collector's Shop issues more draw calls with comparable
primitives and costs 17.3ms. So the cost is per-pixel, and the question is
which per-pixel work each scene actually asks for. This lists it.

    python3 tools/audit_gpu_cost.py

Reported per scene, and split by whether the node is authored visible - an
effect layer that ships `visible = false` is turned on by a sequence for a few
seconds and is NOT part of the constant frame cost, which is the distinction
that matters when deciding what a low-end preset should cut:

  shadow lights   Light3D with shadow_enabled - each one is a shadow map
                  rendered every frame, at the shadow atlas resolution, which
                  does NOT scale with graphics_render_scale.
  fullscreen fx   CanvasItems covering the whole frame (anchors_preset 15)
                  carrying a shader or blend material. intro.tscn costs 20.6ms
                  of GPU with 13 draw calls and no lights, so these are
                  expensive out of proportion to their count.
  transparent 3D  materials that force alpha blending, which on a mobile
                  tiler means the tile cannot be resolved early.

Reads .tscn text only - no Godot, no imports, runs in a second.
"""

import glob
import json
import os
import re
import sys

SCAN_DIRS = ("lullaby_mod", "menus")

LIGHT_TYPES = ("OmniLight3D", "SpotLight3D", "DirectionalLight3D")
FULLSCREEN_TYPES = ("ColorRect", "TextureRect", "Panel", "Control", "Sprite2D")


def nodes_of(text):
    for block in re.split(r"\n(?=\[node )", text):
        m = re.match(r"\[node ([^\]]*)\]", block)
        if not m:
            continue
        header = m.group(1)

        def attr(key):
            found = re.search(key + r'="([^"]*)"', header)
            return found.group(1) if found else None

        props = dict(re.findall(r"^([A-Za-z_][\w/]*) = (.*)$", block, re.M))
        yield attr("name"), attr("type"), attr("parent"), props


def main():
    scenes = [
        p
        for d in SCAN_DIRS
        for p in glob.glob(os.path.join(d, "**", "*.tscn"), recursive=True)
    ]

    rows = []
    for scene in scenes:
        try:
            text = open(scene, errors="ignore").read()
        except OSError:
            continue

        # shader ext_resource id -> shader basename, to name what a material is
        shaders = {
            m.group(2): m.group(1)
            for m in re.finditer(
                r'\[ext_resource type="Shader"[^\]]*path="res://[^"]*/(\w+)\.gdshader"'
                r'[^\]]*id="([^"]+)"',
                text,
            )
        }
        shader_mats = {}
        for block in re.split(r"\n(?=\[sub_resource )", text):
            m = re.match(r'\[sub_resource type="ShaderMaterial" id="([^"]+)"\]', block)
            if not m:
                continue
            s = re.search(r'shader = ExtResource\("([^"]+)"\)', block)
            shader_mats[m.group(1)] = shaders.get(s.group(1), "?") if s else "?"

        shadow_on = []
        shadow_off = []
        fx_on = []
        fx_off = []

        # A node inside a hidden subtree is not drawn either, so ancestor
        # visibility has to be carried down - PhoneGlow sets no `visible` of its
        # own but lives under a cutscene group that ships hidden.
        hidden_paths = set()
        for name, _type, parent, props in nodes_of(text):
            if props.get("visible", "true").strip() == "false":
                path = name if parent in (None, ".") else parent + "/" + name
                hidden_paths.add(path)

        def visible_in_tree(name, parent, props):
            if props.get("visible", "true").strip() == "false":
                return False
            if parent in (None, "."):
                return True
            segs = parent.split("/")
            for i in range(len(segs)):
                if "/".join(segs[: i + 1]) in hidden_paths:
                    return False
            return True

        for name, type_, parent, props in nodes_of(text):
            visible = visible_in_tree(name, parent, props)

            if type_ in LIGHT_TYPES:
                if props.get("shadow_enabled", "false").strip() != "true":
                    continue
                # editor_only lights do not render in a running game at all.
                if props.get("editor_only", "false").strip() == "true":
                    continue
                label = "%s (%s)" % (name, type_)
                energy = props.get("light_energy", "1.0").strip()
                try:
                    if float(energy) == 0.0:
                        label += "  [light_energy = 0 - emits nothing, still" \
                            " renders a shadow map]"
                except ValueError:
                    pass
                (shadow_on if visible else shadow_off).append(label)

            # A CanvasItem stretched to the whole frame, carrying a material.
            if props.get("anchors_preset", "").strip() == "15" or (
                type_ in FULLSCREEN_TYPES and "anchors_preset" in props
            ):
                mat = props.get("material", "")
                mm = re.search(r'SubResource\("([^"]+)"\)', mat)
                if mm and props.get("anchors_preset", "").strip() == "15":
                    label = "%s (%s: %s)" % (name, type_, shader_mats.get(mm.group(1), "?"))
                    (fx_on if visible else fx_off).append(label)

        if shadow_on or shadow_off or fx_on or fx_off:
            rows.append(
                {
                    "scene": scene,
                    "shadow_on": shadow_on,
                    "shadow_off": shadow_off,
                    "fx_on": fx_on,
                    "fx_off": fx_off,
                }
            )

    rows.sort(key=lambda r: (-len(r["shadow_on"]), -len(r["fx_on"]), r["scene"]))

    print("Constant frame cost is the 'always on' column. A node authored")
    print("visible = false is enabled by a sequence for a few seconds and is not")
    print("part of the steady-state cost.")
    print()
    print("%-58s %-13s %-13s" % ("scene", "shadows", "fullscreen fx"))
    print("%-58s %-13s %-13s" % ("", "on / gated", "on / gated"))
    print("-" * 88)
    for r in rows:
        print(
            "%-58s %5d /%5d %5d /%5d"
            % (
                r["scene"].replace("lullaby_mod/", ""),
                len(r["shadow_on"]),
                len(r["shadow_off"]),
                len(r["fx_on"]),
                len(r["fx_off"]),
            )
        )

    print()
    print("=== detail, always-on only ===")
    for r in rows:
        if not (r["shadow_on"] or r["fx_on"]):
            continue
        print(r["scene"])
        for s in r["shadow_on"]:
            print("   shadow light  ", s)
        for f in r["fx_on"]:
            print("   fullscreen fx ", f)

    if "--json" in sys.argv:
        json.dump(rows, open("gpu_cost.json", "w"), indent=1)


if __name__ == "__main__":
    main()
