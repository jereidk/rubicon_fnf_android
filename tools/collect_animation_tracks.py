#!/usr/bin/env python3
"""Collect every animation track in every scene, with the tree it has to resolve against.

Feeds tools/audit_animation_tracks.gd. Godot drops an animation track whose
NodePath does not resolve, or whose property the target node does not have,
**in silence** - no error, no warning, the animation simply does less than it
was authored to do. That is how 86% of the Collector's and Hex's bone tracks
were being discarded, and how Hypno's three tracks animating
`dancing_measure_step` disappeared when this fork renamed the property.

Two jobs the audit needs and only text can do cheaply:

1. Flatten each scene's node tree, expanding instanced sub-scenes, so a track
   pointing at `Stage/GoldPhase1/Parts/BodySymbol/AnimationPlayer` can be
   looked up. SceneState alone does not see inside an instance.
2. Pull the tracks out of animations stored as sub-resources of the .tscn.

External AnimationLibraries (.res/.tres) are listed rather than read - those are
resources, so the Godot half loads them. So is every class/property question,
which needs ClassDB.

    python3 tools/collect_animation_tracks.py > tracks.json
    godot --headless --script tools/audit_animation_tracks.gd -- tracks.json
"""

import glob
import json
import os
import re
import sys

SCAN_DIRS = ("lullaby_mod", "addons", "menus", "songs", "resources")

# AnimationPlayer's root_node defaults to the player's parent.
DEFAULT_ROOT = ".."

MAX_DEPTH = 8

_scene_cache = {}
_flat_cache = {}


def read(path):
    """Parse a .tscn's ext_resources, sub-resource animations and nodes."""
    if path in _scene_cache:
        return _scene_cache[path]
    _scene_cache[path] = None

    try:
        text = open(path, errors="ignore").read()
    except OSError:
        return None

    ext = {}
    for m in re.finditer(
        r'\[ext_resource type="(\w+)"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text
    ):
        ext[m.group(3)] = {"type": m.group(1), "path": m.group(2)}

    # Animations stored inside the scene, keyed by sub_resource id.
    animations = {}
    for block in re.split(r"\n(?=\[sub_resource )", text):
        m = re.match(r'\[sub_resource type="Animation" id="([^"]+)"\]', block)
        if not m:
            continue
        name = re.search(r'resource_name = "([^"]*)"', block)
        tracks = []
        by_index = {}
        for tm in re.finditer(r"tracks/(\d+)/(type|path) = (.*)", block):
            by_index.setdefault(tm.group(1), {})[tm.group(2)] = tm.group(3).strip()
        for idx in sorted(by_index, key=int):
            entry = by_index[idx]
            path_m = re.match(r'NodePath\("(.*)"\)', entry.get("path", ""))
            if not path_m:
                continue
            tracks.append(
                {
                    "type": entry.get("type", "").strip('"'),
                    "path": path_m.group(1),
                }
            )
        animations[m.group(1)] = {
            "name": name.group(1) if name else m.group(1),
            "tracks": tracks,
        }

    # AnimationLibraries stored inside the scene: id -> [animation sub ids]
    libraries = {}
    for block in re.split(r"\n(?=\[sub_resource )", text):
        m = re.match(r'\[sub_resource type="AnimationLibrary" id="([^"]+)"\]', block)
        if not m:
            continue
        libraries[m.group(1)] = re.findall(r'SubResource\("([^"]+)"\)', block)

    nodes = []
    for block in re.split(r"\n(?=\[node )", text):
        m = re.match(r"\[node ([^\]]*)\]", block)
        if not m:
            continue
        header = m.group(1)

        def attr(key):
            found = re.search(key + r'="([^"]*)"', header)
            return found.group(1) if found else None

        instance = re.search(r'instance=ExtResource\("([^"]+)"\)', header)
        script = None
        sm = re.search(r'^script = ExtResource\("([^"]+)"\)', block, re.M)
        if sm and sm.group(1) in ext:
            script = ext[sm.group(1)]["path"]

        # libraries/ = SubResource(...) or a dict of name: SubResource/ExtResource
        lib_subs = []
        lib_exts = []
        lib_block = re.search(r"^libraries/?\w* = (.*?)(?=^\w|\Z)", block, re.M | re.S)
        if lib_block:
            lib_subs = re.findall(r'SubResource\("([^"]+)"\)', lib_block.group(1))
            for eid in re.findall(r'ExtResource\("([^"]+)"\)', lib_block.group(1)):
                if eid in ext:
                    lib_exts.append(ext[eid]["path"])

        root_node = None
        rm = re.search(r'^root_node = NodePath\("([^"]*)"\)', block, re.M)
        if rm:
            root_node = rm.group(1)

        nodes.append(
            {
                "name": attr("name"),
                "type": attr("type"),
                "parent": attr("parent"),
                "instance": ext[instance.group(1)]["path"] if instance else None,
                "script": script,
                "lib_subs": lib_subs,
                "lib_exts": lib_exts,
                "root_node": root_node,
            }
        )

    _scene_cache[path] = {
        "ext": ext,
        "animations": animations,
        "libraries": libraries,
        "nodes": nodes,
    }
    return _scene_cache[path]


def fs(res_path):
    return res_path.replace("res://", "")


def node_path_of(node):
    parent = node["parent"]
    if not parent or parent == ".":
        return node["name"]
    return parent + "/" + node["name"]


def flatten(scene_res_path, depth=0):
    """Relative node path -> {type, script, opaque} for a scene.

    The scene root is keyed ".", every other node by its path below it. The
    root must NOT be keyed by its own name: a child of the root is written
    `parent="."` so its path is just its name, and scenes here really do give a
    child the same name as the root (cut_boyfriend_scream, every pause menu).
    Keying both by that name merges them, and then a track aimed at the child
    resolves onto the root instead - or, once the root is re-keyed, at nothing.

    `opaque` marks a node whose subtree cannot be read: an instance of a .gltf
    or .scn. The skeletons under those carry most of the bone tracks in the
    project, and nothing about them is knowable from text, so the audit has to
    treat a path descending into one as unchecked rather than broken.
    """
    if depth > MAX_DEPTH:
        return {}
    if scene_res_path in _flat_cache:
        return _flat_cache[scene_res_path]
    _flat_cache[scene_res_path] = {}

    data = read(fs(scene_res_path))
    if not data or not data["nodes"]:
        return {}

    out = {}

    def merge(path, info):
        entry = out.setdefault(path, {"type": None, "script": None, "opaque": False})
        entry["type"] = entry["type"] or info.get("type")
        entry["script"] = entry["script"] or info.get("script")
        entry["opaque"] = entry["opaque"] or bool(info.get("opaque"))

    for index, node in enumerate(data["nodes"]):
        path = "." if index == 0 else node_path_of(node)
        merge(path, node)

        instance = node["instance"]
        if not instance:
            continue
        if not instance.endswith(".tscn"):
            merge(path, {"opaque": True})
            continue

        inner = flatten(instance, depth + 1)
        for rel, info in inner.items():
            merge(path if rel == "." else _join(path, rel), info)

    _flat_cache[scene_res_path] = out
    return out


def _join(base, rel):
    return rel if base == "." else base + "/" + rel


def main():
    scenes = [
        p
        for d in SCAN_DIRS
        for p in glob.glob(os.path.join(d, "**", "*.tscn"), recursive=True)
    ]

    out_scenes = []
    for scene in scenes:
        data = read(scene)
        if not data:
            continue

        tree = flatten("res://" + scene)
        players = []
        for node in data["nodes"]:
            if not (node["lib_subs"] or node["lib_exts"]):
                continue

            anims = []
            for lib_id in node["lib_subs"]:
                for anim_id in data["libraries"].get(lib_id, []):
                    anim = data["animations"].get(anim_id)
                    if anim:
                        anims.append(anim)
                # `libraries/ = SubResource(Animation_x)` straight to an animation
                anim = data["animations"].get(lib_id)
                if anim:
                    anims.append(anim)

            players.append(
                {
                    "path": node_path_of(node),
                    "root_node": node["root_node"] or DEFAULT_ROOT,
                    "animations": anims,
                    "external_libraries": node["lib_exts"],
                }
            )

        if players:
            out_scenes.append({"scene": scene, "tree": tree, "players": players})

    json.dump({"scenes": out_scenes}, sys.stdout)


if __name__ == "__main__":
    main()
