#!/usr/bin/env python3
"""Fill precompiled_astc_imports/ from a CI-built APK.

This is the fast path precompiled_astc_imports/README.md describes, as a
script rather than a snippet to paste. It exists because the slow path is
very slow: the two custom ASTC importers compress at EXHAUSTIVE quality, and
anything they cover that has no precompiled output gets recompressed on every
single build. The Actions cache does not save you - its key hashes every
png/tscn/tres/gd in the project, so it misses on any commit at all.

Usage:
    python3 tools/harvest_precompiled_imports.py APK --match '*_packed_*.png'
    python3 tools/harvest_precompiled_imports.py .godot/imported --match '*.png'
    python3 tools/harvest_precompiled_imports.py SOURCE           # refresh what exists
    python3 tools/harvest_precompiled_imports.py SOURCE --all     # read the warning
    ... plus --dry-run on any of the above.

SOURCE is either an APK or a directory of already-imported resources. The
directory form is what CI uses: the runner has just run --headless --import,
so .godot/imported holds the authoritative output and there is no APK to
unpack. It also means the harvest does not depend on an export succeeding.

Adding is opt-in, and that is deliberate. A real APK contains the compiled
form of every texture in the project, but this directory has never held all
of them - only the slow ones - because each entry is an LFS object that every
clone and every CI checkout then has to pull. Run with --all and you commit
some 400 more of them. So by default this only refreshes entries that are
already here, and --match names what to add.

The Android export writes imported resources as loose files under
assets/.godot/imported/ inside the APK rather than packing them, so they can
be read straight out of the zip. For each source PNG the ASTC importers own,
this pulls out the matching .res and writes the .md5 sidecar Godot's
reimport-skip check reads: source_md5 of the PNG as it exists in the tree
right now, dest_md5 of the .res bytes.

That sidecar is also the reason to be careful. Godot trusts the .res next to
a sidecar whose source_md5 matches - it does not re-derive anything - so
pairing a current PNG with a stale .res ships the wrong texture silently.
Only ever run this against an APK built from a commit whose PNGs match your
tree, and check the summary: a source the APK does not contain means the APK
predates it, which is exactly that mistake waiting to happen.

Afterwards, verify with:
    godot --headless --path . --script tools/verify_precompiled_astc.gd
"""

import fnmatch
import glob
import hashlib
import os
import re
import sys
import zipfile

OUT_DIR = "precompiled_astc_imports"
ASTC_IMPORTERS = ('importer="lullaby.astc_sprite"', 'importer="lullaby.astc_normal_map"')


def astc_sources():
    """Every source file the two ASTC importers own, by .import path."""
    for path in glob.glob("**/*.import", recursive=True):
        if ".godot/" in path.replace("\\", "/"):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if any(marker in text for marker in ASTC_IMPORTERS):
            yield path, text


def apk_index(zf):
    """Imported .res files in the APK, keyed by basename.

    Keyed by name rather than by the path= line in the tree's own .import,
    because a source that has never been imported locally has no path= line
    to read - which is the case for anything freshly added, i.e. exactly what
    this script is for.
    """
    found = {}
    for name in zf.namelist():
        if name.startswith("assets/.godot/imported/") and name.endswith(".res"):
            found[os.path.basename(name)] = name
    return found


def dir_index(root):
    """Same index, for a directory of imported resources."""
    found = {}
    for path in glob.glob(os.path.join(root, "*.res")):
        found[os.path.basename(path)] = path
    return found


def main(argv):
    flags = [a for a in argv[1:] if a.startswith("-")]
    args = [a for a in argv[1:] if not a.startswith("-")]
    dry_run = "--dry-run" in flags
    add_all = "--all" in flags
    patterns = [f[len("--match="):] for f in flags if f.startswith("--match=")]
    # Also accept the "--match PAT" spelling, which is what people type.
    rest = argv[1:]
    for i, a in enumerate(rest):
        if a == "--match" and i + 1 < len(rest):
            patterns.append(rest[i + 1])
            if rest[i + 1] in args:
                args.remove(rest[i + 1])
    if len(args) != 1:
        print(__doc__)
        return 2

    source_arg = args[0]
    if not os.path.exists(source_arg):
        print("no existe: %s" % source_arg)
        return 1
    if not os.path.isdir(OUT_DIR):
        print("ejecuta esto desde la raiz del repo (no encuentro %s/)" % OUT_DIR)
        return 1

    from_dir = os.path.isdir(source_arg)
    if from_dir:
        zf = None
        available = dir_index(source_arg)
        read_bytes = lambda key: open(available[key], "rb").read()
    else:
        zf = zipfile.ZipFile(source_arg)
        available = apk_index(zf)
        read_bytes = lambda key: zf.read(available[key])
    in_apk = available

    written, already, absent, skipped = 0, 0, [], 0
    written_bytes = 0

    def wanted(source, has_entry):
        """Refresh what is already tracked; add only what was asked for."""
        if add_all or has_entry:
            return True
        return any(fnmatch.fnmatch(source, pat) or fnmatch.fnmatch(os.path.basename(source), pat)
                   for pat in patterns)

    for imp_path, text in astc_sources():
        source = imp_path[: -len(".import")]
        if not os.path.exists(source):
            continue

        # An already-imported .import names its own output; a fresh one does
        # not, so fall back to matching the APK on the source's basename.
        match = re.search(r'path="res://\.godot/imported/([^"]+\.res)"', text)
        candidates = []
        if match:
            candidates.append(match.group(1))
        prefix = os.path.basename(source) + "-"
        candidates += [n for n in in_apk if n.startswith(prefix)]

        res_name = next((c for c in candidates if c in in_apk), None)
        if res_name is None:
            absent.append(source)
            continue

        data = read_bytes(res_name)
        source_md5 = hashlib.md5(open(source, "rb").read()).hexdigest()
        dest_md5 = hashlib.md5(data).hexdigest()

        base = res_name[: -len(".res")]
        res_out = os.path.join(OUT_DIR, res_name)
        md5_out = os.path.join(OUT_DIR, base + ".md5")

        has_entry = os.path.exists(res_out) and os.path.exists(md5_out)
        if has_entry and open(md5_out).read().split('"')[1] == source_md5:
            already += 1
            continue

        if not wanted(source, has_entry):
            skipped += 1
            continue

        written_bytes += len(data)
        if dry_run:
            print("  escribiria %s" % res_name)
        else:
            with open(res_out, "wb") as handle:
                handle.write(data)
            with open(md5_out, "w") as handle:
                handle.write('source_md5="%s"\ndest_md5="%s"\n\n' % (source_md5, dest_md5))
        written += 1

    print("")
    print("origen         : %s (%s)" % (source_arg, "directorio" if from_dir else "APK"))
    print("ya al dia      : %d" % already)
    print("%s: %d  (%.1f MB a LFS)" % (
        "escribiria    " if dry_run else "escritos      ", written, written_bytes / 1e6))
    print("no pedidos     : %d  (usa --match o --all)" % skipped)
    print("sin .res en el origen: %d" % len(absent))
    for path in absent[:20]:
        print("    %s" % path)
    if len(absent) > 20:
        print("    ... y %d mas" % (len(absent) - 20))
    if absent:
        print("")
        print("Un fuente sin .res en el origen significa que el origen es anterior a el.")
        print("Reimporta o reconstruye desde este commit antes de fiarte del resultado.")

    print("")
    print("Ahora verifica:")
    print("  godot --headless --path . --script tools/verify_precompiled_astc.gd")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
