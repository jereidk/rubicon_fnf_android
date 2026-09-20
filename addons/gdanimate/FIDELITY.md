# gdanimate vs FlxAnimate — auditoria de fidelidad

Este documento es el resultado del primer pase de auditoria de `addons/gdanimate/adobe/`
(el parser Adobe Animate activo) contra el engine Haxe real que usa el mod `holyquintet`.
Es la referencia obligatoria antes de tocar cualquier archivo de `adobe/`: dice que esta
verificado, que esta roto, y que esta documentado como "no aplica" con su razon.

**No se toco** `addons/gdanimate/sparrow/` (otro formato, para ButtonUI) ni
`addons/gdanimate/parser/` (ver seccion "parser/ es codigo muerto" abajo).

## Fuente de verdad: CORRECCION IMPORTANTE

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
como source-of-truth del haxelib, es el fork de Codename el que se compila).
un fork/reescritura casi completa de FlxAnimate que Codename Engine mantiene por su
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
| Boton (`ST == "B"`/`"button"`) | ❌ | `ButtonInstance.hx` | No implementado (cae por el `else` de `load_frame` y se interpreta como `ATLAS_SPRITE_instance`, produce sprite vacio) | Degrada con gracia (invisible), no crashea. No se usa en el mod HQ (verificado: sus Animation.json no traen `"ST":"B"`). |
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
