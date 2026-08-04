# Precompiled texture imports

This directory holds pre-run output of Godot's own stock `texture`
importer for a handful of individually-slow PNGs: the `.ctex` files
Godot produces, plus a `.md5` sidecar per source file.

## Why this exists

Same idea as `precompiled_astc_imports/` and `precompiled_lightmap_imports/`
next to this directory (see their READMEs for the fuller rationale on why
the workflow's `.godot/imported` Actions cache can't just absorb this on
its own - any commit touching a tracked `.gd`/`.tscn`/etc anywhere in the
project invalidates its key). Unlike those two, the ~600 other PNGs and
OGGs that also fall outside their scope are each individually cheap
(1-2s) - there's no single disproportionate offender left to justify
precompiling all of them (that's ~560MB of committed binaries for ~7
minutes saved - a call left for later, not made here). These 4 are the
exception: each one measured over 10s alone in CI's Import step, still
using Godot's plain `texture` importer rather than either custom ASTC
plugin.

Covers:
- `assets/funkin/safety_lullaby/characters/gf/hypnosis-0.png` (a second,
  unrelated copy of `hypnosis-0.png` also exists under
  `lullaby_mod/assets/...` - that one already goes through
  `lullaby.astc_sprite` and is covered by `precompiled_astc_imports/`
  instead)
- `lullaby_mod/assets/menus/antipiracy/fuckno_doodii.png`
- `lullaby_mod/assets/menus/antipiracy/FucknoBack.png`
- `lullaby_mod/assets/funkin/safety_lullaby/pause/tex_hypno_pause.png`

## Regenerating

Needed whenever one of these 4 source PNGs changes. Run the actual
import locally (or via a throwaway CI run), then for each `.import` file
above, copy its `dest_files` entry plus the matching
`<source_basename>-<hash>.md5` sidecar (same hash embedded in the dest
filename) straight out of `.godot/imported/` - these are Godot's own
generated files, not hand-computed.

```
godot --headless --import   # run twice; see the workflow's own comment on why
```

Verify from a *clean* `.godot/` (delete it first) that a subsequent
`--headless --import` reports no `reimport |` line for any of these 4
source filenames before committing.
