# Tira de fotogramas del encendido del freeplay, para poder MIRAR la animacion del intro
# en vez de suponer que corre.
#
# El intro son tres momentos encadenados y ninguno se ve en una toma unica: a 0.5 s el
# televisor y el reproductor empiezan su animacion, a ~0.75 s el tubo termina y dispara
# introDone, y a 1 s entra el resto del diorama. Con una sola captura a 2.5 s todo eso ya
# paso y una animacion que no corre se ve igual que una que si.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/intro_strip.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SHOTS: Array[float] = [0.45, 0.56, 0.62, 0.68, 0.80, 1.10, 2.50]
const OUT := "user://intro_%d.png"

var _t: float = 0.0
var _next: int = 0
var _screen: Node = null


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	_t += delta
	if _next >= SHOTS.size():
		return
	if _t < SHOTS[_next]:
		return
	var tv := _screen.get_node_or_null("Tv") as AnimatedSprite2D
	var vcr := _screen.get_node_or_null("Player") as AnimatedSprite2D
	var back := _screen.get_node_or_null("TvBackBG") as CanvasItem
	var mask := _screen.get_node_or_null("PlayerLayer") as CanvasItem
	print("OUT t=%.2f  tv(vis=%s frame=%d playing=%s)  vcr(vis=%s frame=%d playing=%s)  %s"
		% [_t,
		tv != null and tv.visible, tv.frame if tv != null else -1,
		tv != null and tv.is_playing(),
		vcr != null and vcr.visible, vcr.frame if vcr != null else -1,
		vcr != null and vcr.is_playing(),
		"back=%s mask=%s allow=%s" % [back != null and back.visible,
			mask != null and mask.visible, _screen.get("allow_input")]])
	var path: String = OUT % _next
	get_viewport().get_texture().get_image().save_png(path)
	_next += 1
	if _next >= SHOTS.size():
		print("OUT dir %s" % ProjectSettings.globalize_path("user://"))
		get_tree().quit()
