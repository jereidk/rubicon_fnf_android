# gdanimate vs FlxAnimate — auditoria de fidelidad

Este documento es el resultado del primer pase de auditoria de `addons/gdanimate/adobe/`
(el parser Adobe Animate activo) contra el engine Haxe real que usa el mod `holyquintet`.
Es la referencia obligatoria antes de tocar cualquier archivo de `adobe/`: dice que esta
verificado, que esta roto, y que esta documentado como "no aplica" con su razon.

**No se toco** `addons/gdanimate/sparrow/` (otro formato, para ButtonUI) ni
`addons/gdanimate/parser/` (ver seccion "parser/ es codigo muerto" abajo).

## Fuente de verdad ACTUAL: `MaybeMaru/flixel-animate` @ `dcaa33c`

**Esta es la referencia vigente y manda sobre todo lo que sigue.** Por decision
del usuario, gdanimate se fideliza contra el HEAD de `MaybeMaru/flixel-animate`,
commit `dcaa33ca8845f23d7c4c441025cecaacc91b0eff` ("Absolute paths fix",
2026-08-26), clonado en `/root/refs/flixel-animate-maru`. 23 archivos `.hx`,
6.695 lineas.

```bash
git clone https://github.com/MaybeMaru/flixel-animate.git /root/refs/flixel-animate-maru
git -C /root/refs/flixel-animate-maru checkout dcaa33ca8845f23d7c4c441025cecaacc91b0eff
```

Sobre `cne-flixel-animate` (la referencia anterior, ver la seccion siguiente):
comparando los HEADs reales de los dos repos, **cne es maru + hooks de Codename,
no un superset de features**. Una conclusion anterior de esta auditoria decia que
cne era el mas completo; eso era un artefacto de comparar contra un ref viejo de
maru (febrero) en vez de contra su HEAD, y esta **corregido**.

Las citas `archivo:linea` de las secciones viejas apuntan a `cne-flixel-animate`
y siguen siendo validas donde el codigo coincide, pero **no estan re-verificadas
contra maru salvo donde se diga explicitamente**. Todo lo escrito a partir del
pase file-by-file (F1 en adelante) cita maru `dcaa33c`.

### Pase file-by-file contra maru (F1..F13)

Orden acordado: archivo por archivo, logica por logica.

| # | Archivo Haxe (maru) | Destino en el port | Estado |
|---|---|---|---|
| F1 | `FlxAnimateJson.hx` (810) | `adobe_atlas.gd`, `adobe_color_matrix.gd` | **hecho** (ver abajo) |
| F2 | `Element.hx` (78) + `AtlasInstance.hx` (244) | `adobe_drawable.gd`, `adobe_atlas_sprite.gd` | **hecho** (ver abajo) |
| F3 | `SymbolInstance.hx` (282) + `MovieClipInstance.hx` (285) | `adobe_symbol_instance.gd`, `adobe_atlas.gd` | **hecho** (ver abajo) |
| F4 | `ButtonInstance.hx` (153) | `adobe_button_instance.gd`, `animate_symbol.gd` | **hecho** (ver abajo) |
| F5 | `Frame.hx` (448) | `adobe_layer_frame.gd`, `adobe_animate_controller.gd` | **hecho** (ver abajo) |
| F6 | `Layer.hx` (262) | `adobe_layer.gd` | **hecho** (ver abajo) |
| F7 | `Timeline.hx` (476) + `SymbolItem.hx` (95) | `adobe_symbol.gd` | **hecho** (ver abajo) |
| F8 | `FlxAnimateFrames.hx` (707) | `adobe_atlas.gd` (load_*) | **hecho** (ver abajo) |
| F9 | `FlxAnimate.hx` (497) | `animate_symbol.gd` | **hecho** (ver abajo) |
| F10 | `FlxAnimateController.hx` (413) | `adobe_animate_controller.gd` | **hecho** (ver abajo) |
| F11 | `StageBG.hx` (46) + `Blend.hx` (171) | stage bg + shader | **hecho** (ver abajo) |
| F12 | `TextFieldInstance.hx` (124) + `FlxSpriteElement.hx` (206) | `adobe_textfield_instance.gd` | **F12a hecho, F12b diferido a F13** (ver abajo) |
| F13 | filtros: `RenderTexture` + `FilterRenderer` + `AdjustColorFilter` + `StackBlur` + `MaskShader` | `adobe_filter.gd`, `adobe_color_matrix.gd`, `adobe_render_baker.gd` | **F13a + F13b-i hechos, F13b-ii..iv pendientes** |

### F13b-ii.3c — test de integracion del pipeline de bake

**HECHO.** `tests/test_bake_integration.gd` nuevo, 5 casos:

1. `_filters_bake_key` sin filtros -> "".
2. `_filters_bake_key` con GLOW solo -> "" (glow va por shader inline,
   no bakea).
3. `_filters_bake_key` con BLUR -> "layer:<id>:<frame>:<start>:<hash>".
4. `_filters_bake_key` con DROP_SHADOW -> no vacia.
5. `AdobeRenderBaker.request()` con BLUR en un patron mitad-y-mitad:
   despues del bake + apply_filters_to_texture, el pixel del borde
   (x=15) tiene rojo < 0.99 (blur aplicado).

Los casos 1-4 son puros (sin render). El 5 ejercita el pipeline completo:
SubViewport bake + apply_filters_to_texture + readback. Suite: **19/19**.

### F13b-ii.3b — aplicar filtros al bake + reconectar bake_ready

**HECHO.**

1. **`AdobeRenderBaker.request()`** acepta `filters: Array[AdobeFilter]`
   opcional. `_do_bake` aplica `apply_filters_to_texture` a la textura
   resultante ANTES de guardarla en el cache. El cache que queda es la
   textura **ya filtrada** (equivalente a `FilterRenderer.applyFilter`
   de maru, que devuelve el BitmapData final).

2. **`_request_layer_bake`** en `adobe_atlas.gd` pasa `filters_copy` al
   `baker.request()`.

3. **`AnimateSymbol._enter_tree`** conecta `AdobeRenderBaker.bake_ready`
   a un slot `_on_bake_ready(key)` que hace `queue_redraw()`. **Sin
   esto**, el primer frame tras un cache miss seguia dibujando sin
   filtro y el siguiente nunca se enteraba. **`_exit_tree`** desconecta
   para evitar callbacks sobre nodos liberados.

Con esto el flujo completo funciona:
- Frame N: `draw_symbol` ve la capa con BLUR, no hay cache, dibuja sin
  filtro + encola el bake.
- Frame N+1 (baker `_process`): hornea el contenido crudo + aplica los
  filtros via shader → guarda en cache → emite `bake_ready`.
- Frame N+1 (symbol, tras recibir el signal): `queue_redraw()`.
- Frame N+2: `draw_symbol` ve el cache → dibuja la textura filtrada.

Latencia total: 2 frames. Imperceptible a 60fps (33ms).

**Tests:** sin test nuevo. El test de integracion real (bake con BLUR
en un simbolo sintetico) es F13b-ii.3c. Suite: **18/18**.

### F13b-ii.3a — bifurcacion de bake en draw_symbol

**HECHO (hooks).** `adobe_atlas.gd` ahora tiene:

1. **Bifurcacion en `draw_symbol`:** cuando una capa tiene filtros que el
   shader inline NO cubre (BLUR, DROP_SHADOW, BEVEL), el render de esa
   capa se reemplaza por una textura baked:
   - Cache hit: dibujar la textura filtrada con
     `canvas_item_add_texture_rect` y `continue` (saltea el loop de
     elementos).
   - Cache miss: dibujar normal este frame + disparar el bake para el
     proximo.
   - GLOW y ADJUST_COLOR siguen por el shader inline (ya funcionan); no
     fuerzan bake.

2. **`_filters_bake_key(layer, frame, layer_frame)`:** devuelve `""` si la
   capa no necesita bake, o una key de cache
   `"layer:<id>:<frame>:<starting_index>:<hash>"`.

3. **`_request_layer_bake(...)`:** encola un bake. Dibuja los elementos a
   un canvas plano del SubViewport via el mini-loop (copia local; no reusa
   el loop de `draw_symbol` porque ese tiene side effects en
   `_backbutton_scratch` y `_backbuffer_scratch`).

**Estado (F13b-ii.3a):** los bakes se encolan pero **todavia no se aplican
los filtros ni se reconecta `bake_ready` a `queue_redraw`**. Eso viene en
F13b-ii.3b. Como ningun asset del mod HQ/tricky tiene BLUR/DS/BEVEL, la
ramificacion nunca se ejecuta en runtime real: cero regresion visual.

**Tests:** sin test nuevo (los hooks no son verificables sin un asset con
BLUR). Suite sigue **18/18**.

### F13b-ii.2 — DropShadow + Bevel

**HECHO.** Extendido `filter_shader.gdshader` +
`AdobeRenderBaker.apply_filters_to_texture` para cubrir DropShadow (DSF)
y Bevel (BF). Ya **no** hace falta un segundo pase: los dos se resuelven
con samples offset en el mismo shader.

**DropShadow:** se dibuja como un alpha compositing estandar del shadow
detras del contenido. El shadow es `src` muestreada en
`uv - ds_offset_uv` con un ring de alpha para el blur. Formula:
    fg_rgb = col.rgb * col.a
    bg_rgb = ds_color.rgb * ds_alpha
    out_a = col.a + ds_alpha * (1 - col.a)
    col.rgb = (fg_rgb + bg_rgb * (1 - col.a)) / out_a

**Bevel:** dos rings opuestos (highlight y shadow). Se aplican sobre
donde el sprite NO cubre (`1 - col.a`), con `mix()`:
    ring_h = ring en (uv + bevel_offset_uv)
    ring_s = ring en (uv - bevel_offset_uv)
    h_amount = ring_h * (1 - col.a) * strength * highlight.a
    s_amount = ring_s * (1 - col.a) * strength * shadow.a
    col.rgb = mix(col.rgb, highlight.rgb, h_amount)
    col.rgb = mix(col.rgb, shadow.rgb, s_amount)
    col.a = max(col.a, h_amount + s_amount)

**Uniforms nuevos:**
- ds_enabled, ds_color, ds_offset_uv, ds_blur_uv, ds_strength
- bevel_enabled, bevel_highlight, bevel_shadow, bevel_offset_uv,
  bevel_blur_uv, bevel_strength

**Offsets en UV-space:** igual que el blur, los offsets (distance, angle)
se convierten a UV dividiendo por `size` en GDScript. Evita el gotcha de
`TEXTURE_PIXEL_SIZE` (viewport-global, no texture-local) descubierto en
F13b-ii.1.

**Helper nuevo en el shader:** `sample_alpha_ring(tex, uv, r)`, variante
de `sample_glow_ring` que toma un radio escalar (no un `vec2`) — util
para DS y Bevel que solo necesitan un radio.

**Tests:** `test_filter_shader.gd` extendido con 2 casos: DropShadow
agrega alpha a la zona del shadow (fuera del contenido original); Bevel
agrega pixeles en el borde del patron. Suite: **18/18**.

**Cobertura final del shader:** BLUR, GLOW, DROP_SHADOW, BEVEL,
ADJUST_COLOR. Los dos tipos GRADIENT_* (solo flash en el source) quedan
descartados: no se aplican, mismo comportamiento que maru en target no
flash.

### F13b-ii.1 — shader de filtros + `apply_filters_to_texture`

**HECHO.** `filter_shader.gdshader` (nuevo) + metodo
`AdobeRenderBaker.apply_filters_to_texture(src, filters, size)`.

Port conceptual de `FilterRenderer.applyFilter`
(maru src/animate/internal/FilterRenderer.hx:400-500). El source aplica
filtros de a uno al `BitmapData` (via OpenFL + GPU shader o CPU). El
port los aplica en **un solo pase** con un shader de canvas_item.

**Cobertura del shader:** BLUR, GLOW, ADJUST_COLOR.
**Diferido a F13b-ii.2:** DROP_SHADOW, BEVEL (necesitan un segundo pase
con el contenido original + offset del shadow).

**Detalles de implementacion:**

- `apply_filters_to_texture` crea un `SubViewport` temporal con un
  `TextureRect` (con `src` como textura) y un `ShaderMaterial`. Espera a
  `RenderingServer.frame_post_draw` y lee con `get_texture().get_image()`
  (equivalente a `gl.readPixels` del source).
- `TextureRect` y no `ColorRect`: el shader lee la textura fuente en
  `TEXTURE`; un `ColorRect` dibuja un rect plano sin textura.

**Lecciones / fixes aplicados en este sub-pase:**

1. `TAU` ya existe como built-in en el shader language de Godot 4 (junto
   con `PI` y `E`). No se puede redeclarar — el shader no compila.
2. `instance uniform` + `ShaderMaterial.set_shader_parameter()` **no se
   comunican**. Los instance uniforms requieren
   `RenderingServer.canvas_item_set_instance_shader_parameter()` sobre el
   RID del nodo. Este shader usa `uniform` a secas (se aplica a 1 nodo,
   no necesita instancing).
3. `TEXTURE_PIXEL_SIZE` en un canvas_item shader **no es 1/size de la
   textura** — es un valor global del viewport. El radio del blur hay que
   pasarlo precomputado como `blur_uv = blur_px / size` desde GDScript.
4. Texturas uniformes (rojo solido) no muestran blur aunque el shader
   funcione: no hay transiciones que suavizar. El test usa un patron
   mitad-y-mitad (borde duro) para verificar.

**Tests:** `tests/test_filter_shader.gd` nuevo (3 casos: blur suaviza un
borde duro, adjust con brightness -50 atenua el rojo, filtros vacios
hacen passthrough). Suite: **18/18**.

### F13b-i — infra render-to-texture (`AdobeRenderBaker`)

**HECHO.** `adobe/adobe_render_baker.gd` (nuevo).

Port conceptual de `FilterRenderer.renderToBitmap`
(maru src/animate/internal/FilterRenderer.hx:257-285). El source:
1. Toma un `FlxCamera` del `CamPool`.
2. Llama `draw_cb(cam, mat)` que dibuja en el canvas de la camara.
3. `renderGfx()` lee el canvas a un `BitmapData` via `gl.readPixels`.
4. Devuelve el `BitmapData`.

En Godot la version mas cercana es SubViewport + `frame_post_draw` +
`get_texture().get_image()` (que ES `readPixels`) + `ImageTexture`.

**DIVERGENCIA ARQUITECTONICA — bake deferred, no sincrono.**

El source es SINCRONO: `renderToBitmap` devuelve el bitmap en el mismo
call stack y el caller lo usa inmediatamente. Godot no permite "render
sincrono a textura". El port usa bake DEFERRED:

- El caller hace `baker.request(key, size, draw_cb)` y sigue con lo que
  tenia cacheado.
- El `AdobeRenderBaker` singleton hornea **1 pending por frame** en su
  propio `_process()`.
- El resultado se ve **1 frame tarde**. Imperceptible a 60fps.

Efecto observable: la primera vez que aparece una capa con filtro se ve
sin filtro durante 1 frame. No es un bug, es la unica forma sin reescribir
el pipeline de Godot. Se puede mitigar pre-bakeando durante el `parse()`
del atlas, pero eso multiplica el tiempo de carga (maru mismo lo advierte
en `FilterQuality` con el flag `cacheOnLoad`).

**Serializado: 1 SubViewport, 1 bake por frame.**

Evita N viewports en memoria cuando hay muchas capas con filtros. Es lo
que hace maru con `CamPool.get()` (una camara del pool, no N).

**API** (`AdobeRenderBaker`):
- `instance()` -> singleton (creado bajo root del SceneTree on demand).
- `request(key, size, draw_cb)` -> encola un bake. `draw_cb(rid, size)`.
- `has_cached(key) -> bool`.
- `get_cached(key) -> ImageTexture`.
- `invalidate(key)` -> descarta cache + pending. Equivalente al
  `_dirty = true` de `Frame.setDirty()` en maru.
- `signal bake_ready(key)` -> emitida cuando termina un bake. El caller
  puede reconectar para `queue_redraw()`.

**Uso en F13b-ii** (todavia pendiente): en `AdobeAtlas.draw_symbol`,
cuando una capa tiene filtros, el render se hace asi:
1. Consultar `baker.get_cached(key)`.
2. Si hay cache, dibujar la textura como `canvas_item_add_texture_rect`.
3. Si no, `baker.request(key, size, cb)` y dibujar SIN filtro este frame
   (o dibujar el bake previo si `invalidate` no se llamo todavia).
4. El `AnimateSymbol::_process()` reconecta `bake_ready` -> `queue_redraw`.

**Tests:** `tests/test_render_baker.gd` nuevo (3 casos: bake simple de un
rect rojo 32x32, cache hit sin request nuevo, invalidate limpia la key).
Suite: **17/17**.

### F13 — filtros: F13a (parseo + math) y F13b (render-to-texture, pendiente)

**Revision del pipeline real de maru.**

maru NO aplica filtros per-fragmento. El pipeline es:
1. `FilterRenderer.renderToBitmap` renderiza la frame a un `BitmapData` offscreen.
2. Aplica los `BitmapFilter` de OpenFL al bitmap (GPU via
   `__renderGpuFilter`, o CPU via `__renderCpuFilter` + `StackBlur`).
3. `bakeFilters` devuelve un `AtlasInstance` con el bitmap filtrado como
   `frame`. El resto del render lo trata como un sprite normal.

En Godot eso requiere render-to-texture (SubViewport + `force_draw` +
`get_texture`). Es la misma infra que necesita F12b
(`FlxSpriteElement`). Por eso F13 se parte en dos.

**F13a HECHO — parseo + math sin render.**

Lo que se puede hacer sin tocar el pipeline de dibujo:

1. **`AdobeFilter` reescrito** (`adobe_filter.gd`):
   - Enum con **7 tipos** en vez de 2: BLUR, ADJUST_COLOR, DROP_SHADOW,
     GLOW, BEVEL, GRADIENT_GLOW, GRADIENT_BEVEL.
   - `parse_one(raw)`: dispatch por `N`/`name` con los 7 nombres cortos
     (`BLF`/`ACF`/`DSF`/`GF`/`BF`/`GGF`/`GBF`) y los 7 largos
     (`blurFilter`/`adjustColorFilter`/`dropShadowFilter`/`glowFilter`/
     `bevelFilter`/`gradientGlowFilter`/`gradientBevelFilter`). Filtro
     desconocido -> null (mismo comportamiento que el source).
   - `parse_list(input)`: acepta Array (optimized) o Dictionary (legacy
     con `DropShadowFilter` / `GlowFilter` como claves). El source lo
     normaliza con `FilterJson.resolve` (FlxAnimateJson.hx:419-440).
   - `extract_glow_compat(filters)`: devuelve el primer GLOW como Dict con
     los campos que el shader inline actual espera (`color`, `alpha`,
     `blur_x`, `blur_y`, `strength`, `quality`, `inner`, `knockout`).

2. **Parseo en `load_frame`**: ahora pobla `AdobeLayerFrame.filters` con
   `AdobeFilter.parse_list`. Antes `glow` existia pero NUNCA se puebla
   (el shader de glow nunca funcionaba). Ahora `glow` es un DERIVADO de
   `filters` (primer GLOW) y el shader inline recibe datos reales.

3. **Parseo en `load_symbol_instance`**: ahora pobla
   `AdobeSymbolInstance.filters` desde `SymbolInstanceJson.F`. Antes el
   campo existia y nunca se usaba.

4. **`AdobeLayerFrame.filters: Array[AdobeFilter]`** campo nuevo.

5. **`AdobeAtlas.expand_filter_bounds(base, filters)`**: port de
   `FilterRenderer.expandFilterBounds`. Calcula el margen que cada filtro
   agrega al bbox (blur/glow outer/dropShadow). No expanden:
   inner glow, bevel, adjust_color, gradient_*.

6. **`AdobeColorMatrix.adjust_from_params(b, h, c, s)`**: port de
   `AdjustColorFilter.getColorMatrix`. Matematica pura. Devuelve un
   `AdobeColorMatrix` con la diagonal + offsets compuestos. Documentado:
   la version del port NO aplica el cross-talk entre canales
   (saturation/hue cruzados); con los valores reales del mod (h=0,
   saturation=0) es 1:1 con el source. Un caso con h != 0 requiere un
   shader 4x5 completo -> F13b.

**F13b PENDIENTE — aplicar los filtros (render-to-texture).**

Bloqueado por SubViewport (misma infra que necesita F12b). Componentes
que faltan:

- `FilterRenderer::renderToBitmap` -> `SubViewport` + `force_draw`.
- `FilterRenderer::bakeFilters` -> horneado con margen de filtro.
- `FilterRenderer::applyFilter` + `__renderGpuFilter` / `__renderCpuFilter`.
- `FilterRenderer::maskFrame` (aunque `canvas_item_set_canvas_group_mode(
  CLIP_ONLY)` puede cubrirlo parcialmente).
- `StackBlur::blur` (para targets sin gpu-blur).
- `MaskShader` (equivalente al CLIP_ONLY nativo).
- `Frame._requireBake` / `_bakedFrames` / `__isDirtyCall`.
- `FilterQuality` enum.
- Aplicacion de cada filtro real (Blur, Glow outer, DropShadow, Bevel).
- `AdjustColorFilter` con shader 4x5 completo (para h != 0, s != 1).

**Reaperturas tambien anotadas para F13b:**

- **F11-reopen**: modos ALPHA (1) y ERASE (4) hoy hacen `discard` en
  `atlas_shader.gdshader`. Divergencia arquitectonica fundamental
  (requieren escribir el alpha del BG). Fix real: RenderTexture +
  composicion manual -> F13b.
- **F11-reopen**: ADD con premult hack (`COLOR.rgb *= COLOR.a` antes de
  `add()`). Divergencia real contra el `BlendShader` de maru. Revisar en
  F13b.
- **F12-reopen**: `FlxSpriteElement` (F12b). Requiere SubViewport capture.
- **F12-reopen**: `letter_spacing` (CSP) y `bold`/`italic` en
  `AdobeTextFieldInstance`. F13b.

**Tests:** `tests/test_filters.gd` nuevo (6 casos: parseo optimized,
parseo legacy dict, filtro desconocido descartado, extract_glow_compat,
expand_filter_bounds para blur/inner-glow/outer-glow/none,
adjust_from_params identidad). Suite: **16/16**.

### F12 — `TextFieldInstance.hx` (F12a) + `FlxSpriteElement.hx` (F12b)

**F12a HECHO — `TextFieldInstance.hx` (124 lineas).**

Port en `adobe/adobe_textfield_instance.gd` (nuevo). El source crea un
`openfl.text.TextField`, lo configura con un `TextFormat`, mide
`textWidth`/`textHeight`, lo hornea a un `BitmapData` y lo trata como un
`FlxFrame` mas. Hereda de `AtlasInstance`, NO de `SymbolInstance`.

El port NO hornea a textura: usa `TextLine` de Godot, que dibuja directo
al canvas RID del layer en el mismo pipeline que el resto de los
elementos. Ventajas: sin SubViewport, sin forzar render sincrono, y
glow/blend/canvas group siguen aplicando igual porque va al mismo
`canvas_item` del layer. El source hornea porque Flixel dibuja sincrono y
necesita un `FlxFrame`; Godot no lo necesita.

**Parseo** (`AdobeAtlas::load_textfield_instance`):
- MX / matrix -> `transform`
- TXT / text -> `text`
- ATR[0].SZ / Size -> `font_size`
- ATR[0].C / color -> `text_color` (hex, trim_prefix "#")
- ATR[0].F / font -> `font_path` (el source lo trata como nombre de
  fuente del SO; aca como path `res://`. Fallback a `ThemeDB.fallback_font`
  si no existe.)
- ATR[0].ALN / align -> `align` (0=left, 1=center, 2=right, 3=justify)
- ATR[1..N] -> ignorados. El source solo lee `ATR[0]`
  (TextFieldInstance.hx:52 `var atr = data.ATR[0]`).

**Dispatch**: `load_frame` prueba SI > ASI > TFI. Antes el TFI estaba como
`pass` (se salteaba); ahora se construye. `draw_symbol` tiene una rama
nueva para `AdobeTextFieldInstance` despues del `elif` de
`AdobeAtlasSprite`.

**Divergencias conocidas:**

- **`letter_spacing` (CSP)**: no aplicado. `TextLine.add_string` no
  soporta tracking. Anotado para F13b: agregar manualmente por glifo o
  cambiar a un `RichTextLabel` con `BBCode` custom.
- **`bold` (BL) / `italic` (IT)**: no aplicados. Requieren cargar la
  variante bold/italic de la fuente. El source las aplica via
  `TextFormat.bold/italic` (que redirige a la fuente del SO). En Godot
  hay que resolver el path a la variante correcta. Anotado para F13b.
- **`BRD` / `ALSRP` / `ALTHK`**: no aplicados. El source **tampoco** los
  aplica (`format.borderSize = data.ALTHK` esta comentado,
  TextFieldInstance.hx:71). Fiel.
- **`MAX` / `ORT` / `LT` / `TP` / `IN`**: no aplicados. El source no los
  usa en render. Fiel.
- **`AUK` / `CPS` / `LSP` / `IND` / `LFM` / `RFM` / `URL`**: no aplicados.
  El source no los lee. Fiel.

**Anclaje del bbox**: `transform * Rect2(0, 0, W, H)`, igual que
`AtlasInstance.getBounds` (AtlasInstance.hx:168-180). Sin centrar.

**Alineacion horizontal**: aplicada manualmente en `draw_to_canvas`
desplazando el origen por -W/2 (center) o -W (right). `TextLine` no maneja
alineacion por si sola; el source la resuelve via `TextFormat.align` +
`textWidth`. Resultado final: identico.

**Tests:** `tests/test_textfield.gd` nuevo (5 casos: parse minimo,
atributos completos, bbox desde matrix, setter de text marca dirty,
ATR vacio no crashea). Actualizado `test_json_schema.gd`: el fixture de
dispatch ahora espera 3 elementos (SI + ASI + TFI) en vez de 2, y
verifica `els[2] is AdobeTextFieldInstance`. Suite: **15/15**.

**F12b DIFERIDO — `FlxSpriteElement.hx` (206 lineas).**

En maru, `FlxTypedElement<T:FlxBasic>` envuelve un `FlxBasic` arbitrario
(un `FlxSprite` cualquiera del juego) para que participe de la timeline
de Animate con transform/blend/color sincronizados. Patron: guardar
estado -> `basic.setPosition(...)` -> `basic.draw()` -> restaurar. Todo
**sincrono**, dentro del mismo call stack, porque Flixel dibuja a camara
inmediatamente.

**En Godot esto no es posible 1:1.** El pipeline de dibujo es diferido
via RIDs: modificar un `CanvasItem` no se refleja hasta el proximo frame
del scene tree. No hay "draw synchronously now".

Tres arquitecturas posibles:
1. **SubViewport capture**: renderizar el `CanvasItem` externo a una
   textura via `SubViewport`, dibujar la textura en la timeline. Fiel al
   resultado. **Requiere la infra de SubViewport que tambien necesita
   F13** (filtros Adobe: `RenderTexture` de maru).
2. **RID reparenting**: `canvas_item_set_parent(nodo.get_canvas_item(),
   layer_rid)` en draw_on, restaurar en `_process`. Aprovecha el pipeline
   actual pero rompe jerarquia de nodos (riesgo con botones, filtros).
3. **API transformada**: el elemento expone `apply_timeline_transform(t)`
   que el consumidor llama en `_process`. Funcional pero no fiel al
   "sincrono".

**Decision: F12b va con opcion 1, diferido a F13b**, cuando la infra de
SubViewport este armada. Hacerlo antes implica duplicar el trabajo de
F13 (que tambien necesita SubViewport/RenderTexture) o hacer un hack
(RID reparenting) que despues habria que deshacer.

**Reapertura F11 (para F13b):**
- Modos de blend **ALPHA (1)** y **ERASE (4)**: hoy hacen `discard` en
  `atlas_shader.gdshader`. Son divergencia arquitectonica fundamental:
  requieren escribir el alpha del BG compuesto, que un `canvas_item`
  no controla (solo el FG). Fix real requiere RenderTexture + composicion
  manual -> **F13b**, junto con la infra de SubViewport.
- **ADD con premult hack** (`COLOR.rgb *= COLOR.a; COLOR.a = 1.0` antes de
  `add()`): divergencia real contra el `BlendShader` de maru, que aplica
  ADD sin premultiplicar. Para el patron real que usan los mods (glow
  additive sobre fondo oscuro) el resultado visual coincide, pero no es
  fiel. **Revisar en F13b.**

### F11 — `StageBG.hx` + `Blend.hx`: estado (sin fixes)

**Revision completa.** Los dos archivos ya estan portados fielmente. Este
pase es solo verificacion + documentacion de las divergencias
arquitectonicas.

**Verificacion empirica de blends en los mods.**

Se escanearon los 42 Animation.json del HQ + trickyclowned buscando claves
`B` (optimized) y `Blend` (legacy). Resultado:

    0  ADD         ->  105 instancias
    9  MULTIPLY    ->  204 instancias
    TOTAL:            309

**Cero ALPHA, cero ERASE, cero valores fuera de {ADD, MULTIPLY}.** Los dos
unicos modos que aparecen estan implementados y son fieles:

- **ADD (0)**: `add(COLOR, screen)` con premultiplicacion por `COLOR.a` y
  `COLOR.a = 1.0`. Documentado como divergencia conocida por el autor
  (blend aditivo de Flixel no es exactamente el mismo que Flash, que
  aplica ADD sobre el target sin premultiplicar). Para el patron real que
  usan los mods (glow additive sobre fondo oscuro) el resultado visual
  coincide.
- **MULTIPLY (9)**: `multiply(COLOR, screen)` = `COLOR.rgb * screen.rgb`.
  Identico al `a.rgb * b.rgb` del `BlendShader` de maru.

**`Blend.hx` - estado por metodo:**

- `resolve()` -> `adobe_atlas.gd::resolve_blend` (~linea 810). Port fiel.
  La unica rama no portada es `Frame.__isDirtyCall -> NORMAL`, que es del
  sistema de baking de keyframes (F13).
- `fromInt()` -> cubierto por el enum `AdobeSymbolInstance.AdobeBlendMode`.
  Verificado valor-por-valor contra `Blend.hx:37-56`:
    ADD=0, ALPHA=1, DARKEN=2, DIFFERENCE=3, ERASE=4, HARD_LIGHT=5,
    INVERT=6, LAYER=7, LIGHTEN=8, MULTIPLY=9, NORMAL=10, OVERLAY=11,
    SCREEN=12, SHADER=13, SUBTRACT=14.
  Los 15 valores coinciden exactos.
- `isGpuSupported()` -> N/A. En Godot el blend se resuelve via
  `instance uniform int blend_mode` en `atlas_shader.gdshader`, no via
  shaders de target.
- `blend()` + `BlendShader` (bitmap) -> N/A. Arquitectura distinta: el
  shader de maru renderiza al TARGET (BG compuesto) y hace el alpha blend
  manual (`result.rgb = mix(a.rgb, result.rgb, b.a)`). El shader de Godot
  renderiza por fragmento del FG y deja que el canvas haga el alpha blend
  automatico. **Mismo resultado neto**, mecanismo distinto.

**Divergencia arquitectonica: modos 1 (ALPHA) y 4 (ERASE) no se aplican.**

`atlas_shader.gdshader` hace `discard` para ambos:
    } else if (blend_mode == 1 || blend_mode == 4) { // adobe animate skill issue
        discard;
    }

Razon: un shader canvas_item **no puede reescribir el BG**, solo el FG.
Para ALPHA (reemplazar el alpha del BG por el del FG) o ERASE (atenuar el
BG por el alpha del FG) hace falta un segundo pase con
`canvas_item_set_copy_to_backbuffer`. **No vale la pena implementarlo
porque los mods reales no los usan** (verificado empiricamente: 0 hits).

**Cobertura del shader (verificada contra `BlendShader` de maru):**

    0 ADD         -> add() con premult (divergencia conocida)
    1 ALPHA       -> discard (N/A)
    2 DARKEN      -> min()
    3 DIFFERENCE  -> abs(a - b)
    4 ERASE       -> discard (N/A)
    5 HARD_LIGHT  -> overlay(COLOR, screen) = hardlight(BG, FG)  [identidad]
    6 INVERT      -> 1.0 - BG
    7 LAYER       -> passthrough (no matchea en el if)
    8 LIGHTEN     -> max()
    9 MULTIPLY    -> a * b
    10 NORMAL     -> excluido del if externo, passthrough
    11 OVERLAY    -> overlay(screen, COLOR) = overlay(BG, FG)
    12 SCREEN     -> 1 - (1-a)*(1-b)
    13 SHADER     -> passthrough
    14 SUBTRACT   -> BG - FG

Las dos `overlay()` con argumentos invertidos (11 y 5) son identidades
matematicas: el orden de los argumentos de `hardlight` en Flash coincide
con el `overlay(a,b)` con los roles invertidos. Verificado leyendo
`BlendShader` de maru lado a lado.

**`StageBG.hx` - estado:**

Port en `AdobeAtlas.draw_on` (`render_stage` branch). El source escala un
sprite 1x1 blanco a `(stageRect.width, stageRect.height)` y le aplica el
color; el port dibuja `stage_rect` directo como rect con
`canvas_item_add_rect`. **Mismo resultado visual** porque `stage_rect`
siempre se construye en `_parse_stage_metadata` como `Rect2(0, 0, W, H)`.

Early-outs del source:
    if (!visible || alpha <= 0) return;
    if (colorTransform.alphaMultiplier <= 0) return;

El port solo tiene el segundo via `stage_color.a > 0.0`. En Godot el
modulate del padre se hereda por jerarquia de canvas_items, asi que
`modulate.a == 0` no dibuja igual - solo hay 1 rect de coste, no es bug.

**Regresion visual: cero.** Sin cambios de codigo en este pase.

### F10 — `FlxAnimateController.hx`: `on_frame_label` + `set_anim_frame`

**Revision completa del archivo (413 lineas).** El registro de animaciones
nombradas y la busqueda de labels ya estaban portados en F7. Este pase
cierra los dos gaps que el port tenia anotados:

**FIX 1 — Signal `on_frame_label`.**

Port de `FlxAnimateController.onFrameLabel` (maru
FlxAnimateController.hx:19-23):
    public final onFrameLabel = new FlxTypedSignal<(frameLabel:String) -> Void>();
Se dispara cada vez que el frame activo del timeline tiene un label no
vacio. En maru lo dispara `Timeline.signalFrameChange` (que a su vez itera
los frames activos y llama `Frame.signalFrameChange`).

Cadena en el port:
- `AnimateSymbol.frame` setter llama `_anim_controller.notify_frame_changed(value)`.
- `AdobeAnimateController.notify_frame_changed` consulta
  `AnimateSymbol.get_current_label()` y emite `on_frame_label` si no esta
  vacio.
- `AnimateSymbol.get_current_label()` usa `AdobeSymbol.get_frame_label_at_index`
  (F7) sobre el simbolo actual.

**FIX 2 — `set_anim_frame(anim_name, frame_index)`.**

Port del override de `set_frameIndex` (maru FlxAnimateController.hx:322-350):
    frame = frame % numFrames;
    _animate.timeline = curAnim.timeline;
    _animate.timeline.currentFrame = frame;
    _animate.timeline.signalFrameChange(frame, this);
    frameIndex = frame;
    fireCallback();

El port NO overridea el `_process` del sprite (AnimateSymbol avanza natural
con `frame += amount`, siguiendo el flow Godot). Reemplazar ese flow por un
`set_frameIndex` completo es alto riesgo sobre mods calibrados, asi que
`set_anim_frame` se expone como **API publica**: un consumidor que quiera
el wrap estricto por lista lo usa en vez de setear `.frame` a mano.

Comportamiento:
- `posmod(frame_index, indices.size())` — wrap por la LISTA, no por
  `frame_count` del timeline (como hace maru).
- Mapea `indices[idx]` al frame real del simbolo.
- Cambia `_sprite.symbol` al `timeline_symbol` registrado (si hay).
- Llama `notify_frame_changed` para disparar el signal.
- Devuelve el frame real, o -1 si la animacion no esta registrada.

`play(anim_name)` se refactorizo para llamar `set_anim_frame(anim_name, 0)`,
asi que tambien dispara el signal y hace wrap del primer indice.

**N/A (arquitectura distinta):**
- `updateTimelineBounds` (maru FlxAnimateController.hx:353-372): construye
  un `FlxFrame` fake para que FlxSprite tenga `frameWidth`/`frameHeight`
  coherentes con el bbox del timeline. En Godot el AnimateSymbol es un
  Node2D que dibuja RIDs directo; no tiene "frame rect" que fakeear.
- `FlxAnimateAnimation.getCurrentFrameDuration`: extension de FlxAnimation
  para que los frame durations cuenten. La animacion de Godot
  (`AnimationPlayer` generado por `make_player_from_current`) ya maneja
  esto nativamente.
- `_renderTexture` mark-dirty en `set_frameIndex`: N/A (useRenderTexture
  no portado, ver F9).
- `getCollectionTimelines` sobre `addedCollections`: N/A, el port tiene un
  solo atlas por AnimateSymbol.

**Verificado como equivalente:**
- `add_by_frame_label` / `add_by_frame_label_indices` / `add_by_symbol` /
  `add_by_symbol_indices` / `add_by_timeline` / `add_by_timeline_indices`:
  registran en `_animations` con la misma estructura {name, indices,
  frame_rate, looped, flip_x, flip_y, timeline_symbol} que la
  FlxAnimateAnimation de maru.
- `find_frame_label_indices`: port fiel con `rtrim` en el nombre del
  keyframe (no `strip_edges`) y `hasFoundLabel` + break al primer layer.

**Tests:** `tests/test_anim_controller_f10.gd` nuevo con 4 casos:
`set_anim_frame` basico con indices [2,5,8], wrap positivo (`3->2, 4->5`),
wrap negativo (`-1->8` por posmod), animacion no registrada -> -1, y
existencia/conectividad del signal `on_frame_label`. Suite: **14/14**.

### F9 — `FlxAnimate.hx`: origin-shift automatico + flip de offset

**Revision completa del archivo (497 lineas).** Casi todo estaba portado en
`animate_symbol.gd` (props + setters, `_process` con playback, `_draw_impl`
-> `_draw_adobe`, `get_animation_length`, `validate_frame`). El fix
funcional de este pase es el origin-shift automatico al bbox del simbolo,
que cierra la otra mitad del bug raiz del trickyDJ.

**FIX — origin-shift automatico al bbox del simbolo (BREAKING).**

maru `drawAnimate` (FlxAnimate.hx:194-196):
    var bounds = timeline._bounds;
    if (!willUseRenderTexture) matrix.translate(-bounds.x, -bounds.y);

El source hace este shift SIEMPRE, no condicionado a `applyStageMatrix`
(que recien se aplica despues, en `prepareAnimateMatrix`). El port no lo
hacia en absoluto: `offset` era `@export var offset: Vector2 = ZERO`, que
el usuario seteaba a mano. Resultado: todo sprite quedaba desplazado por
`bounds.position` del simbolo, lo cual el mod HQ compensaba con
`pixel_offset` empiricos.

Fix: `AdobeAtlas.compute_bounds_offset(key)` (nuevo, ~linea 1557) devuelve
`-symbol.bounding_box.position`. `draw_on` lo aplica
(`transform = transform.translated(compute_bounds_offset(key))`) ANTES
de concatenar `stage_transform`, mismo orden que el source.

**BREAKING CHANGE: `offset` invierte el signo.**

maru `FlxSprite.updateFramePixels`:
    _point.x += origin.x - offset.x;
    _point.y += origin.y - offset.y;
o sea offset positivo mueve el sprite **LEFT/UP**. El port sumaba
(`translated(draw_info.offset)`), asi que offset positivo movia
**RIGHT/DOWN** - opuesto al source. Ahora se resta
(`translated(-draw_info.offset)`).

**Consecuencia agregada:** los dos cambios de F9 (shift automatico +
flip de signo) van a romper visualmente los mods actuales:

- **Holy Quintet**: los `pixel_offset` empiricos del `MainMenuSprite` /
  `chr_*_base.tscn` asumian que `bounds_offset` era 0 y que offset
  positivo movia RIGHT/DOWN. Despues de F9 hay que **recalibrar todos**.
- **Tricky Clowned Out**: trickyDJ va a quedar **corregido** de raiz
  (bbox ya no arrastra (0,0), y el origin-shift se aplica como en maru),
  pero `title-screen-text` puede necesitar reajuste de `offset` por el
  flip.

**La recalibracion NO se hace en este pase** (regla: no testear mods
hasta cerrar F13). Queda como paso obligatorio post-F13: correr los mods,
medir, ajustar `offset` a mano hasta que las posiciones coincidan con el
engine Haxe real.

**N/A (arquitectura distinta):**
- `useRenderTexture`, `_renderTexture`, `checkRenderTexture`: el flatten
  de limbs a una textura unica es una optimizacion para `renderTile` en
  flixel; Godot dibuja directo via RenderingServer.
- `postStageMatrixApply`: modo alternativo de aplicar el stage matrix
  despues de las transformaciones del sprite. El mod usa el orden default.
- `skew`, `_skewMatrix`, `updateSkew`: FlxSprite no tiene skew en el port.
- `drawDebugLimbs`, `drawFrameComplex`, `getScreenBounds`,
  `getAnimateOrigin`, `drawStage` (StageBG): N/A o F13.
- `updateFramePixels` (render a BitmapData): N/A, Godot no tiene ese
  pipeline.
- `set_applyStageMatrix` que dispara `anim.updateTimelineBounds()`: el
  port no cachea bounds en el sprite (lazy en `AdobeSymbol.bounding_box`),
  asi que no hay nada que invalidar. El setter ya hace `frame_dirty =
  true` + `queue_redraw`, que es lo que importa.

**Verificado como equivalente (mecanismo distinto, resultado igual):**
- Loop REVERSO de layers. maru `Timeline.draw` itera `i = length - 1;
  i--`. El port itera `for layer in target.layers` (0..N-1) y compensa
  con `to_push.push_front(layer_rid)` + `canvas_item_set_draw_index(i)`
  con i creciente. Layers[0] queda con draw_index maximo = se dibuja
  ultimo = arriba. Mismo painter's order final.
- `_process` playback: el port usa `frame_step` (extension propia
  documentada) para reducir rebuilds. Con `frame_step=1` es 1:1 con maru.
- `get_animation_length` / `validate_frame`: portados tal cual.

**Tests:** `tests/test_bounds_offset.gd` nuevo con 4 casos:
`compute_bounds_offset` con bbox (100, 200) -> (-100, -200), bbox (0, 0)
-> (0, 0), symbol inexistente -> (0, 0), shortcut de carpeta
`Folder/walk` -> bbox de `walk`. Suite: **13/13**.

**Post-F13 (obligatorio):** recalibrar offsets de los mods.
- Verificar trickyDJ con gdanimate post-F9: el sprite deberia verse
  centrado sin `pixel_offset` manuales.
- Re-correr Holy Quintet `MainMenuSprite`, anotar desplazamientos,
  ajustar `offset` (ahora con signo invertido).

### F8 — `FlxAnimateFrames.hx`: estado y fix del shortcut de carpetas

**Revision completa del archivo (707 lineas).** La mayoria de la
infraestructura ya estaba porteada; el unico fix funcional fue el shortcut
de nombres con carpeta.

**Fix aplicado — shortcut de nombres con carpeta.**

`FlxAnimateFrames.getSymbol` (maru FlxAnimateFrames.hx:90-155) tiene un
fallback: si el `SymbolInstance` referencia `"Symbol 3/walk"` pero el
dictionary tiene `"walk"` (o al reves), prueba el ultimo segmento del path
(`name.split("/").pop()`) antes de rendirse. Sin esto, cualquier atlas
exportado con carpetas de simbolos dibuja instancias faltantes (nada se
pinta donde va el sub-simbolo).

Antes el port hacia `symbols.has(key)` + `symbols[key]` directo en 8
lugares, asi que un `SN = "Folder/walk"` con `symbols = {"walk": ...}` no
matcheaba y el frame entero del sub-simbolo desaparecia.

`AdobeAtlas.get_symbol(name)` es el port fiel del shortcut. El port NO hace
lazy-load de simbolos inlined (SD) ni de LIBRARY/*.json — los carga eager
en `load_symbols` / `load_symbol_directory`. Equivalencia funcional (mismo
dictionary final), lookup O(1).

Lookups reemplazados:
- `draw_on` (141, 230): `not symbols.has(x)` -> `get_symbol(x) == null`,
  `symbols[key]` -> `get_symbol(key)`.
- `get_length_of` (308-318): ahora usa `get_symbol` con fallback a
  `stage_symbol` como el source.
- `draw_symbol` (408-457): `if not symbols.has(element.key): continue` ->
  `var sub_sym = get_symbol(element.key); if sub_sym == null: continue`,
  y los dos usos de `symbols[element.key]` -> `sub_sym`.
- `element_bounds` (709-714): mismo cambio.

**Lo que ya estaba portado (sin cambios):**
- Deteccion inlined vs non-inlined en `load_animation`: chequea
  `metadata.json` vs `SD` — mismo criterio que
  `isInlined = !exists("metadata.json")` de maru (FlxAnimateFrames.hx:325).
- `LIBRARY/*.json` via `load_symbol_directory` con subdirectorios — port de
  `listWithFilter(path + "/LIBRARY", ..., true)` (FlxAnimateFrames.hx:335).
- Spritemap id-based pairing en `load_spritemap`: usa `get_basename()` para
  el `.png` — equivalente a `split("spritemap")[1].split(".")[0]`
  (FlxAnimateFrames.hx:352).
- Metadata `FRT/W/H/BGC` con fallback 1280x720 / blanco en
  `_parse_stage_metadata` — port de FlxAnimateFrames.hx:405-410.
- `STI.SI.MX` -> `stage_transform` (FlxAnimateFrames.hx:412-414).
- Root symbol self-registration: `load_symbol(anim)` mete
  `symbols[SN] = gd_symbol` — mismo patron que
  `frames.dictionary.set(frames.timeline.name, ...)` (FlxAnimateFrames.hx:405).

**N/A (arquitectura distinta):**
- `_cachedAtlases` in-memory: el port cachea en disco (`.res`).
- `FlxAnimateSpritemapCollection`: ciclo de vida de FlxGraphic; Godot usa
  reference counting.
- `addAtlas` / `combineAtlas`: mix Adobe+Sparrow; el port no lo necesita.
- `setSymbolDirty`: baking de filters/masks, va a F13.
- `FilterQuality`: idem F13.

**Diferido (no vale la pena sin perfilado real):**
- `_cachedBounds` per-frame (diferido de F7).
- Pre-computo de `bounding_box` en `parse()`.
- Legacy Animate 2018 (`atlasInstance` param que construye un Timeline fake
  con un AtlasInstance): no portado. Ningun asset del mod lo usa.
- `MetadataJson.V/FLV` (version del exporter): cosmetico, no afecta render.

**Tests:** `tests/test_symbol_lookup.gd` nuevo con 5 casos: exact match,
shortcut directo, shortcut missing, sin slash sin match,
`get_length_of` con fallback a stage_symbol + shortcut. Suite: **12/12**.

**Regresion visual: cero esperada.** El cambio solo AGREGA un fallback
cuando el lookup directo falla; nunca cambia el resultado de un lookup que
ya funcionaba.

### F7 — `Timeline.hx` + `SymbolItem.hx`: divergencias y fixes

**Bug raiz corregido (fixup de F6):** `AdobeLayer.calculate_bounding_box`
y `AdobeSymbol.calculate_bounding_box` arrancaban de `Rect2()` vacio y
mergeaban. **`Rect2().merge(otro)` NO es `otro`**, es
`"(0,0,0,0) union otro"` = `Rect2(0, 0, ...)`. Cualquier capa cuyo primer
elemento tuviera bbox fuera del origen del atlas **metia (0, 0) al bbox de
la capa**, y el merge capa-por-capa del simbolo propagaba el error. Despues
`FlxAnimate.hx:224-225` hacia `matrix.translate(-bounds.x, -bounds.y)` con
ese bounds inflado -> **sprite cortado/desplazado. Bug raiz del trickyDJ.**

Fix: flag `first` como el source (`Timeline.getBounds`, maru Timeline.hx:
230-275) + skip de frames vacios (`if (frame == null ||
frame.elements.length <= 0) continue;`, Timeline.hx:255) y skip de
elementos sin area (`if (frameBounds.isEmpty) continue;`, Timeline.hx:259).

**SymbolItem.hx: casi N/A.** El archivo es un wrapper fino de Timeline:
- `createInstance(type)` -> ya portado en F3 (`adobe_symbol_instance.gd` +
  `animate_symbol.gd`).
- `transformationPoint = FlxPoint.get()` -> **solo inicializacion a (0,0)**.
  El TRP real del JSON lo escribe `SymbolInstance._loadJson` (F3).
  SymbolItem NO parsea TRP.
- `onSymbolCreate` hook -> settings callback, sin equivalente en el port.
- `timeline.libraryItem = this` -> backref SymbolItem->Timeline. En el port
  AdobeSymbol **es** SymbolItem+Timeline fusionados, backref N/A.

**Metodos portados a `adobe_symbol.gd` (Timeline.hx):**
- `name: StringName` + `_layer_map: Dictionary` + `rebuild_layer_map()`.
- `get_layer(ref)` (Timeline.hx:48-51): acepta String/StringName (por mapa)
  o int (por indice).
- `for_each_layer(cb)` (Timeline.hx:60-66).
- `get_frames_at_index(i)` (Timeline.hx:75-90).
- `get_elements_at_index(i)` (Timeline.hx:92-108).
- `get_frame_label_at_index(i)` (Timeline.hx:120-133).
- Static `expand_bounds(a, b)` (Timeline.hx:391-401): wrapper de `a.merge(b)`.
- Static `mask_bounds(masked, masker)` (Timeline.hx:406-424): interseca; si
  el masker esta vacio devuelve `masked` sin tocar.
- Static `apply_matrix_to_rect(rect, m)` (Timeline.hx:426-477): wrapper de
  `m * rect`. Godot aplica el mismo AABB de las 4 esquinas.

**Metodos portados a `adobe_atlas.gd`:**
- `whole_symbol_bounds(target, include_hidden=false)` (Timeline.hx:194-220):
  recorre todos los frames, expande el rect. Sin cache todavia
  (`_cachedBounds` de maru se difiere a F8 junto con los hooks de
  invalidacion).
- `symbol_bounds_origin(target, apply_stage_matrix=false)` (Timeline.hx:
  166-178): top-left del bounds. Es lo que un consumidor usa para
  `matrix.translate(-origin.x, -origin.y)`.

**Hallazgo contractual: `frame_indices` es DENSO desde 0.**

`Layer.frame_indices` es un array **denso desde 0**, un slot por frame de
duracion de cada keyframe, **sin respetar huecos** por `frame.starting_index`
(que si es timeline-global). Consecuencia: `Layer.getFrameAtIndex(i)` indexa
por el i-esimo frame **local** de la capa, no por el frame i del timeline.
Un keyframe con `I=2, DU=1` produce `frame_indices=[0]`, y
`getFrameAtIndex(0)` lo devuelve aunque su `starting_index=2`.

**Esto es fiel a maru, no un bug del port.** `test_layer.gd` (F6) y
`test_symbol.gd::_test_get_frames_and_elements_at_index` (F7) lo cubren.
Un futuro "fix" que pretenda meter huecos nulos en `frame_indices`
romperia el invariante que maru mantiene.

**Lo que NO se porto (a otro archivo / otro F):**
- `draw()` -> `animate_symbol.gd::_draw_adobe` (F9). Verificar alli el loop
  REVERSO de capas (`i = length - 1; i--`, Timeline.hx:312-328): si el port
  itera en orden natural, las capas quedan invertidas (Adobe Animate emite
  top-to-bottom, hay que dibujar bottom primero).
- `currentFrame` / `getCurrentElements()` -> vive en AnimateSymbol, no en
  AdobeSymbol (F9).
- `signalFrameChange(i, anim)` -> controller (F10).
- `_loadJson` -> ya portado en `adobe_atlas.gd::load_layers`.
- `findFrameLabelIndices` -> ya portado en `adobe_animate_controller.gd`.

**Anotado para F8:**
- `_cachedBounds` de maru (Timeline.hx:240-283) + `clearBoundsCache()`.
  Requiere hookear todos los puntos que invalidan (replace_frame del sprite,
  setKeyframe, cacheOnLoad).
- Pre-computar `bounding_box` en `parse()` (llamando
  `whole_symbol_bounds`) para que el getter lazy no recalcule.
- Verificar que `getWholeBounds` vs "merge de layer.bounding_box" difieran
  solo con clipping frame-level. Los assets de holyquintet + trickyclowned
  no tienen ese patron; el fallback local es correcto para ellos.
- Inconsistencia detectada: `adobe_atlas.gd::load_layers` resuelve
  `parent_layer` buscando hacia atras en `gd_symbol.layers` (solo capas ya
  procesadas), pero `migrate_all_layers_from_legacy` busca en TODO el array.
  Si el clipper esta DESPUES del clipped en el JSON, el parse vivo NO lo
  encuentra. Verificar contra Layer.hx real si "busca hacia arriba" es
  indice menor o mayor. No tocado en F7.

**Tests:** `tests/test_symbol.gd` nuevo con 9 casos: `layer.bbox` sin leak
de (0,0), `symbol.bbox` sin leak, frame vacio no infla bbox, `get_layer`
por nombre+indice, `for_each_layer`, `get_frames_at_index`,
`get_elements_at_index`, `get_frame_label_at_index`,
`whole_symbol_bounds`, `symbol_bounds_origin`. Suite: **11/11**.

**Regresion visual: cero esperada.** El fixup corrige un leak de origen que
estaba latente desde F2; para assets cuyo primer elemento del primer frame
arranca cerca de (0,0) del atlas el comportamiento es identico. Para
trickyDJ (que arranca lejos) el bbox deberia achicarse y el sprite
reubicarse correctamente.

### F6 — `Layer.hx`: divergencias encontradas y que se hizo

**Arreglado en este pase:**

1. **`frame_indices` (Layer.hx:34, :186-188).** El source mantiene un array
   `timeline_index -> keyframe_index`, un slot por frame de duracion de cada
   keyframe (`for (_ in 0...frame.duration) frameIndices.push(i)`). El port
   hacia un scan O(N) sobre `layer.frames` en `layer_frame_at_index()`. En
   JSON con keyframes de duraciones bien formadas coinciden, pero el source
   es O(1) y el port O(N), y con keyframes con gaps se comportan distinto.
   `AdobeLayer.frame_indices` + `get_frame_at_index()` lo portean tal cual.
   `_migrate_from_legacy()` rellena el array en caches viejos.

2. **`layerType` enum (Layer.hx:32, :200-213).** El source tiene
   `NORMAL / CLIPPER / CLIPPED / FOLDER`. El port solo tenia `clipping: bool`
   (CLIPPER vs resto) y CLIPPED implicito en `clipped_by != ""`. FOLDER no
   existia. `AdobeLayer.LayerType` es ahora el campo real.

3. **Precedencia `Clpb > LT` (Layer.hx:141-164).** Si `Clpb` esta presente la
   capa es CLIPPED y el bloque `else` (donde se evalua `LT`) **no corre**. El
   port viejo chequeaba los dos por separado, asi que una capa con ambos
   campos podia quedar CLIPPER y CLIPPED a la vez, o CLIPPER donde el source
   haria CLIPPED. Reproducido con fixture sintetico antes de tocar nada.

4. **FOLDER no parsea frames (Layer.hx:181-193).** `if (this.layerType !=
   FOLDER) { ... parse FR ... }`. El port lo trataba como NORMAL y si el JSON
   traia un `FR` en un folder lo parseaba igual.

5. **`parentLayer` es referencia directa (Layer.hx:150).** El source guarda
   `parentLayer = aboveLayer`. El port guardaba el nombre en `clipped_by` y
   hacia lookup por nombre cada vez en `frame_bounds()`. Ahora
   `AdobeLayer.parent_layer` es la referencia.

**Sin cambios de comportamiento, verificados equivalentes:**

- `getFrameAtIndex` con `FlxMath.maxInt(index, 0)` -> `maxi(index, 0)`.
- `frameCount` es property calculada sobre `frameIndices.length` -> `get_frame_count()`.
- `visible`/`hidden` son el mismo flag con la polaridad invertida (el port
  mantiene `hidden` para que el default `false` sea "mostrar").

**Fix colateral en `test_clipping.gd`:** el test aserteaba que `clipped_by`
se limpia a `""` cuando el clipper no aparece. Eso era comportamiento del
**cne-flixel-animate** (port viejo), no de maru. `Layer.hx:158-163` de maru
**solo** pone `parentLayer = null`, `isMasked = false`, `visible = false` —
no toca `Clpb`. El test se corrigio a maru. Sigue siendo la unica assertion
que cambio; el resto del test pasaba tal cual.

**Migracion de caches legacy.** Los `.res` cacheados de gdanimate guardan
`AdobeLayer` con `clipping: bool` en lugar de `layer_type`. Al cargar un
cache viejo, `AdobeSymbol.migrate_all_layers_from_legacy()` hace 3 pasos:
(1) infiere `layer_type` desde `clipping`, (2) rellena `frame_indices` desde
las duraciones de los keyframes, (3) resuelve `parent_layer` para CLIPPED sin
referencia. Idempotente. Se llama desde `adobe_atlas.gd::parse()` en la rama
del cache.

**Tests:** nuevo `tests/test_layer.gd` con 5 casos:
`frame_indices` (con duraciones 1/3/2), precedencia `Clpb > LT`, FOLDER sin
frames, `parent_layer` referencia directa, migracion + idempotencia. Suite
**10/10** (test_layer + test_clipping corregido + los 8 previos).

**Regresion visual: cero.** Los bounds y el render de assets reales
(holyquintet + trickyclowned) no cambian con F6 — el cambio es de estructura
interna (indices, tipo, ref), no de geometria.

**Anotado para despues:** `setKeyframe` / `setBlankKeyframe` (Layer.hx:73-105)
estan sin portear; el source los usa para el baking de mascaras, que cae en
F13. `forEachFrame` esta portado pero el port no lo usa todavia.

### F1 — `FlxAnimateJson.hx`: divergencias encontradas y que se hizo

**Arreglado en este pase:**

1. **Resolucion de claves por campo.** maru no tiene un "modo optimizado"
   global: cada getter hace `this.<corta> ?? this.<larga>`
   (`FlxAnimateJson.hx:129-130` y ~90 mas). El port elegia el esquema una vez
   (`optimized = data.has("AN")`) y miraba una sola clave, asi que un
   `Animation.json` de claves mezcladas (raiz optimizado + `LIBRARY/*.json`
   en formato largo, que Adobe si produce) perdia campos en silencio.
   `AdobeColorMatrix.parse` tenia el mismo problema (`ColorJson`,
   `FlxAnimateJson.hx:646-700`). Los parametros `optimized` quedan por
   compatibilidad de firma pero ya no deciden nada.

2. **`MatrixJson.resolve` completo** (`FlxAnimateJson.hx:717-747`). Nuevo
   `AdobeAtlas.resolve_matrix()`, usado por los tres call sites. Agrega el
   fallback `POS`/`Position` del texture atlas legacy de Adobe Animate 2018
   (`[1,0,0,1,pos.x,pos.y]`), que no existia: sin el, cada elemento de un
   atlas 2018 caia en identidad y se amontonaba en el origen.

3. **`from3Dto2D` con la rama de perspectiva** (`FlxAnimateJson.hx:749-776`).
   Se activa cuando `m03`/`m13`/`m23` != 0 o `m33` != 1 — Adobe lo escribe con
   rotacion 3D en la timeline. La formula se porteo literal, incluido que el
   `/ z` aplica solo a `m[12]`/`m[13]` y no al parentesis entero (parece un bug
   de precedencia upstream; se replica igual, el objetivo es dibujar lo mismo).
   La forma objeto del M3D (`m00..m33`) ahora pasa por la misma reduccion que
   la forma array, asi el chequeo de perspectiva tambien corre para ella.

4. **Despacho de elementos SI/ASI/TFI** (`Frame.hx:216-249`). Era un if/else
   binario y todo lo que no fuera `SI` caia en `load_atlas_sprite`; un `TFI`
   reventaba ahi. Ahora se prueba SI -> ASI -> TFI (salteado, F12) -> nada.
   Ademas `E` puede faltar entero y el source lo chequea; antes se iteraba null.

5. **Blend legacy desde el nombre de instancia** (`SymbolInstanceJson.get_B`,
   `FlxAnimateJson.hx:222-240`). Si no hay `B`/`blend`, el blend viene
   codificado en `IN` como `"_bl<N>_..."`. **Esto cambia el render de assets
   reales**: `anim_accolades` y `anim_gauntlet` del mod holyquintet tienen
   131 y 150 instancias `_bl0_ACCOLADE_LIGHT` (indice 0 = ADD) y ningun `"B"`,
   o sea que hasta ahora se dibujaban en NORMAL y ahora van en aditivo — que es
   lo que hace flixel-animate. **Requiere verificacion visual en device.**

6. **`MetadataJson` null-safe** (`FlxAnimateJson.hx:625-644`): el bloque
   metadata inline puede faltar; antes framerate quedaba en null.

**Detectado y NO arreglado todavia (queda para el archivo que lo consume):**

| Gap | Source | Donde se resuelve |
|---|---|---|
| `FrameJson.B` — blend a nivel keyframe (`this.B ?? this.blend`) | `FlxAnimateJson.hx:135-138`, `Frame.hx:214` | F5 (`Frame.hx`): necesita campo en `AdobeLayerFrame` + plumbing de render |
| `FrameJson.SND` — sonido por keyframe (`N`/`SNC`/`LP`/`RP`) | `FlxAnimateJson.hx:145-165`, `Frame.hx:251+` | F5; el port no tiene subsistema de audio por timeline |
| `SymbolInstanceJson.BM` — bitmap legacy 2018 embebido en la instancia | `FlxAnimateJson.hx:201`, `FlxAnimateFrames.hx:157-175` | F8: se resuelve en `getSymbol(name, atlasInstance)`, que arma un SymbolItem de un solo frame |
| Fallback de nombre "shortcut" para simbolos en carpeta (`a/b/c` -> `c`) | `FlxAnimateFrames.hx:117-123` | F8 |
| `MetadataJson.V` / `FLV` (version del exporter) | `FlxAnimateJson.hx:637-641` | F8; maru los lee pero el port no ramifica por version todavia |
| `FilterJson` completo (BLF/ACF/DSF/GF/BF/GBF/GGF + `resolve()` de la forma objeto) | `FlxAnimateJson.hx:259-459` | F13 |
| `TextFieldInstanceJson` + `TextFieldAttributesJson` | `FlxAnimateJson.hx:487-600` | F12 |

### F2 — `Element.hx` + `AtlasInstance.hx`: divergencias y que se hizo

**Arreglado en este pase:**

1. **`AnimateElement.visible`** (`Element.hx:19`, true en el ctor
   `Element.hx:29`). `Frame.hx:423-426` gatea CADA elemento con el:
   `for (element in elements) if (element.visible) element.draw(...)`.
   El port no tenia el campo y dibujaba todo siempre. No es lo mismo que
   `AdobeLayer.hidden`, que es por capa. El motor lo usa internamente para el
   baking (`Frame.hx:339`, `MovieClipInstance.hx:173`).

2. **Guard de frame inexistente** (`AtlasInstance.hx:98-99`:
   `if (frame == null || frame.frame == null) return;`). Un `ASI` que apunta
   a un nombre ausente del spritemap daba un `AdobeAtlasSprite` con
   `texture == null` y `draw_atlas_sprite` hacia `texture.get_rid()` →
   *"Cannot call method 'get_rid' on a null value"*, por frame y por elemento
   roto. Reproducido con un test antes del fix.

3. **La matriz se asigna aunque el frame falte** (`AtlasInstance.hx:43-48`:
   `getByName` puede dar null pero `this.matrix = data.MX.toMatrix()` corre
   igual). El port devolvia un sprite nuevo y perdia la matriz.

4. **`tile_matrix` explicita**: port de
   `FlxFrame.prepareBlitMatrix(mat, blit = false)` (flixel 6.2.0,
   `FlxFrame.hx:184-204`), cacheada en el ctor de AtlasInstance
   (`AtlasInstance.hx:58`) y aplicada primero en draw
   (`AtlasInstance.hx:101-103`). Estaba duplicada inline en
   `draw_atlas_sprite()` y `calculate_bounding_box()`.

5. **`replace_frame()`**: port de `AtlasInstance.replaceFrame`
   (`AtlasInstance.hx:70-86`), incluido el `adjustScale` que escribe la
   escala sobre `tileMatrix.a`/`.d` — con el bug de rotacion que el propio
   source marca con un TODO (`AtlasInstance.hx:74`), replicado tal cual.

**Verificado equivalente, sin cambio de codigo:**

| Item del source | Por que ya esta bien |
|---|---|
| Orden de las matrices en `draw` (`tileMatrix` → `matrix` → `parentMatrix`, `AtlasInstance.hx:101-103`) | Haxe usa convencion de filas y Godot de columnas, asi que el equivalente es `parent * matrix * tile`, que es lo que hace `draw_atlas_sprite` |
| `getBounds` aplica las matrices **de a una** re-encajonando en el medio (`AtlasInstance.hx:175-177` + `Timeline.applyMatrixToRect`), el port compone y aplica una sola vez | La tile matrix es identidad o una rotacion de 90 grados EXACTOS, y esas preservan el eje: el AABB intermedio no pierde nada, los dos caminos dan el mismo rect |
| `sprite.rotated` → `ANGLE_NEG_90` (`FlxAnimateFrames.hx:409`), `frame` = `(x, y, w, h)` del spritemap, `offset` = `(0,0)` | El port lee las mismas 4 celdas y arma `rotateByNegative90() + translate(0, w)` |
| `ElementType` enum (ATLAS/GRAPHIC/MOVIECLIP/BUTTON/TEXT, `Element.hx:71-78`) y los `toXInstance()` casts | En GDScript el despacho es por clase (`element is AdobeSymbolInstance`) y el subtipo por `AdobeSymbolInstance.type` |
| `destroy()` (`Element.hx:64-69`) | Los `Resource` de Godot son refcounted |
| `drawPixelsFlash` (`AtlasInstance.hx:126-137`) y `drawBoundingBox` (`AtlasInstance.hx:186-225`) | `#if flash` / `#if FLX_DEBUG`, no aplican |

**Detectado y NO arreglado todavia:**

| Gap | Source | Donde se resuelve |
|---|---|---|
| `isOnScreen` — culling por elemento contra la camara | `AtlasInstance.hx:141-166` | Diferencia arquitectonica: el port crea un `canvas_item` por capa y deja cullear al renderer de Godot. Sin efecto visual; revisar recien si aparece un problema de performance |
| `parentFrame` + `setDirty()` — el elemento avisa a su keyframe que se ensucio | `Element.hx:21`, `AtlasInstance.hx:84-85` | F5 (`Frame.hx`). Hoy `replace_frame` obliga al consumidor a marcar `frame_dirty` + `queue_redraw` a mano |
| `BakedInstance` + `Blend.resolve(this.blend, blend)` | `AtlasInstance.hx:233-244` | F5/F11: es parte del sistema de baking de keyframes, que el port no tiene |
| `getBounds(includeFilters, useCachedBounds)` — los dos flags se ignoran | `AtlasInstance.hx:168` | F7 (bounds cacheados) y F13 (bounds con filtros) |

### F3 — `SymbolInstance.hx` + `MovieClipInstance.hx`: divergencias y que se hizo

**Arreglado en este pase:**

1. **`getFrameIndex` transcrito literal** (`SymbolInstance.hx:100-140`).
   `symbol_instance_frame()` era una reimplementacion a mano, equivalente en
   5 de los 6 casos pero distinta en el sexto: **LOOP con `FF > 0` y sin
   `LF`**. El source hace `FlxMath.wrap(frameIndex, 0, lastIndex)`, o sea que
   al pasarse del final vuelve al frame **0** del sub-simbolo; la version
   vieja envolvia dentro de `[FF, final]` y volvia a `FF`. Con `FF=7` en un
   simbolo de 10 frames: source `7,8,9,0,1,2,...`, viejo `7,8,9,7,8,9`.
   Se agrega `_flx_wrap()`, port de `FlxMath.wrap` (max **inclusivo**, al
   reves que `wrapi()` de Godot).

2. **MovieClip congelado = frame 0** (`MovieClipInstance.hx:220-223`:
   `return swfMode ? super.getFrameIndex(...) : 0;`). Literal 0, **no**
   `firstFrame`. Era un TODO pendiente de confirmar; resuelto con datos (ver
   la medicion abajo).

3. **Instancia a un simbolo inexistente** (`SymbolInstance.hx:57-58`:
   `if (libraryItem == null) visible = false;`). El port iba directo a
   `symbols[element.key]` y el error de acceso a Dictionary **abortaba la
   funcion**: un solo nombre roto dejaba de dibujar el resto del keyframe y
   del layer. El chequeo va en el loop de dibujo, no en el parseo, porque
   `load_symbols()` carga de a uno y los simbolos posteriores todavia no
   estan en el diccionario.

4. **Alpha 0 saltea el subarbol entero** (`SymbolInstance.hx:190-211`:
   `if (transform.alphaMultiplier <= 0) return;`, dentro del `if (isColored)`).
   Mismo resultado en pantalla, pero evita crear los `canvas_item` del
   subarbol y que un subarbol invisible agrande el `screen_rect` del
   backbuffer.

5. **Precedencia de blend anidado, estaba invertida**
   (`SymbolInstance.hx:213` → `Blend.resolve`). El source se queda con el
   blend **propio** salvo que sea NORMAL; el port se quedaba con el
   **heredado** salvo que el heredado fuera NORMAL. Una instancia MULTIPLY
   dentro de una SCREEN se dibujaba SCREEN. Extraido a `resolve_blend()`
   para que sea una funcion sola como en el source.

**Cuanto de esto cambia lo que se ve** (medido sobre los 40 `Animation.json`
del mod, branch `origin/holyquintet-port`):

| Cambio | Instancias que lo tocan | Que cambia de verdad |
|---|---|---|
| `getFrameIndex` LOOP sin LF | 5736, en 24 archivos (sayaka-base 1873, kyoko-base 700, madoka-base 602, gf-base 601) | **9**, todas en `characters/kyubey-small`: solo se nota cuando la duracion del keyframe supera la cola que queda desde FF hasta el final del sub-simbolo. Conteo de primer nivel, no sigue anidamiento: es piso, no techo |
| MovieClip congelado → 0 | 591 instancias MC | **0**: las 591 tienen `FF = 0` |
| Blend anidado | — | **0**: el unico blend del mod es el ADD legacy de accolades/gauntlet, sin anidar |
| Simbolo inexistente, alpha 0 | — | **0** en los assets actuales; son guards |

Las 32 capturas golden-image salen identicas fuera de la franja del overlay
despues de los cinco cambios.

**Verificado equivalente, sin cambio de codigo:**

| Item del source | Por que ya esta bien |
|---|---|
| El `switch (color.M)` de `SymbolInstance.hx:60-80` (AD / CA / CBRT / T) | `AdobeColorMatrix.parse` hace lo mismo. El source trabaja los offsets en 0-255 (`ColorTransform` de OpenFL) y el port en 0-1, con el `/255` en AD y los valores ya normalizados en CBRT y Tint. Ademas el source **asigna** el transform y el port hace `*=` desde una identidad, que es lo mismo |
| `LoopType` (LOOP / PLAY_ONCE / SINGLE_FRAME, `SymbolInstance.hx:267-281`) | `AdobeSymbolLoopMode` tiene los mismos tres, y el parseo (`:47-52`) ya estaba porteado |
| `swfMode` sale de `parent._settings.swfMode` (`MovieClipInstance.hx:44`) | En el port es `AdobeAtlas.movie_clips_play`, un `@export` del atlas. Mismo alcance: por atlas, no por instancia |
| `transformationPoint` / `TRP` (`SymbolInstance.hx:54-55`) | maru lo parsea y lo guarda pero **nunca lo lee** para dibujar (las unicas otras menciones son `FlxAnimateJson.hx:216` y `SymbolItem.hx:64`, que solo lo inicializa). Dato muerto; no se portea |
| `destroy()`, `toString()`, los `toXInstance()` casts | Refcounting de Godot / despacho por clase |

**Detectado y NO arreglado todavia:**

| Gap | Source | Donde se resuelve |
|---|---|---|
| `isSimpleSymbol()` — marca un simbolo de un solo frame para el baking | `SymbolInstance.hx:146-159`, usado por `Frame.hx:317` | F5 |
| `getBounds` con el re-resolve de `libraryItem` ("patch-on fix for a really weird fucking bug") | `SymbolInstance.hx:163-185` | F7 |
| `Frame.__isDirtyCall → NORMAL` en `Blend.resolve` | `Blend.hx` | F5 (sistema de baking) |
| Filtros y baking del MovieClip: `setFilters`, `setDirty`, `_bakeFilters`, `_bakedFrames`, `_filterQuality`, `expandFilterBounds` | `MovieClipInstance.hx:27-32, 91-178, 192-206` | F13 |
| `cacheOnLoad` (bakear todos los frames al cargar) | `MovieClipInstance.hx:40-47, 77-82` | F8 / F13 |

### F4 — `ButtonInstance.hx`: divergencias y que se hizo

De ButtonInstance estaba porteada la mitad de "que frame muestro segun el
estado" (`getFrameIndex`, `ButtonInstance.hx:53-56`), pero **el estado nunca
cambiaba**: `cur_state` se quedaba en UP para siempre, `last_hitbox` no lo
escribia nadie y la senal `clicked` no la emitia nadie. El docstring decia
que la logica vivia en `AnimateSymbol._unhandled_input` y en `draw_symbol`, y
ninguna de las dos existia.

**Prerrequisito que hubo que portear primero: la cadena de bounds por frame.**
El hitbox de un boton es, textualmente, los bounds del frame **HIT** de su
sub-simbolo (`ButtonInstance.hx:45-51`), y el port no tenia forma de calcular
los bounds de un simbolo *en un frame*. Lo que si tenia, `AdobeSymbol.bounding_box`,
es el equivalente de `getWholeBounds` (`Timeline.hx:203`), la union sobre
**todos** los frames — para un hitbox no sirve. Se porteo:

| Nuevo en `adobe_atlas.gd` | Source |
|---|---|
| `symbol_bounds()` | `Timeline.getBounds` (`Timeline.hx:244-290`) |
| `layer_frame_at_index()` | `Layer.getFrameAtIndex` |
| `frame_bounds()` | `Frame.getBounds` (`Frame.hx:165-196`) |
| `element_bounds()` | `Element` / `AtlasInstance` / `SymbolInstance`.`getBounds` |
| `mask_bounds()` | `Timeline.maskBounds` |
| `instance_frame_index()` | el despacho de `getFrameIndex` por tipo, extraido de `draw_symbol` porque los bounds necesitan exactamente el mismo |

Tres detalles del source que es facil errarle y quedaron tal cual:
`Frame.getBounds` **no** chequea `element.visible` (ese flag solo se mira en
el loop de dibujo, `Frame.hx:423-426`); `applyMatrixToRect` sobre un rect
vacio devuelve un **punto** en `(m.tx, m.ty)`, no un rect en el origen; y una
capa clipeada recorta sus bounds contra los del clipper (`Frame.hx:186-192`).

**El input:** `draw_symbol()` calcula el hitbox de cada boton que dibuja y lo
junta en `_button_scratch` (mismo patron que `_backbuffer_scratch`);
`draw_on()` lo pasa a coordenadas locales y lo entrega por
`AnimateDrawInfo.buttons`; `AdobeButtonInstance.update_state()` es el port de
`updateButtonState` (`ButtonInstance.hx:73-121`); y
`AnimateSymbol._update_buttons()` hace el polling una vez por frame.

**Dos desvios deliberados del source**, los dos documentados en el codigo:

| Desvio | Por que |
|---|---|
| El hitbox va en coordenadas **locales del nodo**, no de camara (`ButtonInstance.hx:71`) | No se invalida cuando el nodo se mueve, asi que sobrevive al camino barato del backbuffer cache, que no vuelve a pasar por `draw_symbol()` |
| El polling vive en el **nodo**, no en el dibujo (`ButtonInstance.hx:61`) | En Flixel `draw()` corre siempre; en Godot `_draw()` solo corre si alguien encola un redraw, asi que un boton quieto nunca reaccionaria. La decision por boton igual vive en `AdobeButtonInstance`, como en el source |

**Verificado equivalente / no aplica:**

| Item del source | Estado |
|---|---|
| Rama `#elseif FLX_TOUCH` (`ButtonInstance.hx:96-119`) | Misma logica sobre el primer dedo. Godot emula mouse desde touch por default, asi que el camino del mouse ya la cubre |
| `drawBoundingBox` del hitbox en violeta (`ButtonInstance.hx:65-68`) | `#if FLX_DEBUG`, no aplica |
| `ButtonState` (UP/OVER/DOWN/HIT = 0..3) | Ya estaba, con los mismos valores |

**Detectado y NO arreglado todavia:**

| Gap | Source | Donde se resuelve |
|---|---|---|
| Cache de bounds por frame (`useCachedBounds`) | `Timeline.hx:249-256, 285-286` | F7 |
| Bounds expandidos por filtros (`includeFilters`) | `MovieClipInstance.hx:117-125` | F13 |
| `getWholeBounds` con `includeHiddenLayers` y el `_bounds` cacheado del timeline | `Timeline.hx:203-242, 367` | F7 |

### F5 — `Frame.hx`: divergencias y que se hizo

**Arreglado en este pase:**

1. **Blend a nivel keyframe** (`FrameJson.B` → `Frame.hx:214`
   `this.blend = frame.B`, aplicado en `Frame.hx:389`
   `var blend = Blend.resolve(this.blend, blend);`). Un keyframe puede traer
   su propio blend, que pisa al heredado para todos sus elementos. Estaba
   anotado como gap desde F1. En `draw_symbol` se resuelve una vez por capa
   (solo hay un keyframe activo por capa) y reemplaza al heredado tanto para
   la recursion de elementos como para el material y el `screen_rect` de la
   capa. Lo escribe BetterTextureAtlas; Adobe a secas no lo emite, y los 40
   `Animation.json` del mod tienen **0** keyframes con `B`.

2. **Defaults del ctor** (`Frame.hx:49-53`: `index = 0`, `duration = 1`). El
   port los tomaba del JSON sin chequear null, asi que un keyframe sin `I` o
   sin `DU` reventaba al asignar Nil a un int tipado.

3. **`find_frame_label_indices` acepta el simbolo** — esto cierra el fallo de
   frame labels que venia en rojo. Ver abajo.

### El fallo de frame labels: el test estaba mal, no el codigo

`find_frame_label_indices('walk')` devolvia 0 indices y el test lo daba por
bug del port. Al leer el motor, las dos causas reales fueron:

1. **Faltaba un parametro.** `addByFrameLabel`, `addByFrameLabelIndices` y
   `findFrameLabelIndices` (`FlxAnimateController.hx:41, 95, 189`) toman un
   `?timeline` **opcional**. Vacio = `getDefaultTimeline()` =
   `_animate.library.timeline`, que es el simbolo **raiz** del
   `Animation.json` (`FlxAnimateFrames.hx:425`), o sea `stage_symbol`. El
   port no tenia el parametro, asi que los labels que viven en un simbolo de
   la libreria eran inalcanzables. Ahora las tres funciones aceptan
   `symbol_name`, y la animacion registrada se queda con ese simbolo
   (`FlxAnimateController.hx:79` `anim.timeline = usedTimeline`).

2. **El trim estaba mal.** `Timeline.findFrameLabelIndices` compara con
   `frame.name.rtrim() == label`: rtrim, solo a la derecha, y solo sobre el
   **nombre del keyframe**. El port hacia `strip_edges()` sobre los dos lados
   y sobre los dos strings, asi que un label con espacios adelante matcheaba
   donde el motor no.

**Y el test pedia algo que el motor no hace**: ponia los labels en
`WithLabels`, dejaba `stage_symbol = "Anim5"` (sin labels) y esperaba que la
busqueda sin simbolo los encontrara. Corregido para chequear las dos cosas —
que sin simbolo devuelva vacio (lo correcto) y que con `"WithLabels"` los
encuentre — mas un caso de rtrim. **Con esto la suite queda en 9/9.**

**Verificado equivalente, sin cambio de codigo:**

| Item del source | Por que ya esta bien |
|---|---|
| `_drawElements` gatea con `element.visible` (`Frame.hx:423-426`) | Porteado en F2 |
| `Frame.getBounds` (`Frame.hx:165-196`), incluido el recorte contra el clipper | Porteado en F4 como prerrequisito del hitbox |
| `this.name = frame.N ?? ""` (`Frame.hx:212`) | Ya estaba |
| `add()` / `insert()` / `forEachElement()` | `elements` es un `Array` de Godot; agregar, insertar e iterar ya estan |

**Detectado y NO arreglado todavia:**

| Gap | Source | Donde se resuelve |
|---|---|---|
| Sonido por keyframe: `SND`, `sound`, `soundSync`, y el switch event/start/stop/stream de `signalFrameChange` | `Frame.hx:254-283, 350-380` | Necesita un subsistema de audio por timeline que el port no tiene. **0 keyframes con `SND`** en los 40 `Animation.json` del mod |
| `onFrameLabel.dispatch(name)` al cruzar un keyframe con label | `Frame.hx:344-348` | F10 (la senal vive en el controller) |
| Baking de mascaras/filtros: `_bakeFrame`, `_bakedFrames`, `_bakedIndices`, `_dirty`, `_requireBake`, `__isDirtyCall`, `FilterRenderer.maskFrame`, y el camino de `draw()` que dibuja el frame bakeado | `Frame.hx:286-341, 396-414` | F13 |
| `setDirty()` → `parent.setSymbolDirty(...)` | `Frame.hx:88-105` | F8 (vive en `FlxAnimateFrames`) |
| `convertToSymbol()` — empaqueta elementos en un simbolo nuevo en runtime | `Frame.hx:112-140` | Feature de autoria; sin consumidores. Depende de `SymbolItem.createInstance` (F7) |

### Correccion: el "ciclo de class_name" NO existe

Una nota anterior de esta auditoria reportaba un bug de GDScript: el par
`AnimateSymbol.anim: AdobeAnimateController` + `AdobeAnimateController._sprite:
AnimateSymbol` supuestamente causaba
`Parse Error: Could not resolve external class member "anim"` en cualquier
script externo, dejando la Etapa 4 inusable.

**Eso era falso.** La causa real era `.godot/global_script_class_cache.cfg`
desactualizado: un run via `-s` NO reescanea el proyecto, usa ese cache tal
como esta, y ahi faltaban las clases nuevas del addon. Los sintomas eran
"Could not find type AdobeButtonInstance in the current scope" en
`adobe_atlas.gd` y, de arrastre, el error de `anim`. Despues de correr
`--import` una vez, el codigo original (con los dos tipos declarados) parsea
y corre perfecto. No hay que romper ningun tipo.

**OJO**: `--import` reescribe `project.godot` y le borra secciones (incluido
`_global_script_classes` y los comentarios de rendering). Hay que restaurarlo
con `git checkout -- project.godot` despues; el cache regenerado vive en
`.godot/` y sobrevive.

### Las capturas golden-image NO son deterministas

Dos corridas de la MISMA version dan hash distinto en 27 de los 32 PNGs. Las
diferencias caen **todas** en la franja `y = 9..27`, donde el autoload
`DebugDisplay` dibuja FPS/MEM/SCENE/MODS. Cualquier comparacion automatica
tiene que saltear esas filas o da 27 falsos positivos. Con ese filtro, el pase
F1 cambio exactamente 3 imagenes (accolades f90/f179, gauntlet f90), todas por
el blend `_bl0` del punto 5.

## Fuente de verdad ANTERIOR (historico): CORRECCION IMPORTANTE

La tarea original asumia que el mod usa `Dot-Stuff/flxanimate` (el addon "FlxAnimate"
publico de Haxe). **Eso es incorrecto.** Verificado en dos capas:

1. **Declaracion**: `CodenameCrew/CodenameEngine/project.xml:140` declara
   `<haxelib name="flixel-animate"/>` (sin `git=`, o sea "resolvelo del registry").
2. **Instalacion real**: `CodenameCrew/CodenameEngine/building/libs.xml`
   linea 22 declara explicitamente:
   `<git name="flixel-animate" url="https://github.com/CodenameCrew/cne-flixel-animate" skipDeps="true"/>`.
   El `Setup.hx` de Codename (`commandline/commands/Setup.hx`) lee ese XML y
   hace `haxelib git` en vez de `haxelib install` — el registry nunca se
   consulta.

Y `FunkinSprite.hx:3` importa `animate.FlxAnimate` (paquete `animate`, no
`flxanimate`). Todo apunta a **`CodenameCrew/cne-flixel-animate`** (aunque su
`haxelib.json` diga version 1.5.0 y apunte al upstream `MaybeMaru/flixel-animate`
como source-of-truth del haxelib, es el fork de Codename el que se compila) — un
fork/reescritura casi completa de FlxAnimate que Codename Engine mantiene por su
cuenta, con una estructura de archivos distinta (`FlxAnimateController`,
`internal/elements/*.hx`, `internal/Timeline.hx`, `internal/StageBG.hx`, etc.) que además
coincide con los nombres de archivo que la tarea original esperaba encontrar
(`FlxAnimateJson.hx`, `internal/Timeline.hx`, `internal/elements/*.hx`) — esos archivos
simplemente no existen en `Dot-Stuff/flxanimate` (que tiene otro layout: `src/animate/`,
sin paquete `internal`, con `FlxSymbol`/`FlxTimeline`/`FlxLayer` en vez de
`SymbolInstance`/`Timeline`/`Layer`).

**Toda referencia de archivo:linea en este documento y en los comentarios del codigo
apunta a `CodenameCrew/cne-flixel-animate`** (clonado en `/root/refs/cne-flixel-animate`
durante esta sesion), no a `Dot-Stuff/flxanimate`. Varios comentarios pre-existentes en
`adobe_atlas.gd`, `animate_symbol.gd` y `animate_draw_info.gd` citaban lineas del repo
equivocado (ej. "FlxAnimate.hx:283-297" para `prepareDrawMatrix`, que en el repo correcto
esta en la linea 304). Se corrigieron en este pase.

Si en el futuro hay que clonar los repos de nuevo:
```bash
git clone https://github.com/CodenameCrew/cne-flixel-animate.git   # el que importa
git clone --depth 1 https://github.com/CodenameCrew/CodenameEngine.git
# Dot-Stuff/flxanimate NO hace falta para nada de este addon.
```

## Tabla de estado

| Feature | Estado | Fuente (cne-flixel-animate) | Port (gdanimate/adobe/) | Nota |
|---|---|---|---|---|
| Parseo claves optimized/legacy | ✅ | `FlxAnimateJson.hx` (abstracts `get_*`) | `adobe_atlas.gd:has_pair/get_pair` | Cobertura equivalente para las claves que el mod usa |
| Matrix 3x2 (`MX`) | ✅ | `MatrixJson.a..ty` (indices 0-5) | `adobe_atlas.gd:parse_matrix` (rama size==6) | Verificado byte a byte |
| Matrix 3D (`M3D`, sin perspectiva) | ✅ | `MatrixJson.from3Dto2D` (indices 0,1,4,5,12,13) | `adobe_atlas.gd:parse_matrix` (rama default) | Verificado byte a byte |
| Matrix 3D con perspectiva (`m3D[3\|7\|11]!=0`) | ➖ | `from3Dto2D` rama proyectiva | no implementado | No se usa en exports 2D normales de Adobe Animate/BTA; muy baja prioridad |
| `TRP` (transformation point) | ✅ (correctamente ignorado) | Se parsea a `SymbolInstance.transformationPoint` **pero no se usa en ningun lado del pipeline de dibujo** (grep confirma 0 usos fuera de asignacion/destroy) | No se parsea | El port coincide con el engine real: TRP es metadata muerta, el M3D ya trae la transformacion horneada. Pregunta abierta del brief original, resuelta. |
| Stage matrix (`STI`/`SI`) | ✅ | `FlxAnimateFrames.hx:430-431` | `adobe_atlas.gd:load_animation` (`stage_transform`) | Igual |
| `applyStageMatrix` | ⚠️ (aproximado, con fix) | `FlxAnimate.hx:304-319` `prepareDrawMatrix` | `adobe_atlas.gd:draw_on` (`apply_stage_matrix`) | Ver seccion dedicada abajo |
| Loop modes | ✅ (corregido este pase) | `SymbolInstance.hx:49-54,102-142` — solo LOOP/PLAY_ONCE/SINGLE_FRAME, cualquier otro valor cae en LOOP | `adobe_atlas.gd` (`AdobeSymbolLoopMode`) | Se eliminaron `REVERSE_ONE_SHOT`/`REVERSE_LOOP` y las claves `"POR"`/`"REV"`/`"reverse"`/`"reverseloop"` — **no existen en el engine real**, eran inventados. Ver seccion dedicada. |
| Ventana `firstFrame`/`lastFrame` (wrap) | ✅ | `SymbolInstance.hx:getFrameIndex` | `adobe_atlas.gd:symbol_instance_frame` | Estructuralmente identico una vez sacado el reverse fabricado |
| MovieClip vs Graphic (`ST`) | ✅ | `Frame.hx:_loadJson` (switch en `si.ST`) | `adobe_atlas.gd:load_symbol_instance` | `"MC"`/`"movieclip"` -> movieclip, resto -> graphic |
| `movieClipsPlay` (MC toca su propio frame vs congelado) | ⚠️ | `MovieClipInstance.getFrameIndex`: solo avanza si `swfMode` (default **false**) | `adobe_atlas.gd:draw_symbol` (`movie_clips_play`, default **false**) | Default coincide (false = MC congelado en su primer frame), pero el port cuando esta en `true` hace wrap manual (`wrapi`) en vez de llamar a `getFrameIndex` normal - revisar si un MC con `swfMode` real respeta first/lastFrame igual que un Graphic. Baja prioridad, no se usa en HQ. |
| Boton (`ST == "B"`/`"button"`) | ⚠️ (parser + render, falta input) | `ButtonInstance.hx` | `AdobeButtonInstance` + `AdobeSymbolType.BUTTON` + rama en `draw_symbol` | Fix 6a: parser detecta ST=B/button, crea `AdobeButtonInstance`, `draw_symbol` llama `button_frame_index(length)` = `min(cur_state, length-1)` (ButtonInstance.hx:76-79). Falta 6b: input handling (`_unhandled_input` en AnimateSymbol, actualizar `cur_state`/`last_hitbox`, disparar `clicked`). Sin caso real en HQ, pero el fix es para completitud. |
| TextField (`TFI`) | ❌ | `TextFieldInstance.hx` | No implementado, mismo fallback que Button | Idem, baja prioridad |
| Blend modes (numeros 0-14) | ✅ | `FlxAnimateJson.hx` tipa `B` directo como `openfl.display.BlendMode` (ADD=0..SUBTRACT=14) | `AdobeSymbolInstance.AdobeBlendMode` | Verificado contra el enum real de OpenFL - los numeros coinciden exactamente |
| Blend modes (matematica por modo) | ✅ (mayoria), ❌ (2 modos, coincide con upstream) | `internal/filters/Blend.hx` (shader GLSL de referencia) | `atlas_shader.gdshader:fragment()` | Ver seccion dedicada — DARKEN/MULTIPLY/LIGHTEN/SCREEN/OVERLAY/HARD_LIGHT/ADD/SUBTRACT/DIFFERENCE/INVERT verificados formula por formula. ALPHA/ERASE hacen `discard` en vez de aplicarse - pero el engine real **tampoco los implementa** (su propio shader de referencia no tiene esos casos en el switch, caen al default `result = a`). LAYER/SHADER correctamente tratados como no-op (= NORMAL), igual que upstream. |
| Blend por transparencia del layer (mix por alpha) | ❌ | `Blend.hx:167` `result.rgb = mix(a.rgb, result.rgb, b.a)` al final de cada blend | No se hace | El shader del port nunca atenua el resultado del blend por el alpha del propio fragmento antes de recomponer. Para sprites totalmente opacos no se nota; en bordes semi-transparentes de un sprite con blend mode puede divergir. Arquitectural: el pipeline de Godot (canvas_item con alpha compositing automatico) no es 1:1 con el compositing manual de dos bitmaps de OpenFL. No es un fix de una linea. |
| GlowFilter | ❌ (codigo muerto) | `SymbolInstanceJson.F` (filtros van en la INSTANCIA, ver mas abajo) | `AdobeLayerFrame.glow` — el campo existe y `draw_symbol()` lo lee, pero **nada en el parser lo llena nunca** (`load_frame()` no asigna `gd_frame.glow` en ningun punto) | `layer_glow` siempre es `{}`, la rama entera de glow en `draw_symbol()` (~40 lineas) nunca se ejecuta. Ver seccion dedicada. |
| BlurFilter / DropShadowFilter / BevelFilter / AdjustColorFilter | ❌ | `FlxAnimateJson.hx:FilterJson.toBitmapFilter()`, filtros van en `SymbolInstanceJson.F`, solo se aplican a `MovieClipInstance` (`MovieClipInstance.hx:_bakeFilters`) | `AdobeSymbolInstance.filters` existe como campo (`@export_storage var filters: Array[AdobeFilter]`) pero **nunca se llena** — `load_symbol_instance()` no lee la clave `"F"`/`"filters"` del JSON en ningun punto | Mismatch arquitectural: en el engine real los filtros son propiedad de la INSTANCIA de simbolo (solo movieclips los hornean, via render-a-bitmap offscreen); el port los modelo como si fueran del layer-frame, lo cual ademas nunca se conecto. Implementarlo bien requiere un pipeline de "baking" a textura (blur real, drop shadow) que no existe hoy en Godot-side. Fuera de alcance de un fix chico. |
| ColorMatrix: Advanced/Alpha/Brightness/Tint | ✅ | `SymbolInstance.hx` (constructor, switch en `color.M`) | `adobe_color_matrix.gd:parse` | Verificado formula por formula incluyendo la normalizacion 0-255 vs 0-1 (Godot Color ya viene 0-1, Advanced divide por 255, coincide) |
| StageBG (rect de fondo) | ⚠️ | `StageBG.hx` + `FlxAnimate.hx:229,375-381` (`renderStage`, default **false**) | `adobe_atlas.gd:draw_on` (`render_stage`, default **false**) | Default coincide (apagado). El port dibuja un rect simple con `stage_color`; el real escala una textura 1x1 con matrix propia mas compleja (incluye stage matrix, render-texture bounds). Como esta apagado por default y el mod HQ no lo activa, no importa hoy - si algun dia se activa, revisar la formula de `StageBG.hx:30-42`. |
| Clipping/masking (capas `Clp`/`Clpb`) | ✅ (aproximado, nativo) | `Layer.hx:_loadJson` (busca capa `CLIPPER` con nombre igual arriba en la lista) + `FlxAnimate.hx` renderiza el clipper a camara separada y compone con blend | `adobe_atlas.gd:draw_symbol` usa `CanvasItemMaterial`/`canvas_item_set_canvas_group_mode` nativo de Godot (`CLIP_ONLY`/`TRANSPARENT`) | Mecanismo distinto (Godot tiene clipping nativo por canvas group, Flash compone dos bitmaps a mano) pero deberia dar resultado visual equivalente para el caso simple. Diferencia menor: el port busca el clipper por nombre en un dict (`rids.get(layer.clipped_by, parent)`) sin confirmar que esa capa sea realmente tipo `Clp`; el original exige que la capa encontrada sea `CLIPPER` (`Layer.hx:150`). Edge case de nombres duplicados, muy improbable en la practica. |
| Cache de backbuffer / RIDs | ➖ | No existe en el original (Flash no tiene el concepto) | `AnimateDrawInfo.backbuffer_cache`, `_use_backbuffer_cache` | Optimizacion propia del port para Godot, no rompe fidelidad visual, no aplica comparacion 1:1 |
| Framerate / stage W,H,BGC (metadata) | ✅ | `FlxAnimateFrames.hx:417-427` | `adobe_atlas.gd:load_animation/_parse_stage_metadata` | Igual, incluye el caso `metadata.json` externo vs `MD` inline |
| Symbol dictionary (SD vs LIBRARY/) | ✅ (con estrategia distinta) | Lazy-load on-demand (`getSymbol()`) | Eager: carga todo en `parse()` | Mismo resultado final, distinta estrategia de timing/performance. No es un bug. |

## Loop modes: `REVERSE_ONE_SHOT`/`REVERSE_LOOP` eran fabricados

**Este es el hallazgo mas importante de este pase**, y ya esta corregido en el commit.

`SymbolInstance.hx:269-273` del engine real:
```haxe
enum abstract LoopType(Int) to Int
{
    var LOOP;
    var PLAY_ONCE;
    var SINGLE_FRAME;
}
```
Solo tres valores. Y el mapeo desde JSON (`SymbolInstance.hx:49-54`):
```haxe
this.loopType = switch (data.LP)
{
    case "PO" | "playonce": LoopType.PLAY_ONCE;
    case "SF" | "singleframe": LoopType.SINGLE_FRAME;
    default: LoopType.LOOP;
}
```
Cualquier valor que no sea exactamente `"PO"`/`"playonce"` o `"SF"`/`"singleframe"` -
incluido `"LP"`, y cualquier variante no reconocida - cae en `LOOP` por default. **No hay
reproduccion en reversa en el engine real.**

El port (antes de este pase) tenia `AdobeSymbolLoopMode.REVERSE_ONE_SHOT` y
`.REVERSE_LOOP`, mapeados desde claves JSON `"POR"` y `"REV"` que no existen en ningun
`Animation.json` real exportado por Adobe Animate ni en el codigo que las leeria. No hay
forma de que esto haya sido producido por un export real - alguien las agrego
especulando. Se eliminaron:

- `addons/gdanimate/adobe/adobe_symbol_instance.gd`: el enum ahora solo tiene
  `LOOP`/`ONE_SHOT`/`FREEZE_FRAME` (valores 0/1/2, sin cambios para las que quedan).
- `addons/gdanimate/adobe/adobe_atlas.gd`: `load_symbol_instance()` ya no reconoce
  `"POR"`/`"REV"`/`"reverse"`/`"reverseloop"`; cualquier valor no reconocido (incluido
  `"LP"`) cae en `LOOP`, igual que el engine real.
- `symbol_instance_frame()`/`_symbol_instance_offset()`: se saco toda la logica de
  `is_reverse` (mirror del offset, `span-1-difference`). La logica de ventana
  (`firstFrame`/`lastFrame`, wrap cuando `lastFrame < firstFrame`) se mantuvo intacta -
  esa parte SI esta verificada contra `SymbolInstance.hx:102-142` y es identica
  estructuralmente.

Impacto: si algun `Animation.json` del mod HQ tenia `"LP":"POR"` o `"LP":"REV"` en algun
lado, ese elemento se reproducia en reversa en Godot pero se hubiera reproducido **hacia
adelante en loop** en el juego real (Codename Engine). Falta verificar en device si algun
symbol se veia "raro"/reversado antes de este fix - pedirle al usuario que compare.

## `applyStageMatrix`: que tan fiel es el fix existente

El pipeline real (`FlxAnimate.hx`, sin `postStageMatrixApply` que es `false` por default):

```
drawAnimate():
  matrix.translate(-bounds.x, -bounds.y)      # FlxAnimate.hx:225

prepareDrawMatrix():
  matrix.concat(library.matrix)                            # FlxAnimate.hx:316 (stage matrix)
  matrix.translate(bounds.x*library.matrix.a,
                    bounds.y*library.matrix.d)              # FlxAnimate.hx:317
  matrix.translate(-origin.x, -origin.y)                     # :321
  matrix.translate(-frameOffset.x, -frameOffset.y)           # :333
  matrix.scale(scale.x, scale.y)                             # :335
  matrix.rotateWithTrig(...)  # si angle != 0                # :343
  matrix.concat(_skewMatrix)  # si hay skew                  # :349
  getScreenPosition(...); matrix.translate(_point.x,_point.y)  # :358-359
```

`bounds` es el bounding box del timeline completo (`Timeline._bounds`), un concepto de
"encuadre" que `FlxSprite` necesita para saber donde esta el (0,0) logico del frame
dentro del dibujo real. **`AnimateSymbol` (el port) no tiene un concepto equivalente**:
no extiende `FlxSprite`, dibuja los `RID` de canvas_item directamente en las coordenadas
nativas de Animate, sin normalizar a un frame con bounds propios. Por eso el fix actual
(`draw_on()` en `adobe_atlas.gd`) no reproduce `translate(-bounds.x,-bounds.y)` ni el
`translate(bounds.x*matrix.a, ...)` que le sigue al stage matrix - los omite enteros y
aplica el stage matrix como un simple `transform *= stage_transform` despues de un
`translate(draw_info.offset)`.

El comentario en el codigo ya documenta (y este pase lo verifico) que esto **coincide**
con el pipeline real solo en el caso especial donde el M3D del stage es traslacion pura
(`a=d=1, b=c=0`), que es el caso de todos los `Animation.json` del mod HQ revisados
(`Story_Animation`: M3D=[1,0,0,0, 0,1,0,0, 0,0,1,0, -798.35,-464.65,0,1]). Si algun
`Animation.json` futuro trae un stage matrix con rotacion o escala no trivial, esta
aproximacion se rompe y hay que portar la formula completa (incluyendo el concepto de
`bounds`, que tendria que aproximarse con el bounding box de `AdobeSymbol` — ya existe
`AdobeSymbol.bounding_box` / `AdobeLayer.bounding_box`, calculado en
`adobe_symbol.gd:calculate_bounding_box`, que podria servir de base).

**Veredicto: ⚠️ aproximacion verificada para el caso real que usa el mod, no una
reproduccion general.** No se toco en este pase (ya estaba arreglado para el caso que
importa); se corrigieron las referencias de archivo:linea en los comentarios, que citaban
el repo equivocado.

## Blend modes: verificacion formula por formula

`atlas_shader.gdshader:fragment()` contra `internal/filters/Blend.hx` (el shader GLSL de
referencia que usa el motor real, `Blend.hx:93-186`). Convencion: en el shader de
referencia `a` = fondo/destino (`bitmap1`), `b` = la capa con el blend mode (`bitmap2`);
en el port, `screen_c` (SCREEN_TEXTURE) = fondo, `COLOR` = la capa con el blend mode -
misma convencion.

| Modo (int) | Formula referencia | Formula port | Coincide |
|---|---|---|---|
| DARKEN (2) | `min(a,b)` | `darken(COLOR,screen_c)` = `min(fg,bg)` | ✅ (simetrico) |
| MULTIPLY (9) | `a*b` | `multiply(COLOR,screen_c)` | ✅ (simetrico) |
| LIGHTEN (8) | `max(a,b)` | `lighten(COLOR,screen_c)` | ✅ (simetrico) |
| SCREEN (12) | `screen(a,b)` (simetrico) | `screen(COLOR,screen_c)` | ✅ |
| OVERLAY (11) | `overlay(a=bg,b=fg)` | `overlay(screen_c,COLOR)` | ✅ orden correcto |
| HARD_LIGHT (5) | equivalente a `overlay(b=fg,a=bg)` (derivado algebraicamente, ver abajo) | `overlay(COLOR,screen_c)` | ✅ orden correcto |
| ADD (0) | `a+b`, luego `mix(a,result,b.a)` | `add(COLOR*COLOR.a, screen_c)`, sin el mix final | ⚠️ formula base ok, falta atenuar por alpha del blend layer |
| SUBTRACT (14) | `a-b` = `bg-fg` | `subtract(screen_c,COLOR)` = `bg-fg` | ✅ orden correcto |
| DIFFERENCE (3) | `abs(a-b)` (simetrico) | `difference(COLOR,screen_c)` | ✅ |
| INVERT (6) | `1-a` (ignora b por completo) | `invert(screen_c)` = `1-bg` | ✅ |
| ALPHA (1) | no implementado en el switch de referencia (cae a `result=a`, sin efecto) | `discard` | ✅ misma intencion (ambos hacen que la capa no afecte lo ya dibujado), mecanismo distinto |
| ERASE (4) | idem ALPHA, no implementado | `discard` | ✅ idem |
| LAYER (7) | tratado como NORMAL (`Blend.hx:79`: `if blend==NORMAL\|\|LAYER\|\|SHADER: draw sin blend`) | sin rama -> se comporta como NORMAL | ✅ |
| SHADER (13) | idem LAYER | sin rama -> NORMAL | ✅ |

Derivacion de HARD_LIGHT: la formula de referencia
`hardlight(a,b) = (b>0.5) ? 1-(1-a)(1-2(b-0.5)) : a*2b` es algebraicamente igual a
`overlay(b,a)` (Overlay con los argumentos invertidos) para ambas ramas - confirmado a
mano. Como el port ya tiene una funcion `overlay(base,blend)` = formula estandar de
Photoshop/Flash, usar `overlay(COLOR,screen_c)` para HARD_LIGHT (base=capa con blend,
blend=fondo) es exactamente la formula correcta, no una coincidencia.

Gaps reales (ninguno bloqueante para el mod HQ, que no parece usar blends complejos en
sus menus):
1. **Falta el `mix(a.rgb, result.rgb, b.a)` final** que la referencia aplica a TODOS los
   modos antes de recomponer - el port solo lo hace parcialmente para ADD (via
   premultiply manual). Para sprites opacos no importa; para bordes con alpha parcial en
   un sprite con blend mode puede divergir. Arreglarlo bien requiere repensar como Godot
   compone `COLOR.a` despues del shader (el canvas_item ya vuelve a hacer alpha blending
   con `COLOR.a` al final, lo que puede doble-aplicar el efecto) - no es un cambio de una
   linea, requeria pruebas visuales en device que no se pudieron hacer en este pase.
2. La condicion `blend_mode > -1 && blend_mode != 10` que el brief marcaba como
   sospechosa: revisada, es inofensiva. `blend_mode` nunca es negativo (el enum va de 0 a
   14, default 10=NORMAL), asi que `> -1` es siempre verdadero y no cambia nada; el `!=
   10` es el skip correcto para NORMAL (no hay blend que aplicar). No se toco.

## GlowFilter y demas filtros: codigo muerto, arquitectura equivocada

Dos problemas separados, documentados para que quien lo retome no repita el analisis:

1. **El campo nunca se llena.** `AdobeLayerFrame.glow` (declarado en
   `adobe_layer_frame.gd`) y `AdobeSymbolInstance.filters`
   (`adobe_symbol_instance.gd`) existen como propiedades, y `adobe_atlas.gd:draw_symbol()`
   tiene ~40 lineas de logica lista para usar `layer_glow` (activa canvas group
   `TRANSPARENT`, pasa `glow_color`/`glow_blur`/`glow_strength`/etc al shader). Pero
   `load_frame()` en `adobe_atlas.gd` **nunca asigna `gd_frame.glow`**, y
   `load_symbol_instance()` **nunca lee `"F"`/`"filters"` del JSON** para llenar
   `symbol_instance.filters`. Confirmado por grep: cero asignaciones fuera de la
   declaracion. Es codigo inerte, no rompe nada (siempre toma el camino "sin glow") pero
   tampoco hace nada.

2. **El modelo de datos no coincide con el engine real aunque se conectara.** En
   `cne-flixel-animate`, los filtros (`blurFilter`/`glowFilter`/`dropShadowFilter`/
   `bevelFilter`/`adjustColorFilter`) son parte de `SymbolInstanceJson.F`
   (`FlxAnimateJson.hx:198`), es decir, propiedad de una **instancia de simbolo**, no de
   un layer-frame. Y solo se hornean (`_bakeFilters`, render-to-bitmap offscreen) para
   `MovieClipInstance` (`MovieClipInstance.hx:129-180`) - un `SymbolInstance` tipo
   Graphic nunca aplica filtros. El port modelo esto como si fuera un atributo del
   layer-frame (`AdobeLayerFrame.glow`), lo cual es estructuralmente distinto de donde
   realmente vive el dato en el JSON y en el engine.

**Veredicto: ❌ no implementado.** Conectar el parseo (leer `"F"` en
`load_symbol_instance`) es trivial, pero hacer que el GlowFilter/BlurFilter/etc.
*rendericen* correctamente requeriria: (a) decidir si se aplican solo a MovieClips como
el original, (b) para blur/dropshadow, un pipeline de render-a-textura offscreen que hoy
no existe en el lado Godot (el shader de glow actual es una aproximacion por sampling
radial en el fragment shader, no un blur real ni coincide con como OpenFL hornea un
`GlowFilter`/`BlurFilter` a bitmap). Es trabajo de varias sesiones, no un fix chico - se
deja documentado para decidir con el usuario si vale la pena, dado que no lo parece usar
el mod HQ en sus menus actuales (los `Animation.json` de `anim_*` revisados no traen
`"F"` en sus `SYMBOL_Instance`).

## `parser/` es codigo muerto, confirmado

`grep` de `ParsedAtlas`/`CollectedSprite`/etc. contra todo el repo (fuera de
`addons/gdanimate/parser/` mismo) no encontro ninguna referencia. Nadie lo importa, no
esta en ninguna escena, no tiene `class_name` usado desde afuera. **No se toco**, como
pide la tarea. Si en algun momento se decide borrarlo, es seguro hacerlo, pero eso es
decision del usuario, no de este pase.

## Que falta por auditar / verificar en device

- Confirmar con el usuario que el fix de `apply_stage_matrix` (de antes de este pase)
  efectivamente alinea `anim_freeplay`/`anim_gauntlet`/`anim_accolades`/`anim_gallery` en
  el menu principal, y que `anim_story`/`anim_credits`/`anim_settings`/`anim_shop` siguen
  bien.
- Confirmar que ningun symbol del mod HQ dependia de `"LP":"POR"`/`"REV"` (deberia dar
  igual o mejor ahora, pero vale la pena mirar el diff visual si algo cambia de
  aspecto).
- `characters/` (fuera de HQ): correr con `apply_stage_matrix=false` (default) y
  confirmar que no cambio nada - los fixes de este pase solo tocaron loop modes
  (deberian afectar characters/ tambien si alguno usaba `"LP":"POR"/"REV"`, pero es
  improbable ya que esas claves nunca fueron reales) y comentarios.

---

# Etapa 0 (port completo): hallazgos adicionales

Todo lo de abajo es del segundo pase, alcance "port completo y fiel de flixel-animate",
NO de "arreglar el menu de holyquintet". Ver `DESIGN.md` para el plan de trabajo; esta
seccion es el estado, esa es el plan. Referencias verificadas contra
`CodenameCrew/cne-flixel-animate` clonado en `/root/refs/cne-flixel-animate` (o donde el
siguiente pase lo clone), lectura completa de los 22 `.hx` del paquete `animate`.

## Toolchain de verificacion: que funciona y que no (importante, leer antes de reintentar)

**Godot headless: viable.** `Godot_v4.7.1-stable_linux.x86_64` corre con
`xvfb-run -a ./Godot ... --rendering-driver opengl3` (Mesa llvmpipe, software OpenGL) y
`get_viewport().get_texture().get_image().save_png(...)` produce PNGs correctos - probado
con un `ColorRect` de prueba, pixel exacto. `--headless` puro (sin Xvfb) NO sirve para
esto: el rendering server no llega a dibujar nada y `RenderingServer.frame_post_draw`
nunca dispara. Esto habilita golden-image tests del lado Godot sin problema.

**Oraculo Haxe (correr flixel-animate de verdad): bloqueado, necesita decision del
usuario.** Intentado en orden:
1. `haxelib install lime/openfl/flixel` (vanilla de haxelib.org) - el redirect de
   `lib.haxe.org` a `haxelib-files.haxe.org` rompe el cliente de `haxelib` (aunque
   `curl -L` sigue el redirect sin problema - es un bug/limitacion del cliente viejo
   4.1.0). Workaround: bajar el zip con curl y `haxelib install <archivo local>`.
2. Con vanilla flixel 6.2.0 + openfl 9.5.2, `cne-flixel-animate` **no tipa**:
   `FlxAnimate.hx` espera que `FlxSprite` (heredado de flixel) tenga campos `layer`,
   `shaderEnabled`, `wrapMode`, `frameOffsetAngle`, `doAdditionalMatrixStuff` que no
   existen en el `FlxSprite` vanilla de HaxeFlixel. `Blend.hx` espera que
   `openfl.display.BlendMode` tenga `COLORDODGE`/`COLORBURN`/`SOFTLIGHT`/`EXCLUSION`/
   `HUE`/`SATURATION`/`COLOR`/`LUMINOSITY` (no estan en el `BlendMode` vanilla de OpenFL)
   y que `OpenGLRenderer` tenga un campo privado `__complexBlendsSupported` que tampoco
   existe. **Confirma con evidencia de compilador, no solo de texto, lo que `libs.xml` ya
   decia**: `cne-flixel-animate` esta escrito contra los forks propios de CodenameCrew,
   no contra flixel/openfl posta.
3. Clonado y registrado via `haxelib dev` `CodenameCrew/cne-flixel` (rama `cne`),
   `cne-openfl` (rama `cne`), `cne-lime` (rama `cne`) - los mismos que `libs.xml` pide.
   **Tampoco tipa**: ahora el error esta DENTRO de `cne-flixel` mismo
   (`AssetFrontEnd.hx` referencia `useOpenflAssets`/`getPath`/`directory`, que no existen
   en ningun lado de `cne-lime` ni `cne-openfl` clonados - confirmado por grep). Esto
   huele a que el HEAD actual de la rama `cne` de cada repo no es una combinacion
   compatible entre si (las tres ramas se mueven independientemente; CodenameEngine
   probablemente los pinea a commits SHA especificos en su propio CI/lockfile, que no
   tengo) - o falta un define de compilacion que no adivine.
4. Mas alla del tipado: `FilterRenderer.hx`/`RenderTexture.hx` (el pipeline de filtros)
   usan `openfl.display.OpenGLRenderer`/`Context3D`/`gl.readPixels` DIRECTAMENTE - para
   correr eso de verdad hace falta el target nativo (`hxcpp`), que a su vez es
   **`CodenameCrew/cne-hxcpp`**, otro fork mas, con su propio build nativo (compilador
   C++, `haxelib run lime rebuild hxcpp`, potencialmente horas). No lo intente: es
   demasiado para este pase sin aprobacion.

**Que decision necesito del usuario para seguir con esto:**
- Opcion A: seguir persiguiendo el toolchain exacto de CodenameEngine (necesito los
  commits pineados exactos de `cne-lime`/`cne-openfl`/`cne-flixel`/`cne-hxcpp` que uso su
  build real - el usuario los tiene si tiene un checkout que compila, via
  `git log`/`git rev-parse` en cada `.haxelib/<lib>/.dev` o el lockfile que use su CI).
  Con eso puedo intentar de nuevo, pero seguramente termino necesitando compilar hxcpp
  nativo igual para llegar al pixel real - horas de build, sin garantia de que ande
  headless sin GPU real (Context3D/OpenGLRenderer puede necesitar mas que Mesa
  llvmpipe).
- Opcion B (la que recomiendo, ver abajo): **oraculo de logica pura**, no el engine
  completo. Extraigo (copio literal, no reescribo) las funciones puras que SI importan
  para fidelidad - parseo de matrices (`MatrixJson.from3Dto2D`/`toMatrix`),
  `SymbolInstance.getFrameIndex`, `Timeline.applyMatrixToRect`,
  `AdjustColorFilter.getColorMatrix` - a un programa Haxe standalone sin flixel/openfl
  (`haxe --interp`, sin dependencias, corre en segundos). Esto reproduce EXACTO el
  computo (mismo texto fuente, no una reinterpretacion mia) para todo lo que no depende
  de FlxG/render, que es la mayoria de lo que importa para "misma posicion en pantalla".
  Lo que NO cubre: composicion final de pixeles (blend GPU, filtros horneados a bitmap,
  antialiasing) - eso queda en "verificado por lectura + comentado en el codigo +
  pendiente de comparacion con screenshots del usuario al final", igual que ya se hizo
  con los blend modes en el pase anterior.
- Opcion C: usar screenshots/video del mod original que el usuario ya tiene como el
  oraculo de facto para todo lo que la Opcion B no cubre, en vez de perseguir pixel
  render real de Haxe. Esto es mas lento (ciclo por chat) pero no depende de que el
  toolchain de CNE llegue a compilar.

**Mi recomendacion: B + C combinadas.** B me da certeza matematica en la parte que mas
bugs de posicion/tiempo genera (matrices, frame index, loop). C cubre lo que B no puede
(pixeles finales). A queda como algo que retomar solo si B+C no alcanzan para algo
puntual y el usuario tiene los pines exactos a mano.

## Nueva tabla: features fuera del primer pase

| Feature | Estado | Fuente (archivo:linea) | Complejidad estimada | Nota |
|---|---|---|---|---|
| `FlxAnimateController` (`addByTimeline`/`addBySymbol`/`addByFrameLabel`/`addByFrameLabelIndices`/`addBySymbolIndices`/`findFrameLabelIndices`, señal `onFrameLabel`) | ⚠️ parcial | `FlxAnimateController.hx` completo (414 lineas) | Mediano | API de animaciones nombradas al estilo `sprite.animation.add()`. Hoy `AnimateSymbol` solo expone `symbol`+`frame` crudos, sin registro de animaciones con nombre. Requiere ademas frame labels (ver fila siguiente), que hoy no se parsean. |
| Frame labels (`"N"`/`name` en `FrameJson`) | ✅ | `FlxAnimateJson.hx:125,140-141` (`FrameJson.N`), usado en `Frame.hx:216` (`this.name = frame.N ?? ""`) y `Timeline.hx:131-171` (`getFrameLabelAtIndex`/`findFrameLabelIndices`) | Chico (parseo) | `AdobeLayerFrame` (`adobe_layer_frame.gd`) no tiene campo `name`/label. Sin esto, `FlxAnimateController` no se puede portear (depende de labels para `addByFrameLabel`). |
| `ButtonInstance` (estados UP/OVER/DOWN/HIT, hit-test mouse/touch, `onClick`) | ⚠️ parcial (6a mergeado) | `internal/elements/ButtonInstance.hx` (156 lineas) | `AdobeButtonInstance` + `AdobeSymbolType.BUTTON` + `draw_symbol` rama | **6a mergeado** (commit `102f6767`): estado UP/OVER/DOWN/HIT, `cur_state`, `clicked` signal, `button_frame_index()`, parser detecta `ST=B`, `draw_symbol` usa el frame por estado. **Falta 6b**: input handling (`_unhandled_input` en `AnimateSymbol`, actualizar `cur_state` segun mouse/touch, hitbox en screen space con el transform completo, disparar `clicked` en just_pressed). 6b requiere verificacion en device. |
| `TextFieldInstance` (texto dinamico horneado a bitmap) | ❌ | `internal/elements/TextFieldInstance.hx` completo (127 lineas) | Grande | El original usa `openfl.text.TextField`+`TextFormat`, renderiza a `BitmapData` y lo trata como un `AtlasInstance` mas. Godot no tiene un equivalente directo de "renderizar texto a textura on-demand" tan directo - la opcion mas fiel es un `SubViewport` con un `Label`/`RichTextLabel` capturado a `ViewportTexture`, cacheado hasta que el texto cambie (paralelo a `_dirty`/`redraw()` del original). Prioridad baja: no hay evidencia de que el mod HQ use `TFI` en sus `Animation.json` (los revisados no traen `textFIELD_Instance`). |
| `FlxSpriteElement` (envolver un `FlxSprite` arbitrario como elemento de timeline) | ➖ | `internal/elements/FlxSpriteElement.hx` completo (210 lineas) | Grande si hiciera falta | Feature de nicho incluso en el engine real (dejar que un `FlxSprite` cualquiera del juego participe de una timeline de Animate, con blend/color/posicion sincronizados). No hay indicio de que ningun mod lo necesite. Propongo dejarlo en ➖ hasta que un caso real lo pida - implementarlo a ciegas es el tipo de trabajo especulativo que la tarea pide evitar. |
| `MovieClipInstance.swfMode` (repro tipo SWF: todas las frames animan; default false = solo frame 0 "congelado" tipo Animate) | ⚠️ | `internal/elements/MovieClipInstance.hx:223-226` (`getFrameIndex`/`isSimpleSymbol` overrides) | Chico | El port tiene `movie_clips_play` (default false, igual semantica que `swfMode=false`: MC muestra su primer frame nomas). La diferencia: cuando esta en `true`, el original llama al `getFrameIndex` COMPLETO de `SymbolInstance` (respeta loop mode, first/lastFrame igual que un Graphic). El port en cambio hace `wrapi(symbol_frame + difference, 0, symbols[element.key].length)` a mano en `adobe_atlas.gd:draw_symbol` (~linea 321), ignorando loop mode/first/lastFrame del MovieClip cuando `movie_clips_play=true`. Fix chico: llamar a `symbol_instance_frame()` (la misma funcion que ya usan los Graphics) en vez de un wrap manual. |
| Filtros: pipeline de horneado completo (`FilterRenderer.hx` + `RenderTexture.hx`) | ❌ | `internal/FilterRenderer.hx` (686 lineas), `internal/RenderTexture.hx` (148 lineas) | Grande | Pipeline real: renderiza el MovieClip a un `BitmapData` offscreen via `OpenGLRenderer`+`Context3D` (acceso directo a GL, `gl.readPixels`), aplica cada `BitmapFilter` (GPU shader pass o CPU fallback segun plataforma), expande bounds segun el filtro (`expandFilterBounds`). Analogo natural en Godot: `SubViewport` + `ViewportTexture`, que YA confirme que renderiza correcto headless (ver arriba). Requiere una clase nueva (`AdobeRenderTexture` o similar) que envuelva un `SubViewport`, mas logica de "expandir bounds por filtro" replicada de `expandFilterBounds` (formulas ya leidas y simples: blur extiende por `ceil(blurX/Y)`, glow igual si no es inner, dropshadow por `distance*cos/sin(angle)+blur`). |
| `BlurFilter` (real, no aproximado) | ❌ | `internal/filters/StackBlur.hx` (stack blur real, algoritmo de Mario Klingemann portado a Haxe/lime) + `FilterRenderer.__renderCpuFilter`/`__renderGpuFilter` | Mediano-Grande | Godot no tiene stack blur nativo. Dos caminos: (a) shader de blur gaussiano de 2 pasadas (rapido, tiempo real, NO pixel-identico a stack blur pero visualmente muy cercano - lo que ya se usa para el glow actual del port), o (b) portar el algoritmo StackBlur exacto operando sobre `Image` en GDScript/CPU (pixel-identico pero lento, no apto para tiempo real en Android). Recomiendo (a) para MovieClips en pantalla, documentado como aproximacion deliberada. |
| `GlowFilter` (horneado, no el aproximado actual) | ⚠️ | `FlxAnimateJson.hx:399-400` (`new GlowFilter(color,alpha,blurX,blurY,strength/100,quality,inner,knockout)`, openfl nativo) | Mediano | El port ya tiene un glow por sampling radial en `atlas_shader.gdshader` (ver pase anterior, seccion filtros) pero ligado a `AdobeLayerFrame.glow`, que nunca se llena (codigo muerto). Con el nuevo modelo (filtros en la instancia, solo MovieClip), hay que: (1) conectar el parseo real de `"F"` en `load_symbol_instance`, (2) decidir si el shader-sampling actual alcanza o si hace falta hornear a textura como el original (mas fiel, mas caro). |
| `DropShadowFilter` | ❌ | `FlxAnimateJson.hx:395-396` | Mediano | No hay nada portado. Formula de extension de bounds ya leida (`FilterRenderer.hx:639-648`), la sombra en si es un blur+offset+color-flat del mismo sprite debajo del original - portable con el mismo pipeline de `RenderTexture` que blur/glow. |
| `BevelFilter` | ➖/❌ | `FlxAnimateJson.hx:407-414`, condicional `#if (flash \|\| openfl >= "9.5.0")` | Grande, baja prioridad | Disponible en el target real (Android usa openfl >= 9.5.0, no es flash-only). No hay evidencia de uso en HQ. Postergar. |
| `GradientBevelFilter`/`GradientGlowFilter` | ➖ (no aplica ni en el original) | `FlxAnimateJson.hx:415-427`, ambos bajo `#if flash` exclusivamente | Ninguna | Confirmado: en el target que compila Codename (cpp/Android, no flash), estos dos filtros **ni siquiera existen en el engine real** - `toBitmapFilter()` cae al `default:` (warning "not currently supported on this target") si algun `Animation.json` los trae. No hace falta portearlos nunca; si un JSON los referencia, replicar el mismo warning y listo. |
| `AdjustColorFilter` (brightness/hue/contrast/saturation) | ❌ | `internal/filters/AdjustColorFilter.hx` completo (79 lineas) - formula de 4 matrices 4x5 multiplicadas (brillo, contraste, saturacion, hue-rotation con luminancia perceptual) | Chico-Mediano | Formula matematica pura, sin dependencia de render - portable directo a GDScript como una funcion que arma un `ColorMatrixFilter`-equivalente (mismo concepto que `AdobeColorMatrix` ya existente, pero derivado de 4 parametros en vez de leido directo del JSON). Aplicarlo requiere el pipeline de horneado (MovieClip only) igual que los demas filtros. |
| `MaskShader` (compositing de mascara en el horneado de clipping) | ➖ | `internal/filters/MaskShader.hx` completo (87 lineas) | No aplica directo | Es el mecanismo de bajo nivel que usa `FilterRenderer.maskFrame` para el clipping HORNEADO (cuando el contenido enmascarado necesita bakearse a bitmap, ej. porque tiene sus propios filtros). El port ya resuelve clipping con `canvas_item_set_canvas_group_mode` nativo de Godot (ver pase anterior) sin necesitar hornear nada - **ese mecanismo nativo sigue siendo el approach correcto**, este archivo solo aplicaria si en algun momento se implementa el horneado completo de filtros y un clip necesita convivir con un filtro en el mismo frame. |
| Sparrow: `flipX`/`flipY` en `SubTexture` | ✅ | `cne-flixel/flixel/graphics/frames/FlxAtlasFrames.hx:263-264,302` (`fromSparrow`) | Chico | `sparrow_atlas.gd:parse()` lee `x/y/width/height/rotated/frameX/frameY/frameWidth/frameHeight` pero nunca `flipX`/`flipY`. Si algun personaje del mod tiene frames Sparrow marcados flip en la herramienta de export, se van a ver sin flipear. Nota: Sparrow NO es parte de `flixel-animate` (vive en `flixel.graphics.frames.FlxAtlasFrames`, core de HaxeFlixel) - es un sistema aparte que el port reimplementa con su propia convencion de agrupamiento por prefijo+4-digitos (valida, pero distinta de como el motor real arma animaciones con nombre via `addByPrefix`). |
| Sparrow: rechazo de formato v1 | ➖ | `FlxAtlasFrames.hx:257-258` (`throw "Sparrow v1 is not supported, use Sparrow v2"` cuando falta `width` pero hay `w`) | Trivial si hace falta | Edge case de compatibilidad con herramientas viejas. Sin evidencia de que el mod lo necesite. |
| `postStageMatrixApply` | ❌ | `FlxAnimate.hx:90-99` (doc), `:310-319` y `:353-356` (aplicacion: antes vs despues del scale/rotate/skew del sprite) | Chico una vez resuelta la Etapa 1 de stage matrix general | Default `false` en el original (mismo pipeline que ya aproxima el port). Portear el caso `true` requiere primero tener la formula general de stage matrix (no solo la aproximacion de traslacion pura) - ver "Stage matrix (aproximado)" en la tabla del primer pase. |
| `Timeline._bounds` como concepto general (no solo para stage matrix) | ⚠️ | `Timeline.hx:196-295` (`getBounds`/`getWholeBounds`, con cache), usado por `FlxAnimateController.updateTimelineBounds` para `frameWidth`/`frameHeight`/`origin` de todo el sprite | Mediano | El port ya tiene un equivalente parcial (`AdobeSymbol.bounding_box`/`AdobeLayer.bounding_box`, calculado on-demand sin cache, sin soporte de "bounds incluyendo filtros" ni "bounds en un frame especifico distinto del actual"). Para Etapa 1 (stage matrix general) alcanza con lo que ya hay. Para reproducir `frameWidth`/`frameHeight`/`width`/`height` de `AnimateSymbol` igual que `FlxSprite` (que characters/holyquintet podrian estar leyendo) hace falta la version completa con cache por frame. Verificar primero si algun consumidor real lee esos valores antes de invertir en esto. |

## Que leer antes de la Etapa 1 (adicional a lo ya citado)

- `FlxAnimate.hx` completo (536 lineas, ya leido para este pase) - especialmente
  `prepareDrawMatrix` (:304-365) para la Etapa 1 de stage matrix general, y
  `getScreenBounds` (:478-506) que muestra como `renderStage` interactua con los bounds
  cuando esta activo.
- `internal/Layer.hx` (`_loadJson`, :134-218) para clipping exacto: la busqueda de la
  capa `CLIPPER` correspondiente escanea HACIA ARRIBA desde la capa clipeada
  (`layerIndex - 1` decreciente) buscando el primer nombre que matchee Y sea tipo
  `CLIPPER` - si no lo encuentra, la capa clipeada queda `visible=false` directamente
  (`Layer.hx:158-163`). El port no tiene ese fallback (si `clipped_by` no matchea ningun
  RID conocido, cae a `parent` silenciosamente en vez de ocultarse) - gap chico anotado
  para la Etapa 1.
