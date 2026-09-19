extends Control
## Boton individual de la ModBubble. Dibuja un circulo con borde + un
## icono geometrico segun los metadatos que le pone mod_bubble.gd:
##   - icon_kind: IconKind (int) — que forma dibujar
##   - icon_color: Color — color del icono
##   - label: String — texto (opcional, para tooltips futuros)
##   - size_px: float — diametro del circulo
##
## Este script existe separado porque GDScript no permite crear clases
## inline en runtime: mod_bubble.gd instancia Control y le asigna ESTE
## script via set_script().

const FONT_PATH := "res://resources/fonts/fnt_vcr.ttf"

enum IconKind { EXIT, CONSOLE, DEBUG, CUSTOM, FAB_CLOSED, FAB_OPEN }

# Estilo: fondo negro translucido + borde blanco suave.
const BG_COLOR := Color(0, 0, 0, 0.6)
const BG_HOVER := Color(0, 0, 0, 0.75)
const BG_PRESSED := Color(0.2, 0.2, 0.2, 0.9)
const BORDER_COLOR := Color(1, 1, 1, 0.4)
const BORDER_HOVER := Color(1, 1, 1, 0.7)

var _hover: bool = false
var _pressed: bool = false


func _ready() -> void:
	mouse_entered.connect(func():
		_hover = true
		queue_redraw()
	)
	mouse_exited.connect(func():
		_hover = false
		_pressed = false
		queue_redraw()
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		queue_redraw()
	elif event is InputEventScreenTouch:
		_pressed = event.pressed
		queue_redraw()


func _draw() -> void:
	var size_px: float = float(get_meta("size_px", 60.0))
	var radius := size_px / 2.0 - 2.0
	var center := Vector2(size_px, size_px) / 2.0

	# Circulo de fondo.
	var bg := BG_PRESSED if _pressed else (BG_HOVER if _hover else BG_COLOR)
	draw_circle(center, radius, bg)
	# Borde.
	var border := BORDER_HOVER if _hover else BORDER_COLOR
	draw_arc(center, radius, 0.0, TAU, 32, border, 2.0)

	# Icono.
	var kind: int = int(get_meta("icon_kind", IconKind.CUSTOM))
	var color: Color = get_meta("icon_color", Color.WHITE)
	var s := size_px
	match kind:
		IconKind.FAB_CLOSED:
			# Tres puntos horizontales: el "⋯" universal de "más opciones".
			var dot_r := maxf(2.5, s * 0.045)
			var spacing := s * 0.16
			draw_circle(center + Vector2(-spacing, 0.0), dot_r, color)
			draw_circle(center, dot_r, color)
			draw_circle(center + Vector2(spacing, 0.0), dot_r, color)

		IconKind.FAB_OPEN:
			# X cerrada: dos lineas cruzadas.
			var arm := s * 0.18
			var w := maxf(3.0, s * 0.05)
			draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), color, w)
			draw_line(center + Vector2(arm, -arm), center + Vector2(-arm, arm), color, w)

		IconKind.EXIT:
			# "Salir": cuadrado abierto + flecha apuntando a la derecha.
			var box_s := s * 0.30
			var box_c := center + Vector2(-s * 0.05, 0.0)
			# Marco del cuadrado (3 lados: izq, arriba, abajo).
			var w := maxf(2.5, s * 0.04)
			draw_line(box_c + Vector2(-box_s / 2.0, -box_s / 2.0),
					  box_c + Vector2(box_s / 2.0, -box_s / 2.0), color, w)
			draw_line(box_c + Vector2(box_s / 2.0, -box_s / 2.0),
					  box_c + Vector2(box_s / 2.0, box_s / 2.0), color, w)
			draw_line(box_c + Vector2(-box_s / 2.0, box_s / 2.0),
					  box_c + Vector2(box_s / 2.0, box_s / 2.0), color, w)
			draw_line(box_c + Vector2(-box_s / 2.0, -box_s / 2.0),
					  box_c + Vector2(-box_s / 2.0, box_s / 2.0), color, w)
			# Flecha de salida (apunta afuera).
			var ax0 := box_c + Vector2(box_s / 2.0 - 2.0, 0.0)
			var ax1 := ax0 + Vector2(s * 0.22, 0.0)
			draw_line(ax0, ax1, color, w)
			draw_line(ax1, ax1 + Vector2(-s * 0.07, -s * 0.07), color, w)
			draw_line(ax1, ax1 + Vector2(-s * 0.07, s * 0.07), color, w)

		IconKind.CONSOLE:
			# ">_" prompt.
			var w := maxf(2.5, s * 0.05)
			var p0 := center + Vector2(-s * 0.16, -s * 0.12)
			var p1 := center + Vector2(-s * 0.04, 0.0)
			var p2 := center + Vector2(-s * 0.16, s * 0.12)
			draw_line(p0, p1, color, w)
			draw_line(p1, p2, color, w)
			# Guion bajo al lado.
			draw_line(center + Vector2(0.0, s * 0.12),
					  center + Vector2(s * 0.18, s * 0.12), color, w)

		IconKind.DEBUG:
			# Circulo con "i" (info).
			var w := maxf(2.5, s * 0.05)
			var i_top := center + Vector2(0.0, -s * 0.12)
			var i_bot := center + Vector2(0.0, s * 0.10)
			draw_line(i_top, i_bot, color, w)
			draw_circle(center + Vector2(0.0, -s * 0.20), maxf(2.0, s * 0.03), color)

		IconKind.CUSTOM:
			# Punto grande centrado.
			draw_circle(center, s * 0.10, color)
