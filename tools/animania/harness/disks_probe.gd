# Dice donde cae cada disco del carrusel en pantalla, y el candado del que lo lleve.
#
# Las capturas del mod se miden en pixeles; el puerto se puede preguntar. Sin esto, cualquier
# diferencia en la fila de discos se queda en "parece mas grande".
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/disks_probe.tscn -- 1
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5
const HOLD := 3.0
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _t: float = 0.0
var _screen: Node = null
var _done: bool = false


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < SETTLE:
		return
	_done = true
	var want: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			want = arg.to_int()
	for _i: int in want:
		_screen.call("change_selection", 1, false)
	var wait: float = 0.0
	while wait < HOLD:
		await get_tree().process_frame
		wait += get_process_delta_time()
	var disks: Node = _screen.get_node("Disks")
	for child: Node in disks.get_children():
		var d := child as Sprite2D
		if d == null:
			continue
		var size: Vector2 = d.texture.get_size() * d.global_scale
		print("OUT %-11s x %6.1f..%6.1f  y %6.1f..%6.1f  escala %.3f%s" % [d.name,
			d.global_position.x / FUNKIN_TO_RUBICON,
			(d.global_position.x + size.x) / FUNKIN_TO_RUBICON,
			d.global_position.y / FUNKIN_TO_RUBICON,
			(d.global_position.y + size.y) / FUNKIN_TO_RUBICON,
			d.global_scale.x / FUNKIN_TO_RUBICON,
			_lock(d)])
	get_tree().quit()


func _lock(disk: Sprite2D) -> String:
	var lock := disk.get_node_or_null("Lock") as Sprite2D
	if lock == null:
		return ""
	var size: Vector2 = lock.texture.get_size() * lock.global_scale
	return "  candado x %.1f..%.1f  y %.1f..%.1f" % [
		lock.global_position.x / FUNKIN_TO_RUBICON,
		(lock.global_position.x + size.x) / FUNKIN_TO_RUBICON,
		lock.global_position.y / FUNKIN_TO_RUBICON,
		(lock.global_position.y + size.y) / FUNKIN_TO_RUBICON]
