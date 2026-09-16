# Pendientes conocidos (fuera del Main Menu)

Cosas reportadas/encontradas durante el port del Main Menu que quedaron
sin resolver, anotadas acá para no perderlas. Ninguna bloquea al Main
Menu en sí — son de otras pantallas.

## 0. Botón/gesto atrás de Android — falta en TODAS las demás pantallas

Al auditar el soporte mobile del main menu se encontró que
`application/config/quit_on_go_back` (true por defecto en Godot) hacía
que presionar atrás cerrara la app entera en vez de navegar hacia
atrás, porque nada interceptaba `NOTIFICATION_WM_GO_BACK_REQUEST`. Ya
arreglado en `main_menu.gd` (sintetiza un press de "ui_cancel" real,
así reusa la misma lógica de back que ya existe por teclado en cada
pantalla/overlay).

**El mismo hueco existe en TODAS las demás pantallas de
`holyquintet_mod`** (title, freeplay, gauntlet, achievements, gallery,
credits, settings, pause, gameover, results, editors, etc. — se
revisó con `grep -rL "GO_BACK_REQUEST" holyquintet_mod/menus/*/*.gd` y
solo `main_menu.gd` lo maneja). `animania_mod` (el otro mod de este
proyecto) sí lo hace en varias de sus pantallas — es el patrón a
copiar: un `_notification(what)` chico por pantalla que, en
`NOTIFICATION_WM_GO_BACK_REQUEST`, dispara la misma acción que ya usa
esa pantalla para "volver" por teclado/Escape (en la mayoría de los
casos de holyquintet_mod alcanza con sintetizar un press de
"ui_cancel", como se hizo en main_menu.gd, ya que casi todas manejan
esa acción). Falta replicarlo en cada pantalla — no se tocó nada fuera
de main_menu.gd todavía.

## 1. Achievements (`holyquintet_mod/menus/achievements/`)

Comparado contra el `create()` real de `HQAchievements.hx`. Encontrado
recién al escribir este pendiente (más grande de lo que se había
anotado antes como "mismatch de z-order"):

- **Falta la grilla de 19 logros.** El real dibuja las 19 achievements
  como íconos chicos en una grilla de 6 columnas (`achievements[]`,
  `xPos`/`yPos` en `create()`, escala 0.75), cada uno con su propio
  marco/estado de desbloqueo, y el `selector` se mueve SOBRE esa
  grilla resaltando el actual. Este port (`achievements_screen.gd`)
  solo tiene un panel de preview (`PreviewFrame`/`PreviewIcon`) que
  cambia al mover la selección — no existen los 19 íconos de la
  grilla como nodos. El `Selector` ($Selector) ya se mueve a las
  posiciones correctas de grilla (`_update_selection()` calcula
  `GRID_X + col*COL_W`, etc.) pero se mueve sobre una zona vacía.
- **Falta el botón "Sync to Game Jolt"** (`button_syncToGJ` en el
  real) — ni siquiera existe como stub acá, a diferencia del Main
  Menu donde el botón de GameJolt sí está presente (solo que no
  hace nada real).
- `bg_Spr` real es un `FlxBackdrop` que hace scroll (`velocity.set(15,
  15)`); acá (`$BG`) es un `TextureRect` estático, sin scroll.
- Orden real completo (todo `add()`, sin `insert()`): bg_Spr, bg_Back,
  button_syncToGJ, selectedAchievement (preview), achievementName,
  achievementDescription, achievements[] (grilla), selector,
  bg_TopBanner, bg_BtmBanner, tracker_BG, tracker_Bar, tracker_text.
  Once la grilla exista, revisar que el resto del orden siga
  coincidiendo (los banners van DESPUÉS de la grilla y selector, o
  sea que la tapan un poco arriba/abajo, igual que en el main menu).

## 2. Pause (`holyquintet_mod/menus/pause/`)

Comparado parcialmente contra `HQPause.hx`. Este port ya tiene bastante
construido (BG, spots, back, 4 botones, personaje, paneles de
créditos) — no es un cascarón vacío. Todavía sin auditar a fondo
porque, al no existir ningún `PlayState`/gameplay real en este port
todavía, esta pantalla es inalcanzable en el juego (nada la abre).
Prioridad baja hasta que exista gameplay real.

Lo que sí se notó de pasada, a confirmar cuando se retome:

- Orden real: bg, spots, back, menu_Buttons (4), pauseChar (el
  personaje que "bopea"), luego los paneles de créditos. En este
  port, `$Char` (el personaje) está ANTES de `$Buttons` en el árbol
  — o sea que en este port los botones dibujan ENCIMA del personaje,
  al revés que en el real (ahí el personaje va encima de los
  botones). Falta corregir el orden de nodos si se confirma que
  importa visualmente (el personaje real ocupa buena parte del
  centro/derecha, podría tapar el texto de algún botón).
- El real usa `blend = BlendMode.ADD` en `bg` y `spots`, y
  `BlendMode.MULTIPLY` en `back`. `MULTIPLY` ya se confirmó roto en
  este renderer (GL Compatibility) para el Main Menu — mismo caso
  acá, probablemente. `ADD` no se probó todavía en un `TextureRect`/
  `ColorRect` plano (es distinto del ADD que sí funciona dentro del
  sistema de `AdobeAtlas` del Main Menu) — falta confirmar si
  `CanvasItemMaterial.BLEND_MODE_ADD` funciona acá o hace falta el
  mismo tipo de workaround.
- Personaje real: `FunkinSprite` con animación `bop` (24fps, loop),
  posición/escala dependen de qué personaje sea el "dad" actual —
  acá es un `AnimatedSprite2D` estático en una posición fija; falta
  confirmar si ya tiene la animación bop conectada o es solo un
  placeholder.
