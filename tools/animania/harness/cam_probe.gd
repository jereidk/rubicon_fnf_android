# Imprime la geometria de tres piezas del freeplay sin dibujar nada.
#
# Existe porque una superposicion dice QUE algo esta desplazado pero no si el desplazado es
# el nodo o el render. Con esto se lee la posicion del nodo, la de la camara y el tamano de
# la textura del fotograma actual, que es lo que se compara contra el binario.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/cam_probe.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5

var _t: float = 0.0
var _screen: Node = null


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	_t += delta
	if _t < SETTLE:
		return
	var cam := _screen.get_node_or_null("Camera2D") as Camera2D
	print("OUT camara=%s  raton=%s" % [str(cam.position) if cam != null else "-",
		str(get_viewport().get_mouse_position())])
	for name: String in ["Tv", "Bed", "Backwall"]:
		var node := _screen.get_node_or_null(name)
		if node == null:
			continue
		var size := "-"
		if node is AnimatedSprite2D:
			var s := node as AnimatedSprite2D
			size = "%s frame=%d" % [
				str(s.sprite_frames.get_frame_texture(s.animation, s.frame).get_size()),
				s.frame]
		elif node is Sprite2D:
			size = str((node as Sprite2D).texture.get_size())
		print("OUT %-9s pos=%s  funkin=%s  %s" % [name, str(node.position),
			str(node.position / 1.5), size])
	get_tree().quit()
