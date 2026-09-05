extends Control
## HQ Main Menu — Story, Freeplay, Settings, Credits

var options: Array[String] = ["Story", "Freeplay", "Settings", "Credits"]
var destinations: Dictionary = {
	"Story": "res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn",
	"Freeplay": "res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn",
	"Settings": "res://holyquintet_mod/menus/settings/settings_screen.tscn",
	"Credits": "res://holyquintet_mod/menus/credits/credits_screen.tscn",
}
var cur_sel: int = 0
var can_control: bool = true

@onready var buttons: VBoxContainer = $Buttons
@onready var fade_rect: ColorRect = $FadeRect
@onready var spots: TextureRect = $Spots

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
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

func _update_selection() -> void:
	for i in buttons.get_child_count():
		var btn = buttons.get_child(i)
		if btn is Label:
			btn.text = ("► " if i == cur_sel else "   ") + options[i]

func _select() -> void:
	can_control = false
	var dest = destinations.get(options[cur_sel], "")
	if dest.is_empty():
		can_control = true
		return
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file(dest))

func _on_back() -> void:
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/title/title_screen.tscn")
