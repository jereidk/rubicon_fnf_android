extends Control
## HQ Pause (Meguca) — the meguca song's special pause screen.
## Ports the mod's HQPauseMeguca: left window menu with Resume/Restart/
## Settings/Quit over the meguca gradient + banner art. The pause video and
## seek bar are not present in the port (no hxvlc videos), so those are omitted.

const OPTIONS: Array[String] = ["Resume", "Restart", "Settings", "Quit"]
const FREEPLAY := "res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn"
const MAIN_MENU := "res://holyquintet_mod/menus/main/main_menu.tscn"

var cur_sel: int = 0
var open_: bool = false
var _leaving: bool = false

@onready var bg: ColorRect = $BG
@onready var gradient: TextureRect = $Gradient
@onready var left_window: TextureRect = $LeftWindow
@onready var menu_label: Label = $LeftWindow/MenuLabel
@onready var credits_title: TextureRect = $CreditsTitle
@onready var banner: TextureRect = $Banner

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_refresh()

func _process(_delta: float) -> void:
	if not open_:
		if Input.is_action_just_pressed("ui_cancel"):
			_open()
		return
	if _leaving:
		return
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = (cur_sel - 1 + OPTIONS.size()) % OPTIONS.size()
		_refresh()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % OPTIONS.size()
		_refresh()
	elif Input.is_action_just_pressed("ui_accept"):
		_confirm()
	elif Input.is_action_just_pressed("ui_cancel"):
		_resume()

func _refresh() -> void:
	var lines := PackedStringArray()
	for i in OPTIONS.size():
		lines.append((">  " if i == cur_sel else "   ") + OPTIONS[i])
	menu_label.text = "\n".join(lines)

func _open() -> void:
	if open_ or _leaving:
		return
	open_ = true
	cur_sel = 0
	visible = true
	get_tree().paused = true
	bg.modulate.a = 0.5
	_refresh()

func _confirm() -> void:
	_leaving = true
	match cur_sel:
		0:
			_resume()
		1:
			HQSaves.death_counter += 1
			get_tree().paused = false
			get_tree().reload_current_scene()
		2:
			get_tree().paused = false
			HQSaves.settings_return_scene = get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
			get_tree().change_scene_to_file("res://holyquintet_mod/menus/settings/settings_screen.tscn")
		3:
			get_tree().paused = false
			HQSaves.goduka_enabled = false
			HQSaves.goduka_cooldown = -1
			get_tree().change_scene_to_file(FREEPLAY)

func _resume() -> void:
	open_ = false
	_leaving = false
	visible = false
	get_tree().paused = false
