extends Node
# Debugs why EditorPicker's black backdrop doesn't visually darken the menu
# behind it.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/editor_picker_bg_debug.tscn

func _ready() -> void:
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Control = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout
	print("screen.size=", screen.size, " screen.position=", screen.position, " screen.anchor=", screen.anchor_right, screen.anchor_bottom, " viewport_size=", get_viewport().get_visible_rect().size)

	var plain := Control.new()
	plain.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(plain)
	await get_tree().create_timer(0.1).timeout
	print("plain(Control-only).size=", plain.size)

	var EditorPickerScript = load("res://holyquintet_mod/menus/editors/editor_picker.gd")
	var picker = EditorPickerScript.new()
	screen.add_child(picker)
	await get_tree().create_timer(0.3).timeout

	print("picker.size=", picker.size, " picker.position=", picker.position, " picker.anchor=", picker.anchor_right, picker.anchor_bottom)
	var bg = picker.get_child(0)
	print("bg=", bg, " bg.size=", bg.size, " bg.position=", bg.position, " bg.color=", bg.color, " bg.visible=", bg.visible, " bg.z_index=", bg.z_index)
	print("picker.get_index()=", picker.get_index(), " parent child count=", screen.get_child_count())
	print("picker modulate=", picker.modulate, " self_modulate=", picker.self_modulate)

	get_tree().quit()
