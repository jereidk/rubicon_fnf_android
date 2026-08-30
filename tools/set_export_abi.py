#!/usr/bin/env python3
"""Sets which Android ABIs an export preset builds for.

The preset carries four `architectures/<abi>=` lines and the repo has always
had exactly one of them true - arm64-v8a. That is the right default and stays
the default; this exists so a build can also be made for 32-bit devices, or for
both at once, without hand-editing export_presets.cfg and remembering to put it
back.

Two things worth knowing before using arm32:

  * a 32-bit build will not install on a device that only ships 64-bit ABIs, and
    a 64-bit-only build will not install on an armeabi-v7a-only phone. `both`
    installs anywhere at the cost of carrying two sets of native libraries, so
    it is the one to hand someone whose device you do not know.
  * x86 and x86_64 are left alone - false, as they have always been. They are
    for emulators, nothing here has ever been tested on one, and turning them on
    silently would make the APK bigger for no one.

The file is edited in place and section-scoped: the same
`architectures/arm64-v8a=` key appears once per Android preset, so a blind
search-and-replace would rewrite the Release preset while building Debug. The
preset is found by its `name=` inside `[preset.N]`, and only the matching
`[preset.N.options]` block is touched.

Usage:
    python3 tools/set_export_abi.py "Android Debug" arm64
    python3 tools/set_export_abi.py "Android Release" both
    python3 tools/set_export_abi.py "Android Debug" arm32 --dry-run
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRESETS = os.path.join(ROOT, "export_presets.cfg")

## Que ABI enciende cada eleccion. `all` no aparece aqui: no es una
## configuracion, son tres builds, y eso lo decide quien llama.
ABIS = {
    "arm64": {"arm64-v8a": True, "armeabi-v7a": False},
    "arm32": {"arm64-v8a": False, "armeabi-v7a": True},
    "both": {"arm64-v8a": True, "armeabi-v7a": True},
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("preset", help='nombre del preset, p.ej. "Android Debug"')
    ap.add_argument("abi", choices=sorted(ABIS))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    text = open(PRESETS, encoding="utf-8").read()

    # El bloque [preset.N] cuyo name= coincide, y luego su [preset.N.options].
    index = None
    for m in re.finditer(r'(?m)^\[preset\.(\d+)\]\n(.*?)(?=^\[|\Z)', text, re.S):
        if re.search(r'(?m)^name="%s"$' % re.escape(args.preset), m.group(2)):
            index = m.group(1)
            break
    if index is None:
        sys.exit('no encuentro un preset llamado "%s"' % args.preset)

    opts = re.search(r'(?m)^\[preset\.%s\.options\]\n(.*?)(?=^\[|\Z)' % index,
                     text, re.S)
    if opts is None:
        sys.exit("el preset %s no tiene bloque de opciones" % index)

    body = opts.group(1)
    changed = []
    for abi, on in ABIS[args.abi].items():
        key = "architectures/%s" % abi
        want = "%s=%s" % (key, "true" if on else "false")
        new, n = re.subn(r'(?m)^%s=(?:true|false)$' % re.escape(key), want, body)
        if n == 0:
            sys.exit("el preset no declara %s" % key)
        if new != body:
            changed.append(want)
        body = new

    text = text[:opts.start(1)] + body + text[opts.end(1):]

    print("preset.%s (%s) -> %s%s" % (index, args.preset, args.abi,
        ("   cambia: " + ", ".join(changed)) if changed else "   (ya estaba)"))
    if args.dry_run:
        return
    open(PRESETS, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()
