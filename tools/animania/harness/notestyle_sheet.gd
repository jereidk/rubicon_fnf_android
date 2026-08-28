# Contact sheet of the ported note style: every lane and note animation, frame by frame.
#
# Cheaper and far more legible than hunting for one arrow in a gameplay screenshot - which
# is what the first check of this port tried, and it could not tell "the port is wrong"
# from "that lane has no note on screen right now".
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/notestyle_sheet.tscn
extends Node2D

const FRAMES := {
	"lanes": "res://animania_mod/notestyle/amtake_lanes_frames.tres",
	"notes": "res://animania_mod/notestyle/amtake_notes_frames.tres",
	"effects": "res://animania_mod/notestyle/amtake_effects_frames.tres",
}
const CELL := Vector2(128.0, 96.0)
const MARGIN := Vector2(16.0, 8.0)

var _frames: int = 0
var _pending: Array = []


func _ready() -> void:
	for sheet: String in FRAMES:
		_pending.append(sheet)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 3:
		return

	var index: int = (_frames - 3) / 3
	if index >= _pending.size():
		get_tree().quit()
		return

	var step: int = (_frames - 3) % 3
	var sheet: String = _pending[index]

	if step == 0:
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_lay_out(load(FRAMES[sheet]))
	elif step == 2:
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("user://notestyle_%s.png" % sheet)
		print("OUT %s -> %s" % [sheet,
			ProjectSettings.globalize_path("user://notestyle_%s.png" % sheet)])


func _lay_out(frames: SpriteFrames) -> void:
	var row: int = 0
	for anim: String in frames.get_animation_names():
		var label := Label.new()
		label.text = anim
		label.position = MARGIN + Vector2(0.0, row * CELL.y + 40.0)
		add_child(label)

		for i: int in frames.get_frame_count(anim):
			var sprite := Sprite2D.new()
			sprite.texture = frames.get_frame_texture(anim, i)
			sprite.centered = false
			# Every frame scaled into the same cell, so animations with different frame
			# sizes still line up and a wrong region reads as a wrong shape.
			var size: Vector2 = sprite.texture.get_size()
			var fit: float = minf(CELL.x / size.x, CELL.y / size.y)
			sprite.scale = Vector2(fit, fit)
			sprite.position = MARGIN + Vector2(230.0 + i * CELL.x, row * CELL.y)
			add_child(sprite)

		row += 1
