#!/usr/bin/env python3
"""Collect every property each .tscn authors, with the node's class and script.

Feeds tools/audit_authored_properties.gd, which checks the names against what
the classes actually have. Split in two because the two halves want different
things: finding the properties is a text problem over ~700 scenes (loading them
in Godot would pull every dependency in the project), and deciding whether a
name is real needs ClassDB, which only Godot has.

    python3 tools/collect_authored_properties.py > authored.json
    godot --headless --script tools/audit_authored_properties.gd -- authored.json

A node's class is not always written on the node. `[node name="X" type="Y"]`
states it; `instance=ExtResource(N)` takes it from that scene's root; and an
override of a node inside an instance (`parent_id_path=...`, no type) has to be
looked up by path inside the instanced scene. Anything this cannot pin down -
most often a script stored inline as `script = SubResource("GDScript_...")` -
is counted as unresolved and excluded rather than guessed at, because a wrong
class produces a page of properties that look missing and are not.
"""

import glob
import json
import os
import re
import sys

SCAN_DIRS = ("lullaby_mod", "addons", "menus", "songs", "resources")

_cache = {}


def parse(path):
    """Parse a .tscn into its ext_resources and node records."""
    if path in _cache:
        return _cache[path]
    _cache[path] = None

    try:
        text = open(path, errors="ignore").read()
    except OSError:
        return None

    ext = {}
    for m in re.finditer(
        r'\[ext_resource type="(\w+)"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text
    ):
        ext[m.group(3)] = (m.group(1), m.group(2))

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

        # An inline script (script = SubResource("GDScript_...")) has no path to
        # follow, so the node's real property set is unknowable from text alone.
        embedded = bool(re.search(r"^script = SubResource\(", block, re.M))
        script = None
        sm = re.search(r'^script = ExtResource\("([^"]+)"\)', block, re.M)
        if sm and sm.group(1) in ext:
            script = ext[sm.group(1)][1]

        nodes.append(
            {
                "name": attr("name"),
                "type": attr("type"),
                "parent": attr("parent"),
                "instance": ext[instance.group(1)][1] if instance else None,
                "script": script,
                "embedded_script": embedded,
                "props": re.findall(r"^([A-Za-z_][\w/]*) = ", block, re.M),
            }
        )

    _cache[path] = {"ext": ext, "nodes": nodes}
    return _cache[path]


def fs(res_path):
    return res_path.replace("res://", "")


def node_path_of(node):
    parent = node["parent"]
    if not parent or parent == ".":
        return node["name"]
    return parent + "/" + node["name"]


def root_of(scene_path, depth=0):
    """(type, script, embedded) of a scene's root, following instance chains."""
    if depth > 8:
        return (None, None, False)
    data = parse(fs(scene_path))
    if not data or not data["nodes"]:
        return (None, None, False)

    root = data["nodes"][0]
    type_, script, embedded = root["type"], root["script"], root["embedded_script"]
    if not type_ and root["instance"]:
        # An instance chain can bottom out in a .gltf/.glb/.scn, which is not
        # text and whose root class we therefore cannot name. Reporting the
        # script's own base type instead is worse than reporting nothing:
        # RubiconCharacter extends Node, so a hex model instanced from a .gltf
        # would have its Node3D `transform` called missing.
        if not root["instance"].endswith(".tscn"):
            return (None, None, True)
        t2, s2, e2 = root_of(root["instance"], depth + 1)
        type_ = type_ or t2
        script = script or s2
        embedded = embedded or e2
    return (type_, script, embedded)


def resolve(node, all_nodes, depth=0):
    """Effective (type, script, embedded) for a node in its own scene."""
    if node["instance"]:
        t2, s2, e2 = root_of(node["instance"], depth)
        return (node["type"] or t2, node["script"] or s2, node["embedded_script"] or e2)

    if node["type"]:
        return (node["type"], node["script"], node["embedded_script"])

    # No type and no instance: an override of a node living inside an instanced
    # ancestor. Walk up to that ancestor, then follow the rest of the path down
    # inside the scene it instanced.
    parts = (node["parent"] or "").split("/") if node["parent"] not in ("", ".", None) else []
    by_path = {node_path_of(n): n for n in all_nodes}

    for cut in range(len(parts), -1, -1):
        ancestor = by_path.get("/".join(parts[:cut])) if cut else all_nodes[0]
        if not ancestor or not ancestor["instance"]:
            continue

        inner = "/".join(parts[cut:] + [node["name"]])
        data = parse(fs(ancestor["instance"]))
        if not data:
            break
        inner_nodes = {node_path_of(n): n for n in data["nodes"]}
        target = inner_nodes.get(inner)
        if target is None and data["nodes"]:
            # The instanced scene may itself only be an instance of another one.
            if inner == data["nodes"][0]["name"]:
                target = data["nodes"][0]
        if target is not None:
            type_, script, embedded = resolve(target, data["nodes"], depth + 1)
            # An override may attach its own script on top of whatever the
            # instanced scene put there, and that one wins.
            if node["script"] or node["embedded_script"]:
                script = node["script"]
                embedded = node["embedded_script"]
            return (type_, script, embedded)
        break

    return (None, node["script"], node["embedded_script"])


def main():
    entries = []
    unresolved = 0

    scenes = [
        p
        for d in SCAN_DIRS
        for p in glob.glob(os.path.join(d, "**", "*.tscn"), recursive=True)
    ]

    for scene in scenes:
        data = parse(scene)
        if not data:
            continue
        for node in data["nodes"]:
            type_, script, embedded = resolve(node, data["nodes"])
            if embedded or (not type_ and not script):
                unresolved += 1
                continue
            entries.append(
                {
                    "scene": scene,
                    "node": node["name"],
                    "type": type_ or "",
                    "script": script or "",
                    "props": node["props"],
                }
            )

    json.dump({"entries": entries, "unresolved": unresolved}, sys.stdout)


if __name__ == "__main__":
    main()
