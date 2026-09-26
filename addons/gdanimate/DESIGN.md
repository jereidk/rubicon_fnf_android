# Diseño: port completo de `flixel-animate` a `addons/gdanimate/`

Etapa 0 de la tarea "port completo y fiel". Este documento es el plan; `FIDELITY.md` es
el estado. Léanse juntos - cada fila de la tabla nueva en `FIDELITY.md` tiene su entrada
acá con la clase/archivo propuesto.

**Este documento es un checkpoint. No se escribió código de producción para ninguna de
las etapas 1-5 todavía** (fuera de lo ya commiteado del pase anterior, que era el primer
audit). Necesito aprobación explícita antes de arrancar la Etapa 1.

## 0. Resumen ejecutivo para decidir rápido

Si solo vas a leer una sección, que sea esta:

1. **El oráculo Haxe real (correr `flixel-animate` de verdad y comparar pixel a pixel)
   está bloqueado.** `cne-flixel-animate` depende de forks propios de CodenameCrew
   (`cne-flixel`, `cne-openfl`, `cne-lime`, y en último término `cne-hxcpp` para
   compilar nativo) que no tipan con las versiones vanilla de haxelib.org, y las ramas
   `cne` que clonaron tampoco tipan entre sí (parecen no estar en un commit compatible
   conjunto). Ver `FIDELITY.md` sección "Toolchain de verificación" para el detalle con
   evidencia de compilador.
2. **Propongo seguir sin ese oráculo**, con dos redes de seguridad en su lugar:
   - Un oráculo de **lógica pura**: copio literal (no reescribo) las funciones Haxe que
     no dependen de FlxG/render (parseo de matrices, cálculo de frame index, bounds) a
     un programa Haxe standalone sin flixel/openfl, que sí corre en segundos con
     `haxe --interp`. Esto da certeza matemática exacta en la parte que más bugs de
     posición/tiempo genera.
   - **Golden-image tests del lado Godot SÍ son viables** (confirmado:
     `xvfb-run` + Godot 4.7.1 + Mesa software renderiza y captura PNG sin problema). No
     tengo con qué compararlos automáticamente contra el engine real, pero sirven para
     dos cosas: (a) tests de regresión dentro del port mismo (¿esta feature sigue
     dibujando lo mismo que antes de tocar código no relacionado?), y (b) el usuario
     puede comparar esos PNG contra sus screenshots del original a mano, más rápido que
     esperar un build de Android completo.
3. ~~Opción A (perseguir el toolchain completo de CNE)~~ - **descartada, decisión del
   usuario 2026-09-20.** Chequeo final antes de cerrarla: `building/libs.xml.sum` no
   existe en `CodenameCrew/CodenameEngine` (`git show origin/main:building/libs.xml.sum`
   → `fatal: path does not exist`), y no hay ningún otro lockfile en `building/` ni en
   el resto del repo (`git ls-tree -r --name-only origin/main | grep -iE
   "\.sum$|lock"` no encuentra nada relevante). `libs.xml` usa `ref="cne"` sin SHA
   pineado - el build real de Codename siempre resuelve al HEAD de la rama al momento de
   compilar, no hay un commit "correcto" fijo para clonar. Aunque lo hubiera, el pipeline
   de filtros necesita `hxcpp` nativo, que no es viable headless en este sandbox. Opción
   A queda cerrada, no se retoma salvo que aparezca una razón nueva y concreta.

**Decisión: B+C.** Todo lo que sigue en este documento y en el trabajo de Etapa 1 en
adelante asume B+C.

## 1. Principios que gobiernan cada decisión de diseño abajo

- **API pública intacta.** Ninguna clase/método/`@export` listado en la tarea original
  cambia de firma. Toda esta sección es sobre qué agregar, no qué romper.
- **Cambios mínimos por commit.** Cada feature de la tabla de `FIDELITY.md` es (en
  principio) un commit, con su test.
- **Preferir composición sobre herencia cuando el original usa herencia por
  conveniencia de Haxe** (ej. `ButtonInstance extends SymbolInstance`) pero el port ya
  tiene una jerarquía de clases (`AdobeDrawable` → `AdobeSymbolInstance`) que puede
  seguir el mismo patrón sin fricción - en ese caso SÍ calco la herencia.
- **Nada de infra nueva sin necesidad concreta.** No creo `AdobeAnimationController` si
  nadie va a usarlo esta etapa; lo dejo para la Etapa 4 como pide el plan.

## 2. Arquitectura propuesta por etapa

### Etapa 1 — Fidelidad de lo existente (sin clases nuevas)

Todo esto es editar archivos que ya existen. Ningún archivo nuevo.

| Cambio | Archivo(s) | Por qué |
|---|---|---|
| Stage matrix general (rotación/escala, no solo traslación pura) | `adobe_atlas.gd` (`draw_on`), posiblemente `animate_symbol.gd` | Hoy la aproximación asume `a=d=1,b=c=0` en el M3D del stage. Portar la fórmula completa de `prepareDrawMatrix` (`FlxAnimate.hx:304-365`) necesita el concepto de `bounds` del symbol raíz - ya existe (`AdobeSymbol.bounding_box`), solo hay que enchufarlo en el orden correcto. |
| `postStageMatrixApply` | `adobe_atlas.gd`, `animate_symbol.gd` (nuevo `@export var post_stage_matrix_apply: bool = false`) | Trivial una vez que el punto anterior está resuelto - es literalmente mover una línea de "antes" a "después" en el pipeline, como en `FlxAnimate.hx:310-319` vs `:353-356`. |
| Blend alpha compositing (`mix(a, result, b.a)` final) | `atlas_shader.gdshader` | Ya diagnosticado en el pase anterior. Requiere pensar cómo Godot recompone `COLOR.a` después del shader para no duplicar el efecto - el fix real puede necesitar mover el punto donde se aplica `COLOR.a` o usar `render_mode blend_premul_alpha` en vez de blend automático. Este es el único ítem de Etapa 1 que puede necesitar iteración visual (no solo lectura de source), así que lo marco de mayor riesgo. |
| Clipping: capa clipper debe existir y ser tipo `Clp` | `adobe_layer.gd`, `adobe_atlas.gd` (`load_layers`/`draw_symbol`) | Hoy si `clipped_by` no matchea un RID conocido cae a `parent` silenciosamente. El original oculta la capa (`visible=false`) si no encuentra un clipper válido (`Layer.hx:158-163`). Fix: en `load_layers`, si una capa tiene `Clipped_by` pero ninguna capa ANTERIOR con ese nombre es tipo clipper, marcarla oculta (nuevo campo `AdobeLayer.hidden_no_clipper: bool` o reutilizar algo existente). |
| `MovieClipInstance.swfMode` respeta loop mode/first/lastFrame | `adobe_atlas.gd` (`draw_symbol`, rama `movie_clips_play`) | Cambiar el `wrapi(...)` manual por una llamada a `symbol_instance_frame()`, la misma función que ya usan los Graphics. Chico, con test directo (mismo test que loop modes, con `type=MOVIE_CLIP` y `movie_clips_play=true`). |
| Frame labels | `adobe_layer_frame.gd` (nuevo `@export_storage var name: String = ""`), `adobe_atlas.gd` (`load_frame`) | Prerequisito de la Etapa 4, pero es una línea de parseo (`get_pair(optimized, frame, "name", "N")`) así que lo hago en Etapa 1 para no bloquear después. |
| Sparrow: `flipX`/`flipY` | `sparrow_frame.gd` (nuevos campos), `sparrow_atlas.gd` (`parse`), `animate_symbol.gd` o `sparrow_atlas.gd` (`draw_on`) | Chico, mismo patrón que `rotated` ya existente. |

### Etapa 2 — Elementos faltantes

| Clase nueva | Extiende | Por qué no reusar algo existente |
|---|---|---|
| `AdobeButtonInstance` (`adobe/adobe_button_instance.gd`) | `AdobeSymbolInstance` | Necesita estado propio (`UP`/`OVER`/`DOWN`/`HIT`) y lógica de hit-test que no aplica a un `SymbolInstance` normal. Calco la herencia del original (`ButtonInstance extends SymbolInstance`) porque el port ya tiene esa misma jerarquía. |
| — (sin clase nueva, se resuelve en el parser) | `adobe_atlas.gd` (`load_symbol_instance`, actualmente ignora `"ST":"B"`) | Detectar el tipo boton y devolver `AdobeButtonInstance` en vez de `AdobeSymbolInstance` cuando `symbolType == "B"`/`"button"`. |
| `AdobeTextFieldInstance` (`adobe/adobe_textfield_instance.gd`) | `AdobeDrawable` (no `AdobeSymbolInstance` - el original tampoco, hereda de `AtlasInstance`) | Prioridad baja (sin evidencia de uso en HQ). Diseño propuesto si se aprueba: guarda el texto/formato parseado de `TFI`, y en el primer `draw_on` (o cuando el texto cambia) renderiza a un `SubViewport` chico con un `Label`, captura a `ViewportTexture`, y de ahí en más se dibuja como un sprite más (mismo mecanismo que se necesita para filtros en Etapa 3 - **quizás convenga hacer esto DESPUÉS de la Etapa 3** para reusar la infraestructura de `AdobeRenderTexture` en vez de duplicarla). |

No creo clase para `FlxSpriteElement`: quedó en ➖ en `FIDELITY.md`, sin caso de uso real
identificado. Si aparece uno, es una etapa aparte.

### Etapa 3 — RenderTexture + Filtros

Esta es la etapa más grande y la que más depende de iteración visual (menos "leer y
portar", más "leer, portar, mirar el resultado, ajustar").

| Clase nueva | Rol | Análogo Haxe |
|---|---|---|
| `AdobeRenderTexture` (`adobe/adobe_render_texture.gd`) | Envuelve un `SubViewport` + `ViewportTexture`. API mínima: `init(size)`, `draw_to(callback)`, `render() -> Texture2D`. | `internal/RenderTexture.hx` (`init`/`drawToCamera`/`render`) |
| `AdobeFilterRenderer` (`adobe/adobe_filter_renderer.gd`, autoload-free, clase estática o `RefCounted`) | Orquesta: recibe una lista de `AdobeFilter`, un `AdobeRenderTexture` con el MovieClip ya dibujado, aplica cada filtro en orden, devuelve la textura final + el rect expandido. | `internal/FilterRenderer.hx` (`bakeFilters`/`applyFilter`/`expandFilterBounds`) |
| Shaders: `blur_filter.gdshader`, `glow_filter.gdshader` (rehecho, hornea en vez de sampling en vivo), `drop_shadow_filter.gdshader` | Los shaders reales que corren dentro de `AdobeRenderTexture` | `StackBlur.hx` (aproximado con gaussiano 2-pasadas, documentado como no pixel-idéntico), `GlowFilter`/`DropShadowFilter` de OpenFL (mismos parámetros: color, blur x/y, strength/alpha, inner, knockout, distance/angle para dropshadow) |
| `AdobeAdjustColorFilter` (función estática en `adobe_color_matrix.gd` o archivo nuevo `adobe_adjust_color_filter.gd`) | Traduce brightness/hue/contrast/saturation a un `AdobeColorMatrix` | `internal/filters/AdjustColorFilter.hx` (fórmula de 4 matrices, la copio literal - es matemática pura, no depende de render) |

Cambios en archivos existentes para esta etapa:
- `adobe_symbol_instance.gd`: conectar el parseo real de `filters` (hoy declarado, nunca
  leído) en `adobe_atlas.gd:load_symbol_instance` - leer `"F"`/`"filters"`, mapear cada
  entrada a un `AdobeFilter` tipado (blur/glow/dropshadow/adjustColor/bevel).
- `adobe_atlas.gd:draw_symbol`: cuando un elemento es `MOVIE_CLIP` y tiene `filters` no
  vacío, desviar a `AdobeFilterRenderer` en vez del camino de dibujo directo. Los
  Graphics NUNCA hornean filtros (igual que el original - `MovieClipInstance` es la
  única clase que llama a `_bakeFilters`).
- `adobe_layer_frame.gd`: el campo `glow` (hoy dead code) se elimina o se re-cablea para
  usar el nuevo modelo (filtros en la instancia). Pendiente de decisión: ¿borrar el
  campo viejo o dejarlo con un comentario `@deprecated`? Dado que nunca se llenó, no hay
  dato en vuelo que perder - me inclino a borrarlo cuando se toque este archivo, pero
  aviso antes de hacerlo (la tarea pide no borrar sin preguntar).

### Etapa 4 — Animation controller / timeline

| Clase nueva | Rol |
|---|---|
| `AdobeAnimateController` (`adobe/adobe_animate_controller.gd`, o vive dentro de `AnimateSymbol` como métodos nuevos - a decidir) | Replica `addByFrameLabel`/`addByFrameLabelIndices`/`addByTimeline`/`addByTimelineIndices`/`addBySymbol`/`addBySymbolIndices`/`findFrameLabelIndices`, señal `frame_label` (Godot `Signal` en vez de `FlxTypedSignal`). |

Decisión de diseño pendiente para este punto (la marco explícita porque no la puedo
resolver sola sin ver cómo se usaría): ¿esto vive como una clase separada que
`AnimateSymbol` instancia (`anim` property, calcando `FlxAnimate.anim`), o como métodos
directos en `AnimateSymbol`? El original lo separa porque `FlxAnimationController` es
una clase base de Flixel que `FlxAnimateController` extiende - acá no hay una jerarquía
equivalente que obligue a separarlo. Mi inclinación: métodos directos en
`AnimateSymbol` con un prefijo claro (`add_by_symbol`, etc.), más simple y consistente
con que hoy `symbol`/`frame` ya viven ahí. Lo reviso con el usuario antes de escribir
código de esta etapa (llegado el momento, no ahora).

### Etapa 5 — Test suite + doc final

Ver sección 4 de este documento.

## 3. Qué se portea "directo" vs necesita subsystem nuevo

**Directo (lógica pura, sin nueva infraestructura de render):**
- Stage matrix general, `postStageMatrixApply`, clipping fallback, `swfMode`, frame
  labels, Sparrow flip, `AdjustColorFilter` (la fórmula).

**Necesita subsystem nuevo (`SubViewport`-based rendering):**
- Todo lo de Etapa 3 (filtros reales) y `TextFieldInstance` (Etapa 2, si se aprueba).
  Comparten la misma pieza de infraestructura (`AdobeRenderTexture`), así que conviene
  hacer `TextFieldInstance` DESPUÉS de tener eso, no antes - lo marco como posible
  reordenamiento Etapa 2 ↔ Etapa 3 si el usuario está de acuerdo (el plan original las
  pone en ese orden, pero técnicamente `TextFieldInstance` es más fácil una vez que
  `AdobeRenderTexture` existe).

**Requiere decisión de producto antes que de ingeniería:**
- `FlxSpriteElement` (¿hay algún caso de uso real?).
- `AdobeAnimateController` como clase separada vs métodos en `AnimateSymbol`.
- `Timeline._bounds` completo con cache (¿algo lee `frameWidth`/`frameHeight` de
  `AnimateSymbol` hoy? si no, no hace falta la versión con cache, la que ya existe
  alcanza).

## 4. Estrategia de tests concreta

Sin GUT ni ningún framework de test instalado en el repo (confirmado, `addons/` no
tiene nada de testing). Dos capas, sin agregar dependencias:

**Capa 1 — oráculo de lógica pura (Haxe, vía `--interp`).** Un directorio
`addons/gdanimate/tests/oracle/` con:
- `oracle/hx/` — programas Haxe standalone (sin flixel/openfl) que copian literal las
  funciones puras citadas en la sección 0, y dumpean su resultado a JSON dado un input
  fijo (ej. una lista de M3D de prueba, o un `(firstFrame, lastFrame, loopMode,
  difference)` por caso). Corridos manualmente por mí durante el desarrollo (`haxe
  --interp`), el JSON de salida se commitea como fixture (`oracle/fixtures/*.json`).
- `oracle/test_matrices.gd`, `oracle/test_frame_index.gd`, etc. — comparan el output
  real de `adobe_atlas.gd`/`AdobeSymbolInstance` contra esos fixtures, corridos desde
  Godot.

**Capa 2 — regresión visual dentro de Godot.** `addons/gdanimate/tests/visual/`:
- Un script runner (`run_visual_tests.gd`, invocado con
  `xvfb-run -a Godot --headless -s res://addons/gdanimate/tests/visual/run_visual_tests.gd`
  — nota: `-s` con un script corre sin necesitar `--headless` funcional para el
  rendering server, pero para CAPTURAR pixeles reales hace falta la combinación
  `xvfb-run` + `--rendering-driver opengl3` sin `--headless`, como confirmé en el
  toolchain check) que carga cada `Animation.json` de prueba de la branch
  `holyquintet-port`, dibuja unos frames representativos, y guarda PNG en
  `tests/visual/output/`.
- Sin oráculo pixel-real para diffear automático (Opción A descartada, ver sección 0),
  así que esta capa es "no se rompió nada respecto al PNG anterior" (diff contra el PNG
  commiteado la vez anterior, con tolerancia de antialiasing) más comparación manual del
  usuario contra sus screenshots del original (Opción C) - no hay comparación automática
  contra el engine real.

**Runner único**: `addons/gdanimate/tests/run_tests.gd`, pensado para correr con
`xvfb-run -a /root/Godot_v4.7.1-stable_linux.x86_64 --path <repo> -s res://addons/gdanimate/tests/run_tests.gd`,
sale con código de proceso 0/1 según si todo pasó, para que sea fácil de invocar en
cada iteración sin mirar output a mano.

## 5. Estimación de complejidad (resumen, detalle en `FIDELITY.md`)

| Etapa | Tamaño | Riesgo de iteración visual |
|---|---|---|
| 1 | Mediano (7 fixes chicos-medianos, ~1 sesión) | Bajo, salvo blend alpha compositing (medio) |
| 2 | Mediano (Button chico-mediano, TextField grande si se aprueba) | Bajo para Button, medio-alto para TextField |
| 3 | Grande (subsystem nuevo completo) | Alto - es la etapa donde más voy a necesitar screenshots de referencia |
| 4 | Mediano | Bajo (es API, no render) |
| 5 | Mediano (trabajo de test, no de feature) | Ninguno |

## 6. Lo que necesito de vos para arrancar Etapa 1

1. **Decisión A/B+C/mezcla** de la sección 0.
2. Confirmación de que puedo arrancar Etapa 1 (los 7 fixes de la tabla), o si preferís
   que ajuste el orden/alcance de algo ahí.
3. Si tenés capturas o video del mod original ya a mano (mencionaste que sí), decime
   cómo pasármelas cuando lleguemos a Etapa 3 - ahí es donde más las voy a necesitar.

No arranco Etapa 1 hasta tener al menos el punto 1 y 2 confirmados.
