# Renders a character scene beside the stage it stands on, so a new one can be looked at.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/chars_shot.tscn
extends Node2D

const STAGE := "res://animania_mod/stages/stg_main_stage.tscn"
const CHARS := {"bf": "res://animania_mod/characters/chr_bf.tscn",
	"gf": "res://animania_mod/characters/chr_gf.tscn"}

var _frames: int = 0
var _pending: bool = false


func _ready() -> void:
	var stage: Node2D = load(STAGE).instantiate()
	add_child(stage)
	# The stage's own character block says where each one stands, in Funkin's space.
	var where: Dictionary = stage.get_meta(&"characters", {})
	for name: String in CHARS:
		var character: Node2D = load(CHARS[name]).instantiate()
		var slot: String = "bf" if name == "bf" else "gf"
		var at: Array = (where.get(slot, {}) as Dictionary).get("position", [640, 500])
		character.position = Vector2(float(at[0]), float(at[1]))
		add_child(character)
	# The 1.5x lives on the camera, and mainStage asks for 1.1 on top.
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 500.0)
	camera.zoom = Vector2.ONE * (1920.0 / 1280.0) / 1.6
	add_child(camera)
	camera.make_current()


func _process(_delta: float) -> void:
	if _pending:
		get_viewport().get_texture().get_image().save_png("user://chars.png")
		print("OUT %s" % ProjectSettings.globalize_path("user://chars.png"))
		get_tree().quit()
		return
	_frames += 1
	if _frames >= 10:
		_pending = true
