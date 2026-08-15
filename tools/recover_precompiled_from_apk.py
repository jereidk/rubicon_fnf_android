#!/usr/bin/env python3
"""Refills precompiled_astc_imports/ from a successful build's APK artifact.

Why this exists
---------------
precompiled_astc_imports/ used to live in Git LFS. The repository's LFS
budget is exhausted, so those objects can no longer be fetched at all:

    batch response: This repository exceeded its LFS budget.

They are out of LFS now and stored as plain git objects, but the conversion
could only carry the files whose real content happened to be present in the
working tree. 64 of them were pointers at that moment, and a pointer is 132
bytes of text - the content is on a server we cannot reach.

The Android export mode this project uses stores imported resources as loose
files under assets/.godot/imported/ inside the APK rather than packing them
into a .pck, so every one of those 64 objects is sitting inside the artifact
of any build that succeeded while they were still fetchable. That is the
recovery path README.md in that directory already describes; this is it,
automated and checked.

What it checks rather than assumes
----------------------------------
An APK from an older commit is only a valid source if the textures have not
changed since. Godot's reimport-skip decision compares the source PNG's md5
against source_md5 in the .md5 sidecar, so a stale .res is not a cosmetic
problem - it makes the build ship a texture that does not match its source,
or silently reimport and lose the point of the whole directory.

So each file is only accepted when the .import in the CURRENT working tree
names exactly the .res filename found in the APK. That filename embeds the
hash Godot derived for that source, which is what would move if the texture
had been re-authored. Anything that does not line up is skipped and named.

Usage
-----
    python3 tools/recover_precompiled_from_apk.py <artifact.zip | app.apk>

Accepts either the artifact zip straight from the Actions API (which
contains the APK) or an already-unwrapped .apk. Run from the repo root.
"""

import glob
import hashlib
import io
import os
import re
import sys
import zipfile

IMPORTED_PREFIX = "assets/.godot/imported/"
OUT_DIR = "precompiled_astc_imports"
ASTC_IMPORTERS = ("lullaby.astc_sprite", "lullaby.astc_normal_map")


def is_pointer(path):
    try:
        with open(path, "rb") as f:
            return b"git-lfs.github.com/spec" in f.read(64)
    except OSError:
        return False


def open_apk(path):
    """The artifact is a zip wrapping the APK, which is itself a zip."""
    outer = zipfile.ZipFile(path)
    names = outer.namelist()
    if any(n.startswith(IMPORTED_PREFIX) for n in names):
        return outer, "el fichero ya es el APK"

    apks = [n for n in names if n.lower().endswith(".apk")]
    if not apks:
        raise SystemExit(
            "no encuentro ni assets/.godot/imported/ ni un .apk dentro de %s" % path)
    inner = io.BytesIO(outer.read(apks[0]))
    return zipfile.ZipFile(inner), "APK extraido del artifact: %s" % apks[0]


def wanted_imports():
    """{res filename: (source png path, .import path)} for the ASTC importers."""
    out = {}
    for imp in glob.glob("lullaby_mod/**/*.import", recursive=True) + \
               glob.glob("addons/**/*.import", recursive=True):
        try:
            content = open(imp, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if not any(k in content for k in ASTC_IMPORTERS):
            continue
        m = re.search(r'dest_files=\["(res://[^"]+\.res)"\]', content)
        if not m:
            continue
        out[os.path.basename(m.group(1))] = (imp[: -len(".import")], imp)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    if not os.path.isdir(OUT_DIR):
        raise SystemExit("ejecutalo desde la raiz del repo (no veo %s/)" % OUT_DIR)

    apk, how = open_apk(args[0])
    print(how)

    declared = wanted_imports()
    print("el proyecto declara %d imports ASTC" % len(declared))

    # Only the pointers. An existing real file is left alone - it is already
    # the committed object and rewriting it would produce a diff with no
    # meaning - and so is a name this directory never carried.
    #
    # That second exclusion is the one that matters. This directory covers 145
    # of the 495 declared imports on purpose: it insures the most expensive
    # textures against the Actions cache being evicted, and the rest are cheap
    # enough to reimport. A real APK contains all 495, so hoovering up
    # everything it offers would add some 500MB of git objects to buy back a
    # few seconds. --all is there for whoever decides that trade is worth it,
    # and it is not the default.
    take_all = "--all" in sys.argv
    needed, unlisted = [], 0
    for res_name in declared:
        dest = os.path.join(OUT_DIR, res_name)
        if os.path.exists(dest):
            if is_pointer(dest):
                needed.append(res_name)
        elif take_all:
            needed.append(res_name)
        else:
            unlisted += 1

    print("punteros que hay que rellenar: %d" % len(needed))
    if unlisted:
        print("nunca estuvieron en esta carpeta, se ignoran: %d  (--all los trae)"
              % unlisted)

    in_apk = {n[len(IMPORTED_PREFIX):]: n
              for n in apk.namelist() if n.startswith(IMPORTED_PREFIX)}
    print("el APK trae %d ficheros importados" % len(in_apk))
    print()

    wrote, absent, mismatched = 0, [], []
    for res_name in sorted(needed):
        if res_name not in in_apk:
            # Either the APK predates the texture, or the source was
            # re-authored after this build and the hash in the name moved.
            absent.append(res_name)
            continue

        data = apk.read(in_apk[res_name])
        if data[:4] != b"RSRC" and not data[:4].isalpha():
            mismatched.append("%s (no parece un recurso: %r)" % (res_name, data[:8]))
            continue

        source_png, _ = declared[res_name]
        if not os.path.exists(source_png):
            mismatched.append("%s (no existe el PNG origen %s)" % (res_name, source_png))
            continue

        with open(source_png, "rb") as f:
            source_md5 = hashlib.md5(f.read()).hexdigest()
        dest_md5 = hashlib.md5(data).hexdigest()

        with open(os.path.join(OUT_DIR, res_name), "wb") as f:
            f.write(data)
        with open(os.path.join(OUT_DIR, res_name[: -len(".res")] + ".md5"), "w") as f:
            f.write('source_md5="%s"\ndest_md5="%s"\n\n' % (source_md5, dest_md5))

        wrote += 1
        print("  %-72s %9d bytes" % (res_name[:72], len(data)))

    print()
    print("recuperados: %d" % wrote)
    if absent:
        print("no estaban en el APK (%d) - probablemente la textura cambio despues:"
              % len(absent))
        for n in absent:
            print("   %s" % n)
    if mismatched:
        print("rechazados (%d):" % len(mismatched))
        for n in mismatched:
            print("   %s" % n)

    print()
    print("Comprueba antes de commitear que no queda ningun puntero:")
    print("  grep -lr 'git-lfs.github.com/spec' %s/ | wc -l   # debe dar 0" % OUT_DIR)


main()
