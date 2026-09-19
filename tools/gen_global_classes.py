#!/usr/bin/env python3
"""Genera el bloque _global_script_classes de project.godot.

Godot registra los class_name en .godot/global_script_class_cache.cfg cuando
corre el editor, pero NO los escribe en project.godot. Como ese .cfg esta
gitignored y el export lee project.godot -> project.binary, las clases nunca
llegan al APK exportado por el CI.

Es idempotente: correrlo dos veces con el mismo codigo no cambia el archivo.

Uso: python3 tools/gen_global_classes.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_GODOT = os.path.join(ROOT, "project.godot")

EXCLUDE_DIRS = {".git", ".godot", "builds", "android", "node_modules"}


def parse_gd(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            src = f.read()
    except Exception:
        return None

    lines = src.split("\n")
    is_tool = False
    is_abstract = False
    class_name = None
    extends = None

    for line in lines[:50]:
        s = line.strip()
        if s.startswith("@tool"):
            is_tool = True
        if s.startswith("@abstract"):
            is_abstract = True
        if s.startswith("class_name ") and class_name is None:
            m = re.match(r"class_name\s+(\w+)", s)
            if m:
                class_name = m.group(1)
        if s.startswith("extends ") and extends is None:
            m = re.match(r"extends\s+([\w.]+)", s)
            if m:
                extends = m.group(1)

    if not class_name:
        return None

    return {
        "class_name": class_name,
        "extends": extends or "RefCounted",
        "is_tool": is_tool,
        "is_abstract": is_abstract,
        "path": path,
    }


def scan_project():
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            info = parse_gd(full)
            if info:
                rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                info["res_path"] = "res://" + rel
                out.append(info)
    return out


def resolve_base(info, by_name, seen=None):
    if seen is None:
        seen = set()
    name = info["class_name"]
    if name in seen:
        return "RefCounted"
    seen.add(name)
    ext = info["extends"]
    if ext in by_name:
        return resolve_base(by_name[ext], by_name, seen)
    return ext


def gen_block(classes):
    classes_sorted = sorted(classes, key=lambda c: c["class_name"])
    lines = ["_global_script_classes=[{"]
    for i, c in enumerate(classes_sorted):
        cls = c["class_name"]
        base = c["base"]
        is_abs = "true" if c["is_abstract"] else "false"
        is_tool = "true" if c["is_tool"] else "false"
        path = c["res_path"]
        lines.append('\t"base": "%s",' % base)
        lines.append('\t"class": &"%s",' % cls)
        lines.append('\t"icon": "",')
        lines.append('\t"is_abstract": %s,' % is_abs)
        lines.append('\t"is_tool": %s,' % is_tool)
        lines.append('\t"language": &"GDScript",')
        if i < len(classes_sorted) - 1:
            lines.append('\t"path": "%s"' % path)
            lines.append("}, {")
        else:
            lines.append('\t"path": "%s"' % path)
            lines.append("}]")
    lines.append("_global_script_class_icons={")
    for i, c in enumerate(classes_sorted):
        cls = c["class_name"]
        if i < len(classes_sorted) - 1:
            lines.append('\t"%s": "",' % cls)
        else:
            lines.append('\t"%s": ""' % cls)
    lines.append("}")
    return "\n".join(lines)


def strip_existing_block(src):
    """Borra el bloque previo. Sin regex: iteramos linea por linea."""
    lines = src.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        if lines[i].startswith("_global_script_classes="):
            i += 1
            while i < n and lines[i] != "}]":
                i += 1
            if i < n:
                i += 1
            if i < n and lines[i].startswith("_global_script_class_icons="):
                i += 1
                while i < n and lines[i] != "}":
                    i += 1
                if i < n:
                    i += 1
            if i < n and lines[i] == "":
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def main():
    classes = scan_project()
    if not classes:
        print("ERROR: no encontre class_name en el proyecto")
        sys.exit(1)

    by_name = {c["class_name"]: c for c in classes}
    for c in classes:
        c["base"] = resolve_base(c, by_name)

    block = gen_block(classes)

    with open(PROJECT_GODOT, "r", encoding="utf-8") as f:
        src = f.read()

    src = strip_existing_block(src)

    marker = "config_version=5\n"
    if marker not in src:
        print("ERROR: no encontre 'config_version=5'")
        sys.exit(1)

    head, sep, tail = src.partition(marker)
    tail = tail.lstrip("\n")
    src = head + sep + "\n" + block + "\n\n" + tail

    with open(PROJECT_GODOT, "w", encoding="utf-8") as f:
        f.write(src)

    print("OK: %d class_name escritas" % len(classes))


if __name__ == "__main__":
    main()
