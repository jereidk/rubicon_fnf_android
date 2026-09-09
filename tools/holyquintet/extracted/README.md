# Contenido extraído de HolyQuintet.exe

Fuente: `HolyQuintet.exe` (131.5 MB, PE x64 MSVC, build Codename Engine v1.0.1 +
`cne-hxcpp` branch `old`) — zip de GameBanana dl/1779909, solo se descomprimió el exe.

## Qué es esto

El mod **no incluye carpeta `data/` en el zip**: sus charts, stages, weeks,
personajes y scripts están embebidos dentro del exe como recursos hxcpp
(strings UTF-8 en el string pool). Este directorio es el volcado de esos
recursos, reconstruido escaneando el binario.

## `scripts/` — 69 scripts HScript únicos (607 KB)

CNE softcode en texto plano (dialecto hscript: `function create()`,
`postCreate()`, `onEvent()`, `importScript(...)`). Cada bloque se deduplicó por
SHA-256 (el exe lleva cada script ~2×: pool release + debug). Nombres
`<hint>_0x<OFFSET>.hx` = heurística de arranque + offset del archivo.

Incluye: tutorial (23 KB con `tutorialProgression`), Sayaka `healthDrain` +
`whiteShader`, intro en video de Kyubey (`FlxVideoSprite`), gauntlet,
`godukaEnabled`, `SoulGemUI`, achievements, menús/créditos (41 KB)…

## `data/` — 56 archivos únicos

| Tipo | Contenido |
|---|---|
| `cne_character_*.xml` ×27 | personajes (`<!DOCTYPE codename-engine-character>`) |
| `cne_week_*.xml` ×8 | weeks del mod |
| `cne_stage_*.xml` ×3 (+1 atlas) | stages |
| `*.json` ×15 | charts Codename (`strumLines`, `events`, `scrollSpeed`): resonance, eternalstar, initium, meguca, out-of-time, partea, reconnect, stardom, vexation |

## Inventario del zip original (GameBanana dl/1779909)

Todo bajo `bin/` (532.7 MB):

| Carpeta | Contenido |
|---|---|
| `bin/assets/` | **1389 archivos**: images/ 1059 PNG (188 MB), sounds/ 241 OGG (15 MB), videos/ 14 MP4 (51 MB), fonts/ (20 MB OTF/TTF), music/ 26 OGG, shaders/ 35 .frag |
| `bin/plugins/` | 391 archivos de hxcpp/lime (110 MB) |
| `bin/lua/` | Scripts .luac de **libvlc** (parsers de playlist youtube/twitch/vimeo) — NO del mod |
| `bin/mods/` | **Vacía** — confirma que todo el mod va embebido en el exe |
| `bin/HolyQuintet.exe` | 131.5 MB — el juego completo + data del mod |

División exacta: **exe = código + `data/`** (scripts, charts, stages, weeks,
personajes), **zip = multimedia** (lo que referencia el `data/`).

## Qué NO está aquí (y dónde sí)

- **El engine (CNE) sí es open source**: `CodenameCrew/CodenameEngine` v1.0.1 en
  GitHub — el "source/" del juego se lee del repo, no del exe. El exe solo trae
  los *paths* `source/funkin/...` como metadatos de compilación hxcpp, no el texto.
- **Los assets multimedia** (PNG, OGG, videos, shaders .frag) **sí están** en el
  zip original sin extraer: 762 png, 241 ogg, 13 mp4, 27 frag.
- Clases Haxe propias del mod compiladas a binario (`ui.SoulGemUI`,
  `util.GenUtil`…): solo desensamblando; los scripts que las usan están aquí.

## Herramientas

Escaneo con `strings -n N -t x` + heurística de validez (ratio imprimible >95%,
firmas `function create|postCreate|onEvent...`, `^import (funkin|flixel|util)...`,
dedup SHA-256). Ver `/tmp/hq_scripts/` para los volcados crudos (218 bloques).
