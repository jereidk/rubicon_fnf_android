extends Control
## HQ Pause — resume, restart, quit with character portrait

var options: Array[String] = ["Resume", "Restart", "Quit"]
var cur_sel: int = 0
var can_control: bool = true

@onready var menu_label: Label = $MenuLabel
@onready var fade_rect: ColorRect = $FadeRect

func _ready() -> void:
	get_tree().paused = true
	fade_rect.modulate.a = 0.8
	_update_selection()

func _process(_delta: float) -> void:
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = (cur_sel - 1 + options.size()) % options.size()
		_update_selection()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % options.size()
		_update_selection()
	elif Input.is_action_just_pressed("ui_accept"):
		_select()
	elif Input.is_action_just_pressed("ui_cancel"):
		_resume()

func _update_selection() -> void:
	var lines: PackedStringArray = []
	for i in options.size():
		lines.append(("► " if i == cur_sel else "   ") + options[i])
	menu_label.text = "\n".join(lines)

func _select() -> void:
	can_control = false
	match cur_sel:
		0: _resume()
		1: _restart()
		2: _quit()

func _resume() -> void:
	get_tree().paused = false
	queue_free()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn")
