# Pinta freeplay con el craneo de jefe FORZADO a la vista.
#
# En el mod el craneo nace con alfa 0 (buildBg linea 1352) y quien lo sube es
# updateDataStuff cuando la cancion tiene `isBoss`. Ninguna de las cuatro del puerto lo
# tiene, asi que sin esto el craneo no se ve nunca y su arte se enviaria sin haberla
# mirado, que es como se cuelan los sprites mal colocados.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/boss_shot.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5

var _frames: int = 0
var _t: float = 0.0
var _screen: Node = null


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	_frames += 1
	_t += delta
	var skull := _screen.get_node_or_null("BossfightSkull") as AnimatedSprite2D
	if skull != null:
		skull.modulate.a = 1.0
		if not skull.is_playing():
			skull.play()
	if _frames < 6 or _t < SETTLE:
		return
	get_viewport().get_texture().get_image().save_png("user://boss.png")
	print("OUT %s" % ProjectSettings.globalize_path("user://boss.png"))
	get_tree().quit()
