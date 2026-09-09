# Contenido extraído de HolyQuintet.exe

Fuente: `HolyQuintet.exe` (131.5 MB, PE x64 MSVC, build Codename Engine v1.0.1 +
`cne-hxcpp` branch `old`) — zip de GameBanana dl/1779909, solo se descomprimió el exe.

## Método: tabla de recursos hxcpp (nombres exactos)

hxcpp registra cada recurso embebido en una tabla `Resource{name, len, ptr}`. Se
localizó en el binario buscando punteros qword a los strings `__ASSET__:file___ASSET__…`
y se recuperaron **809 registros válidos (64.2 MB)**: nombre real, longitud y
puntero al contenido. El exe lleva cada recurso 2× (release + `<nombre>1` debug);
los pares son byte-idénticos — se deduplicó a 289 únicos → 280 tras el canoneo.

Los IDs embebidos están **saneados** (lime los pasa a minúsculas con `_`), así que
el case/guiones reales se restauró con tres fuentes de verdad:

1. **El zip original** (`bin/assets/…` conserva case/espacios/guiones) — para los 143
   assets que también viven en el zip: match exacto id→ruta.
2. **CNE v1.0.1** (repo oficial) — layout y nombres de los archivos del engine
   (`data/notes/Alt Anim Note.hx`, `data/dialogue/boxes/hating-simulator.xml`,
   `images/editors/charter/event-spr.xml`, …).
3. **Strings del exe + contenido** — nombres `HQ*` exactos de los estados
   (`ModState("HQGauntletTransition")`), `class X` dentro de cada HScript, y los
   nombres de eventos tal cual los referencian los charts (`Sayaka Heal`,
   `Kyoko Attack`, `UI Visability`…).

## `data/` — el mod completo con nombres originales (280 archivos, 31 MB)

```
data/
├── characters/        26 personajes del mod (madoka, sayaka, homura, kyoko,
│                      mami, kyubey, nagisa, gf-*, …) — XML codename-engine-character
├── events/            9 eventos con su .hx + .json de editor (nombres con espacios)
├── notes/             4 note-types: Alt Anim/Bullet/No Anim/Timestop Note.hx
├── stages/            9 stages del mod + stage.xml (out-of-time con guión real)
├── states/            21 estados HQ* softcodeados (HQMainMenu, HQFreeplay, HQPause…)
├── scripts/           HQTransition.hx, kadeHUD.hx, dropshadow-effect.hx
├── songs/*.hx         8 scripts globales de gameplay + songs/UIs/{Standard,MegucaUI}.hx
├── songs/<nombre>/    10 canciones: charts (easy/hard), meta, events, dialogue,
│                      Inst.ogg, Voices[-X].ogg — ¡audio incluido!
├── weeks/             8 weeks + week-characters + tutorial
├── dialogue/          cajas y personajes de diálogo
├── global.hx          el Global Script (17 KB, corre siempre)
├── langs/             traducciones en_US + es_US
└── …                  alphabet, config, splashes, editors, titlescreen, discord.hx
```

También: `source/` (27 **clases Haxe del mod en fuente**: `SongInfoUI`,
`SoulGemUI`, `GenUtil`, `BlurFilter`… — su capa lógica compilada como scripts),
`images/` (XMLs de atlas del engine), `modchart/` (shapes CSV), `flixel/sounds/`.

## Verificación

- 56/56 JSON parsean; 95 XML con DOCTYPE correcto (26 character, 9 week,
  8 week-character, 3 alphabet, 2 splash, 1 stage, 46 sin doctype = layouts)
- Audio OGG íntegro (`OggS`), charts con `strumLines`/`events`/`noteTypes`
- Los `.hx` referencian clases del mod (`ui.SoulGemUI`) que existen en `source/`

## Qué NO está aquí

- **El engine (CNE) es open source**: `CodenameCrew/CodenameEngine` v1.0.1 — el
  `source/` del engine se lee del repo, no del exe.
- **El multimedia grueso** (PNG spritemaps, videos MP4, fuentes, shaders .frag)
  sigue en el **zip** (`bin/assets/`: 1059 PNG, 241 OGG, 14 MP4, 35 frag) — el exe
  solo embebió XMLs/JSON/HX/OGG de data + algunos atlas.
- `bin/lua/` del zip es de libvlc (parsers de playlist), no del mod; `bin/mods/` está vacía.

## División exacta del juego

**exe = código + `data/`** (este volcado) · **zip = multimedia** que el `data/` referencia.
