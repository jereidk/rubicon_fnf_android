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
| F4 | `ButtonInstance.hx` (153) | `adobe_button_instance.gd` | pendiente (falta input) |
| F5 | `Frame.hx` (448) | `adobe_layer_frame.gd` | pendiente |
| F6 | `Layer.hx` (262) | `adobe_layer.gd` | pendiente |
| F7 | `Timeline.hx` (476) + `SymbolItem.hx` (95) | `adobe_symbol.gd` | pendiente |
| F8 | `FlxAnimateFrames.hx` (707) | `adobe_atlas.gd` (load_*) | pendiente |
| F9 | `FlxAnimate.hx` (497) | `animate_symbol.gd` | pendiente |
| F10 | `FlxAnimateController.hx` (413) | `adobe_animate_controller.gd` | pendiente |
| F11 | `StageBG.hx` (46) + `Blend.hx` (171) | stage bg + shader | pendiente |
| F12 | `TextFieldInstance.hx` (124) + `FlxSpriteElement.hx` (206) | sin portear | pendiente |
| F13 | filtros: `RenderTexture` + `FilterRenderer` + `AdjustColorFilter` + `StackBlur` + `MaskShader` | sin portear | pendiente |

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
