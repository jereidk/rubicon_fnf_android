# Rubicon Mobile Controls

Controles táctiles estilo **hitbox** para jugar Rubicon FNF en Android: en vez de botones circulares pequeños, la pantalla se divide en zonas verticales grandes (una por lane) — tocar en cualquier punto de una zona presiona ese lane, como un controlador hitbox físico.

## Cómo funciona

- `rubicon_mobile_controls.gd` (`RubiconMobileControls`): el `Control` que dibuja y detecta las zonas táctiles. Soporta multitouch real (varios dedos en distintos lanes a la vez, con conteo por lane para que soltar un dedo no libere los demás lanes) y arrastrar el dedo entre zonas sin soltar.
- `touch_input_handler.gd` (`RubiconTouchInputHandler`): traduce `lane_pressed`/`lane_released` a un `InputEventKey` sintético (D/F/J/K) inyectado con `Input.parse_input_event`. Esto es necesario porque `RubiconLevelNoteController` matchea eventos de teclado crudos contra un `RubiconLevelNoteInputMap`, no usa el `InputMap` de acciones de Godot.
- Está registrado como autoload (`RubiconTouchInput`, ver `project.godot`), así que cualquier instancia de `mobile_controls.tscn` se conecta sola a él en `_ready()` — no hace falta cablear señales a mano por escena.

## Uso

1. El plugin ya está habilitado en `project.godot`. Los ajustes viven en `Project Settings > Rubicon Mobile Controls` (`rubicon_mobile_controls/enabled`, `lane_count`).
2. Instancia `res://addons/rubicon_mobile_controls/mobile_controls.tscn` como hijo de la capa de UI de tu canción (ver `songs/test/test.tscn`, nodo `UILayer/MobileControls`).
3. El control se auto-oculta y desactiva si `DisplayServer.is_touchscreen_available()` es falso y la build no reporta el feature `mobile` (para no molestar en desktop), o si `rubicon_mobile_controls/enabled` está en `false`.

## Configuración (exports en `RubiconMobileControls`)

- `lane_count`: número de zonas/lanes (4 por defecto).
- `hitbox_top_percent`: fracción superior de la pantalla que queda libre de zonas táctiles (para no tapar HUD como el botón de pausa).
- `show_outlines` / `outline_color` / `outline_width`: borde visible de cada zona.
- `fill_color` / `pressed_fill_color`: color de relleno en reposo y mientras se mantiene presionada.
- `haptic_feedback` / `haptic_duration_ms`: vibración al presionar (usa `Input.vibrate_handheld`, no-op fuera de Android/iOS).

## Próximos pasos

- Botón de pausa dentro de la franja libre (`hitbox_top_percent`).
- Ajuste de layout específico por resolución/aspect ratio si hace falta más que el anclaje full-rect actual.
