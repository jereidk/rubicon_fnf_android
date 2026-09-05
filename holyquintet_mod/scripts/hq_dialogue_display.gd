extends CanvasLayer
## HQ Dialogue — simplified pre-song dialogue from dialogue.json.
## Handles graphic screens (full-screen images with fade/shake) and
## normal dialogue (speaker name + text). Add as a child of a song scene
## with events_path pointing to the song's dialogue.json.
##
## Skippable with ui_accept. After all entries, emits dialogue_finished
## and the song scene starts the level.

@export var dialogue_path: String = ""
@export var song_name: String = ""

var _entries: Array = []
var _current_idx: int = 0
var _is_active: bool = false
var _can_advance: bool = false

## UI nodes (created in _ready)
var _bg: ColorRect
var _graphic: TextureRect
var _dialogue_box: TextureRect
var _speaker_label: Label
var _text_label: Label
var _skip_label: Label
var _fade_rect: ColorRect

signal dialogue_finished


func _ready() -> void:
	if dialogue_path.is_empty():
		_start_song()
		return

	var full_path = dialogue_path if dialogue_path.begins_with("res://") else "res://" + dialogue_path
	if not FileAccess.file_exists(full_path):
		push_warning("HQDialogue: not found: %s" % full_path)
		_start_song()
		return

	_load_dialogue(full_path)
	if _entries.is_empty():
		_start_song()
		return

	_build_ui()
	_is_active = true
	_current_idx = 0
	# Fade in from black
	_fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _can_advance = true)
	_show_entry(0)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_active or not _can_advance:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_advance()
	elif event is InputEventScreenTouch and event.pressed:
		_advance()


func _advance() -> void:
	_can_advance = false
	_current_idx += 1
	if _current_idx >= _entries.size():
		_end_dialogue()
		return
	_show_entry(_current_idx)
	_can_advance = true


func _show_entry(idx: int) -> void:
	var entry = _entries[idx]
	var action = entry.get("action", "")
	var params = entry.get("params", [])

	match action:
		"":
			_show_normal(entry)
		"graphic":
			_show_graphic(params)
		"fadein":
			_can_advance = false
			var delay: float = params[0] if params.size() > 0 else 1.0
			await get_tree().create_timer(delay).timeout
			_can_advance = true
			_current_idx += 1
			if _current_idx >= _entries.size():
				_end_dialogue()
				return
			_show_entry(_current_idx)
		"fadeout":
			_can_advance = false
			_fade_rect.modulate.a = 0.0
			_fade_rect.visible = true
			var tw := create_tween()
			tw.tween_property(_fade_rect, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN)
			var delay: float = params[0] if params.size() > 0 else 1.0
			await tw.finished
			await get_tree().create_timer(delay).timeout
			_fade_rect.visible = false
			_can_advance = true
			_current_idx += 1
			if _current_idx >= _entries.size():
				_end_dialogue()
				return
			_show_entry(_current_idx)
		"gotonormal", "gotonormalintro":
			_switch_to_normal(action == "gotonormalintro")
			_show_normal(entry)
		"witches", "griefseed", "magicalgirls":
			_show_graphic(params if params.size() > 0 else [action])
		_:
			_show_normal(entry)


func _show_normal(entry: Dictionary) -> void:
	# Hide graphic, show dialogue box
	_graphic.visible = false
	_graphic.modulate.a = 0.0
	_dialogue_box.visible = true
	_speaker_label.visible = true
	_text_label.visible = true
	_skip_label.visible = false

	var char_name: String = entry.get("name", "")
	# Map internal names to display names
	match char_name:
		"sayaka":
			_speaker_label.text = "Sayaka Miki"
		"mami":
			_speaker_label.text = "Mami Tomoe"
		"madoka":
			_speaker_label.text = "Madoka Kaname"
		"kyoko":
			_speaker_label.text = "Kyoko Sakura"
		"homura":
			_speaker_label.text = "Homura Akemi"
		"nagisa":
			_speaker_label.text = "Nagisa Momoe"
		"girlfriend":
			_speaker_label.text = "Girlfriend"
		"":
			_speaker_label.text = ""
		_:
			_speaker_label.text = char_name.capitalize()

	# Use the dialogue index as placeholder text
	_text_label.text = "[%s]" % entry.get("dialogue", "?")


func _show_graphic(params: Array) -> void:
	_dialogue_box.visible = false
	_speaker_label.visible = false
	_text_label.visible = false
	_skip_label.visible = true

	if params.size() == 0:
		return

	var screen_name: String = params[0]
	var trans_type: String = params[1] if params.size() > 1 else "fadein"

	var tex_path := "res://holyquintet_mod/source/images/game/dialogue/screens/%s.png" % screen_name
	if ResourceLoader.exists(tex_path):
		_graphic.texture = load(tex_path)
		_graphic.visible = true
		_graphic.set_anchors_preset(Control.PRESET_FULL_RECT)
		_graphic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	match trans_type:
		"fadein":
			_graphic.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(_graphic, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN_OUT)
		"shake":
			_graphic.modulate.a = 1.0
			# Subtle shake effect via tween
			var orig_pos := _graphic.position
			var tw := create_tween().set_loops(8)
			tw.tween_property(_graphic, "position:x", orig_pos.x + 5.0, 0.05)
			tw.tween_property(_graphic, "position:x", orig_pos.x - 5.0, 0.05)
			tw.chain().tween_property(_graphic, "position", orig_pos, 0.05)


func _switch_to_normal(instant: bool) -> void:
	_graphic.visible = false
	_graphic.modulate.a = 0.0
	_dialogue_box.visible = true
	_speaker_label.visible = true
	_text_label.visible = true
	_skip_label.visible = false


func _end_dialogue() -> void:
	_is_active = false
	# Fade out
	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _start_song())


func _start_song() -> void:
	dialogue_finished.emit()
	queue_free()


func _load_dialogue(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("HQDialogue: parse error in %s" % path)
		return
	var data = json.data
	if data is Dictionary and data.has("dialogue"):
		_entries = data["dialogue"]
	elif data is Array:
		_entries = data


func _build_ui() -> void:
	# Full-screen overlay
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color.BLACK
	add_child(_bg)

	# Graphic screen
	_graphic = TextureRect.new()
	_graphic.set_anchors_preset(Control.PRESET_FULL_RECT)
	_graphic.visible = false
	add_child(_graphic)

	# Dialogue box (dark translucent bar at bottom)
	_dialogue_box = TextureRect.new()
	_dialogue_box.position = Vector2(100, 700)
	_dialogue_box.size = Vector2(1720, 280)
	_dialogue_box.color = Color(0, 0, 0, 0.7)
	_dialogue_box.visible = false
	add_child(_dialogue_box)

	# Speaker name
	_speaker_label = Label.new()
	_speaker_label.position = Vector2(150, 670)
	_speaker_label.size = Vector2(600, 40)
	_speaker_label.add_theme_font_size_override("font_size", 42)
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_speaker_label.visible = false
	add_child(_speaker_label)

	# Dialogue text
	_text_label = Label.new()
	_text_label.position = Vector2(150, 730)
	_text_label.size = Vector2(1620, 200)
	_text_label.add_theme_font_size_override("font_size", 32)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.visible = false
	add_child(_text_label)

	# Skip hint
	_skip_label = Label.new()
	_skip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_skip_label.offset_top = -60
	_skip_label.offset_bottom = -20
	_skip_label.text = "[ Tap or Enter to continue ]"
	_skip_label.add_theme_font_size_override("font_size", 24)
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.visible = false
	add_child(_skip_label)

	# Fade overlay (for transitions)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 1.0
	add_child(_fade_rect)
