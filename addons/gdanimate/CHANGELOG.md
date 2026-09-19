# Changelog

## [0.0.3-hq] - Holy Quintet fork

Fork of upstream 0.0.3 with extensions needed by the Holy Quintet mod port.

### Added
- `adobe/` directory with the extended Adobe Animate atlas system:
  `AdobeAtlas`, `AdobeAtlasCached`, `AdobeAtlasSprite`, `AdobeColorMatrix`,
  `AdobeDrawable`, `AdobeFilter`, `AdobeLayer`, `AdobeLayerFrame`,
  `AdobeSymbol`, `AdobeSymbolInstance`.
- `animate_atlas.gd` — abstract `AnimateAtlas` base class shared by
  `AdobeAtlas` and `SparrowAtlas`.
- `animate_draw_info.gd` — `AnimateDrawInfo`, per-draw scratch data.
- `atlas_material.tres` / `additive_material.tres` and their shaders.
- `AnimateSymbol` gained: `centered`, `offset`, `speed_scale`, `autoplay`,
  `loop`, `atlases` (array), `atlas_index`, per-symbol backbuffer cache,
  static draw stats.

### Not merged from upstream
- 1.0.2 rewrite: `AnimateSymbol2D`, `formats/`, `AnimateSymbolLibrary`.
  Not compatible with the mod's usage of the 0.0.3 API.

## [0.0.3] - upstream baseline

Base version this fork started from. See
https://github.com/cherrythecool/gdanimate for upstream history.
