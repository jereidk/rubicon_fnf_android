# The mod's original gdanimate, decompiled from the pck

Reference only. Nothing here is on the import path or shipped - these files
have no `.uid` sidecars and are not referenced by any scene.

## Why they are here

`addons/gdanimate/` in this port contains **two** implementations side by side:

- `adobe/` + `animate_atlas.gd` + `animate_draw_info.gd` - the mod's original
- `parser/` + `animate_symbol.gd` - the rubicon fork's rewrite

Nothing outside `adobe/` references `AdobeAtlas`, `AnimateAtlas` or
`AnimateDrawInfo`; `AnimateDrawInfo` is never constructed and `draw_on()` is
never called. The whole `adobe/` tree is dead code that still ships in the APK,
and the live renderer is the fork's.

That matters because both the PC original and twgusta's working Android port
run the adobe path, and this port does not. Every Adobe-animated symbol in
Monochrome - Gold, the unowns, Celebi, the vultures - goes through the one
subsystem where we run different code from both of them.

The one file needed to close that gap is `animate_symbol.gd`, the glue, and it
is the only gdanimate script the port does not have as source. So it was
recovered, along with the `sparrow` pair the port is also missing.

## Provenance and how far to trust it

Produced by `tools/gdc_decompile.py` from `lullaby_mod/original_pck/Lullaby.pck`.

The decompiler was validated on `adobe_atlas.gd`, which this repo already has
as real source: decompiling the pck's copy and comparing against
`addons/gdanimate/adobe/adobe_atlas.gd`, ignoring comments and intra-line
spacing, gives **532 of 532 significant lines identical, 100%**.

Comments, blank-line placement and intra-line spacing are not recoverable from
a token stream and are absent or approximate here. Everything else - every
identifier, literal, default value and statement - is exact.

Cross-check: `animate_symbol.gd` decompiled from twgusta's APK is identical to
the pck's except that the pck loads its two materials by `uid://` where his
loads them by `res://` path. Same script, two independent copies.

## What the fork's rewrite dropped

`speed_scale`, `autoplay`, `loop`, `atlases: Array[AnimateAtlas]`,
`atlas_index`, the `Make AnimationLibrary` tool button, the whole sparrow draw
path, and the backbuffer cache keyed on `frame_dirty`. `offset` was restored
separately in 8fb55d8 but as the seed of the fork's own transform, which is
not where the original applies it - the original passes `get_transform()` into
the draw info and keeps `offset` as a separate field.
