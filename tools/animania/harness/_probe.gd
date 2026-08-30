extends Node2D
var _n: int = 0
var _pending: String = ""
func _ready() -> void:
	var stage: Node2D = load("res://animania_mod/stages/stg_service_enterance.tscn").instantiate()
	stage.name = "Stage"
	add_child(stage)
	for c: Node in stage.get_children():
		print("OUT %-20s %s" % [c.name, (c as Node2D).position])
	var cam := Camera2D.new()
	cam.position = Vector2(600.0, 700.0)
	cam.zoom = Vector2.ONE * 0.46 * 1.5
	add_child(cam); cam.make_current()
func _process(_d: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		if _pending.ends_with("con.png"):
			var red: Node = get_node_or_null("Stage/FgRedOverlay")
			if red != null: (red as CanvasItem).visible = false
			_pending = "user://stage_sin.png"
			return
		get_tree().quit(); return
	_n += 1
	if _n >= 8: _pending = "user://stage_con.png"
