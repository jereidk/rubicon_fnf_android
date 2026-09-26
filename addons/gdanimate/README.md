# GDAnimate (forked for Holy Quintet port)

Version: 0.0.3 + Holy Quintet extensions
Upstream: https://github.com/cherrythecool/gdanimate

## What this is

This is a **fork** of GDAnimate 0.0.3, not a checkout of the current upstream.
The upstream project has since been rewritten (version 1.0.2) with a completely
different architecture: `AnimateSymbol` was renamed to `AnimateSymbol2D`, the
`adobe/` and `parser/` directories were replaced by `formats/`, and the
`AdobeAtlas` API was removed in favor of `AnimateSymbolLibrary`.

The Holy Quintet mod was written against the older 0.0.3 API. Its menus and
character sprites use `extends AnimateSymbol`, `AdobeAtlas.new()`,
`AnimateSymbol.symbol`, and the symbol-instance system that 1.0.2 no longer
provides. Migrating would require rewriting a large portion of the mod.

This fork preserves the 0.0.3 API, plus the extensions the Holy Quintet port
author added during porting:

- `adobe/` — `AdobeAtlas`, `AdobeAtlasSprite`, `AdobeSymbol`,
  `AdobeSymbolInstance`, `AdobeLayer`, `AdobeLayerFrame`, `AdobeFilter`,
  `AdobeColorMatrix`, `AdobeDrawable`, `AdobeAtlasCached`.
- `animate_atlas.gd` — abstract base class for `AdobeAtlas` and `SparrowAtlas`.
- `animate_draw_info.gd` — per-draw scratch data passed to atlas draw functions.
- `atlas_shader.gdshader` / `additive_shader.gdshader` — used by `AdobeAtlas`
  to render atlas sprites with additive blending and color matrices.

## What is NOT included

The current upstream 1.x codebase is not merged here. If you need the newer
`AnimateSymbol2D` features (symbol picker dropdown, `flip_h`/`flip_v`,
`Performance` rendering mode, multiple libraries per node), use the upstream
addon directly — it is not compatible with this fork.

## Files in this fork

- `animate_symbol.gd` — the `AnimateSymbol` node. The main entry point used by
  mod scripts.
- `animate_atlas.gd` — abstract `AnimateAtlas` base class.
- `parser/` — the 0.0.3 JSON parser (timeline, layers, frames, elements).
- `adobe/` — Adobe Animate atlas support. Extensions.
- `sparrow/` — Sparrow atlas support.
- `plugin.cfg` / `plugin.gd` — the editor plugin registration (empty hooks;
  the node is registered via `class_name` in `animate_symbol.gd`).

## License

MIT (see `LICENSE`). Original work by cherrythecool. Extensions by the
Holy Quintet port author.
