extends Control
## Ports HQSettings.hx: 5 categories (Controls, Gameplay, Visuals, Language,
## Other) of SettingOptionUI rows, backed by the new HQOptions autoload
## (this port's equivalent of the real, separately-saved Options class —
## see hq_options.gd's own header for exactly which real fields are ported
## and why some default values are best-effort rather than verified).
##
## Real z-order (create(), all plain add()): bg_Spr, bg_Spots, bg_Back,
## mainOptionButtons(5), controlSettings rows(13), gameplaySettings
## rows(11), visualSettings rows(7), languageSettings rows(2),
## otherSettings rows(2), bg_TopBanner, bg_BtmBanner. All 5 categories'
## rows sit at the SAME absolute positions (580+i*35, 180+i*100) — real
## code relies on only one category's FlxSpriteGroup being .visible at a
## time (changeSelection()) rather than actually separating them on
## screen, and this port does the same (one CategoryRoot Control per
## list, all overlapping at (0,0), toggling .visible).
##
## Real per-category scrolling (update()): FlxSpriteGroup.offset lerped
## every frame toward 100/35px per row of `scrollOffset = sm_subSel - 3`
## (bounded so the list doesn't scroll past its own ends) — a continuous
## fpsLerp chase. Ported as a Tween on each CategoryRoot's own position
## instead of a per-frame lerp on a native "offset" Godot Controls don't
## have; same visual result (the list scrolls to keep the selection in a
## centered window), simpler to express as "animate to a target" than to
## re-implement frame-independent lerp smoothing by hand. Only Controls
## and Gameplay actually need it (13 and 11 rows); Visuals/Language/Other
## have ≤7, matching the real code's own scroll math applying only to
## those first two lists (visualSettings' identical lerp lines exist in
## update() but are commented out there in the real source — a real,
## deliberate cut in the mod itself, not something this port is skipping).
##
## offsettingOption (SongOffset live preview): real update() halves the
## music volume, zooms FlxG.camera by +0.03 on every Conductor.curBeat
## change, and plays a metronome tick on every Conductor.getTimeInBeats
## change, while the camera zoom itself decays back to 1 via
## `CoolUtil.fpsLerp(zoom, 1, 0.25)` every frame regardless. Ported as:
## - "camera" = this screen's own World Control (wraps every real sprite —
##   backgrounds, banners, category buttons, option rows — pivoted at
##   screen center (960,540) via pivot_offset, then scaled instead of a
##   real Camera2D; same convention as HQTitle.hx's star-zoom, see
##   title_screen.gd's own header for why scaling content around its
##   center reads identically to zooming a camera at it).
## - the beat clock: no Conductor/chart exists anywhere in this port yet,
##   so there's no real bpmChangeMap to read. Conductor.hx itself (a base
##   CodenameEngine class, not something the mod overrides, so it's not in
##   this port's own mod-source extraction) falls back to
##   `Conductor.startingBPM` = `dummyChange.bpm` = 100 whenever nothing has
##   called changeBPM() yet — true here, since this screen never loads a
##   chart. Confirmed by reading CodenameEngine's own public source
##   (funkin/backend/system/Conductor.hx) directly, not guessed.
## - fpsLerp: also a base-engine helper (CoolUtil.hx), confirmed the same
##   way: `fpsLerp(a,b,ratio) = lerp(a,b, 1-pow(1-ratio, elapsed*60))`.
## - the real code's two separate beat trackers (lastBeatOffSet for zoom,
##   lastSongBeatOffset for the metronome — technically two slightly
##   different clocks) are consolidated into one here, since without a
##   real Conductor there's only one beat clock to derive from regardless
##   (the settings music's own playback position at the 100 BPM fallback).
##
## Real DestroySaveData ends in Sys.exit() (a desktop-only hard process
## kill after wiping every save). Ported as get_tree().quit() — the
## closest a Godot Android app has to "the process ends right now",
## same intent (don't leave the just-wiped runtime state sitting in
## memory a second longer).
##
## Mobile-only addition, not in the real game: tapping an already-
## selected int/float row's left or right quarter (see
## setting_option_row.gd) steps it down/up, since there's no touch
## equivalent to holding a physical Left/Right key otherwise.

const ButtonScene := preload("res://holyquintet_mod/ui/button_ui.tscn")
const RowScript := preload("res://holyquintet_mod/ui/setting_option_row.gd")
const MessageWindowScene := preload("res://holyquintet_mod/ui/hq_message_window.tscn")
const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

const CATEGORY_NAMES := ["Controls", "Gameplay", "Visuals", "Language", "Other"]

## See this file's header: Conductor.startingBPM's real fallback value when
## no song/chart has set a bpmChangeMap, confirmed against CodenameEngine's
## own Conductor.hx source.
const OFFSET_PREVIEW_BPM := 100.0

const CONTROLS_LIST := [
	{"name": "Left Note", "type": "control", "parent_value": "p1_note_left"},
	{"name": "Down Note", "type": "control", "parent_value": "p1_note_down"},
	{"name": "Up Note", "type": "control", "parent_value": "p1_note_up"},
	{"name": "Right Note", "type": "control", "parent_value": "p1_note_right"},
	{"type": "separator"},
	{"name": "Left UI", "type": "control", "parent_value": "p1_left"},
	{"name": "Down UI", "type": "control", "parent_value": "p1_down"},
	{"name": "Up UI", "type": "control", "parent_value": "p1_up"},
	{"name": "Right UI", "type": "control", "parent_value": "p1_right"},
	{"type": "separator"},
	{"name": "Dodge", "type": "control", "parent_value": "p1_dodge"},
	{"type": "separator"},
	{"name": "Accept UI", "type": "control", "parent_value": "p1_accept"},
	{"name": "Back UI", "type": "control", "parent_value": "p1_back"},
	{"name": "Pause", "type": "control", "parent_value": "p1_pause"},
]

const GAMEPLAY_LIST := [
	{"name": "Downscroll", "type": "bool", "parent_value": "downscroll"},
	{"name": "Middlescroll", "type": "bool", "parent_value": "middle_scroll"},
	{"name": "Strum Underlay Alpha", "type": "int", "parent_value": "strum_underlay_alpha", "lower": 0, "upper": 100, "suffix": "%"},
	{"name": "Player Strum Scale", "type": "float", "parent_value": "player_strum_scale", "lower": 1.0, "upper": 1.3},
	{"name": "Scroll Speed", "type": "float", "parent_value": "player_strum_speed", "lower": 1.0, "upper": 1.5, "suffix": "x"},
	{"name": "Cam Zoom On Beat", "type": "bool", "parent_value": "cam_zoom_on_beat"},
	{"name": "Song Offset", "type": "int", "parent_value": "song_offset", "lower": -999, "upper": 999, "suffix": "ms"},
	{"name": "Reset Button", "type": "bool", "parent_value": "reset_button_enabled"},
	{"type": "separator"},
	{"name": "Streamed Music", "type": "bool", "parent_value": "streamed_music"},
	{"name": "Streamed Vocals", "type": "bool", "parent_value": "streamed_vocals"},
]

const VISUALS_LIST := [
	{"name": "Flashing Lights", "type": "bool", "parent_value": "flashing_lights"},
	{"name": "Shaders", "type": "bool", "parent_value": "gameplay_shaders"},
	{"name": "GPU Cache", "type": "bool", "parent_value": "gpu_only_bitmaps"},
	{"name": "Anti-aliasing", "type": "bool", "parent_value": "antialiasing"},
	{"name": "Low Memory Mode", "type": "bool", "parent_value": "low_memory_mode"},
	{"name": "Splash Notes", "type": "bool", "parent_value": "splashes_enabled"},
	{"name": "Framerate", "type": "int", "parent_value": "framerate", "lower": 60, "upper": 240, "suffix": " FPS"},
]

const LANGUAGE_LIST := [
	{"name": "English", "type": "language", "parent_value": "language", "value": "en_US"},
	{"name": "Spanish", "type": "language", "parent_value": "language", "value": "es_US"},
]

const OTHER_LIST := [
	{"name": "Mechanics", "type": "bool", "parent_value": "mechanics"},
	{"name": "Destroy Save Data", "type": "delete_data", "parent_value": ""},
]

var category_lists: Array = []

var in_sub_menu := false
var sm_cur_sel := 0
var sm_cur_cat := 0
var sm_sub_sel := 0
var can_control := true
var changing_keybind := false
var target_control_row: Control

var category_buttons: Array = []
var category_roots: Array = []
var category_rows: Array = []
var _scroll_tween: Tween
var message_window: Control
var rebind_overlay: Control
var music_player: AudioStreamPlayer
var metronome_player: AudioStreamPlayer
var _hold_time := 0.0
var _offsetting_option := false
var _last_offset_beat := -1

@onready var world: Control = $World
@onready var bg_spots: TextureRect = $World/BgSpots
@onready var bg_top_banner: TextureRect = $World/BgTopBanner
@onready var bg_btm_banner: TextureRect = $World/BgBtmBanner
@onready var fade_rect: ColorRect = $FadeRect


func _ready() -> void:
	category_lists = [CONTROLS_LIST, GAMEPLAY_LIST, VISUALS_LIST, LANGUAGE_LIST, OTHER_LIST]

	music_player = AudioStreamPlayer.new()
	var music_path := "res://holyquintet_mod/source/music/settings.ogg"
	if ResourceLoader.exists(music_path):
		var stream: AudioStream = load(music_path)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		music_player.stream = stream
		add_child(music_player)
		music_player.play()

	metronome_player = AudioStreamPlayer.new()
	var metronome_path := "res://holyquintet_mod/source/sounds/editors/charter/metronome.ogg"
	if ResourceLoader.exists(metronome_path):
		metronome_player.stream = load(metronome_path)
		add_child(metronome_player)

	_build_category_buttons()
	_build_option_rows()

	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)

	_change_selection(0)


func _build_category_buttons() -> void:
	for i in CATEGORY_NAMES.size():
		var btn := ButtonScene.instantiate()
		btn.style = "basic"
		btn.id = i
		btn.text = CATEGORY_NAMES[i]
		world.add_child(btn)
		world.move_child(btn, bg_top_banner.get_index())
		btn.position = Vector2(50.0 + 40.0 * i, 175.0 + 150.0 * i)
		btn.gui_input.connect(_on_category_gui_input.bind(i))
		category_buttons.append(btn)


func _build_option_rows() -> void:
	for cat_i in category_lists.size():
		var list: Array = category_lists[cat_i]
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world.add_child(root)
		world.move_child(root, bg_top_banner.get_index())
		root.visible = false
		category_roots.append(root)

		var rows: Array = []
		for i in list.size():
			var row: Control = RowScript.new()
			row.setup(list[i])
			row.position = Vector2(580.0 + 35.0 * i, 180.0 + 100.0 * i)
			root.add_child(row)
			row.activated.connect(_on_row_activated.bind(cat_i, i))
			rows.append(row)
		category_rows.append(rows)


func _process(delta: float) -> void:
	var spots_tex_w: float = bg_spots.texture.get_width()
	var spots_tex_h: float = bg_spots.texture.get_height()
	bg_spots.position.x -= 15.0 * delta
	bg_spots.position.y -= 25.0 * delta
	if bg_spots.position.x <= -spots_tex_w * 2.0:
		bg_spots.position.x += spots_tex_w
	if bg_spots.position.y <= -spots_tex_h * 2.0:
		bg_spots.position.y += spots_tex_h

	var banner_tex_w: float = bg_top_banner.texture.get_width()
	bg_top_banner.position.x += 5.0 * delta
	if bg_top_banner.position.x >= -30.0 + banner_tex_w:
		bg_top_banner.position.x -= banner_tex_w
	bg_btm_banner.position.x -= 5.0 * delta
	if bg_btm_banner.position.x <= -30.0 - banner_tex_w:
		bg_btm_banner.position.x += banner_tex_w

	_process_hold_repeat(delta)
	_process_song_offset_preview(delta)


## Real update(): holding Left/Right (not just tapping) re-applies the
## int/float step every single frame once held >= 0.5s — no re-arming
## delay after that, so a long hold fast-forwards through the range.
## _unhandled_input's own ui_left/ui_right handling only fires once per
## discrete keypress, so this frame-polled repeat is on top of that, not
## a replacement for it (matches real code: the discrete option.selection
## call in the "just switched direction" branch, PLUS this separate
## every-frame one once past the hold threshold).
func _process_hold_repeat(delta: float) -> void:
	if not in_sub_menu or changing_keybind or is_instance_valid(message_window) or not can_control:
		_hold_time = 0.0
		return
	var left_held := Input.is_action_pressed("ui_left")
	var right_held := Input.is_action_pressed("ui_right")
	if not (left_held or right_held):
		_hold_time = 0.0
		return
	_hold_time += delta
	if _hold_time < 0.5:
		return
	var rows: Array = _current_rows()
	if sm_sub_sel < 0 or sm_sub_sel >= rows.size():
		return
	var row: Control = rows[sm_sub_sel]
	var direction := -1 if left_held else 1
	match row.data.get("type"):
		"int":
			_step_int(row, direction)
		"float":
			_step_float(row, direction)


## See this file's header for the real update() this ports (music volume
## duck, camera zoom pulse per beat, metronome tick per beat, continuous
## zoom decay) and exactly which pieces (World scale as the "camera", the
## 100 BPM fallback, the consolidated single beat clock) are this port's
## own stand-ins for real objects (Conductor, a chart) that don't exist yet.
func _process_song_offset_preview(delta: float) -> void:
	if _offsetting_option and is_instance_valid(music_player) and music_player.playing:
		music_player.volume_db = linear_to_db(0.5)
		var beat := floori(music_player.get_playback_position() * OFFSET_PREVIEW_BPM / 60.0)
		if beat != _last_offset_beat:
			_last_offset_beat = beat
			if is_instance_valid(metronome_player):
				metronome_player.play()
			world.scale += Vector2(0.03, 0.03)
	else:
		if is_instance_valid(music_player):
			music_player.volume_db = 0.0
		_last_offset_beat = -1
	world.scale = Vector2(
		_fps_lerp(world.scale.x, 1.0, 0.25, delta),
		_fps_lerp(world.scale.y, 1.0, 0.25, delta)
	)


## Ports CoolUtil.fpsLerp/getFPSRatio exactly (confirmed against
## CodenameEngine's own CoolUtil.hx source, not guessed).
func _fps_lerp(v1: float, v2: float, ratio: float, delta: float) -> float:
	return lerpf(v1, v2, 1.0 - pow(1.0 - ratio, delta * 60.0))


func _unhandled_input(event: InputEvent) -> void:
	if changing_keybind:
		if event is InputEventKey and event.pressed and not event.echo:
			_finish_key_change(event)
		return

	if not can_control or is_instance_valid(message_window):
		return

	if not in_sub_menu:
		if event.is_action_pressed("ui_up"):
			_change_selection(-1)
		elif event.is_action_pressed("ui_down"):
			_change_selection(1)
		elif event.is_action_pressed("ui_accept"):
			_confirm_selection()
	else:
		if event.is_action_pressed("ui_up"):
			_change_selection(-1)
		elif event.is_action_pressed("ui_down"):
			_change_selection(1)
		elif event.is_action_pressed("ui_left"):
			_adjust_current(-1)
		elif event.is_action_pressed("ui_right"):
			_adjust_current(1)
		elif event.is_action_pressed("ui_accept"):
			_confirm_selection()

	if event.is_action_pressed("ui_cancel"):
		_back_selection()


func _current_rows() -> Array:
	return category_rows[sm_cur_cat]


func _change_selection(change: int) -> void:
	if not in_sub_menu:
		if change != 0:
			GenUtil.play_ui_sound(self, "move")
		sm_cur_sel = wrapi(sm_cur_sel + change, 0, category_buttons.size())
		for i in category_buttons.size():
			category_buttons[i].selected = i == sm_cur_sel
		for i in category_roots.size():
			category_roots[i].visible = i == sm_cur_sel
			for row in category_rows[i]:
				row.active = false
	else:
		if change != 0:
			GenUtil.play_ui_sound(self, "move")
		var rows: Array = _current_rows()
		sm_sub_sel = wrapi(sm_sub_sel + change, 0, rows.size())
		while rows[sm_sub_sel].data.get("type") == "separator":
			sm_sub_sel = wrapi(sm_sub_sel + change, 0, rows.size())
		_offsetting_option = false
		for i in rows.size():
			rows[i].selected = i == sm_sub_sel
			if i == sm_sub_sel and rows[i].data.get("name") == "Song Offset":
				_offsetting_option = true
		_update_scroll(rows.size())


## Real: `100 * bound(sm_subSel - 3, 0, len - 7)`, applied only when the
## list is actually longer than the ~7-row window (bound's lower clamp
## already keeps a short list's offset at 0, so no extra branch needed).
func _update_scroll(list_len: int) -> void:
	var scroll_offset: float = clampf(float(sm_sub_sel - 3), 0.0, maxf(list_len - 7.0, 0.0))
	var root: Control = category_roots[sm_cur_cat]
	if _scroll_tween:
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(root, "position", Vector2(-35.0 * scroll_offset, -100.0 * scroll_offset), 0.25).set_trans(Tween.TRANS_SINE)


func _confirm_selection() -> void:
	if not in_sub_menu:
		category_buttons[sm_cur_sel].selection()
		GenUtil.play_ui_sound(self, "confirm")
		sm_cur_cat = sm_cur_sel
		in_sub_menu = true
		for row in category_rows[sm_cur_cat]:
			row.active = true
		# sm_sub_sel is already 0 here — either the class default, or reset
		# by _back_selection()'s own submenu-exit branch the last time this
		# category was left. Real code: updateSubMenu() always follows with
		# changeSelection(0), same "just re-apply the current index" call.
		_change_selection(0)
	else:
		var rows: Array = _current_rows()
		if sm_sub_sel < 0 or sm_sub_sel >= rows.size():
			return
		_activate_row(rows[sm_sub_sel])


## Real update(): controls.LEFT_P/RIGHT_P toggles a selected bool option
## the same as Enter would (option.selection(0) — the argument is ignored
## for bool), on top of stepping int/float. Left and Right are otherwise
## equivalent for a bool row; direction is unused here for that reason.
func _adjust_current(direction: int) -> void:
	var rows: Array = _current_rows()
	if sm_sub_sel < 0 or sm_sub_sel >= rows.size():
		return
	var row: Control = rows[sm_sub_sel]
	match row.data.get("type"):
		"int":
			_step_int(row, direction)
		"float":
			_step_float(row, direction)
		"bool":
			_activate_row(row)


func _on_category_gui_input(event: InputEvent, i: int) -> void:
	if not can_control or in_sub_menu:
		return
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if not tapped:
		return
	_change_selection(i - sm_cur_sel)
	_confirm_selection()


func _on_row_activated(action: String, cat_i: int, row_i: int) -> void:
	if cat_i != sm_cur_cat or not in_sub_menu:
		return
	match action:
		"select":
			_change_selection(row_i - sm_sub_sel)
		"confirm":
			_change_selection(row_i - sm_sub_sel)
			_activate_row(category_rows[cat_i][row_i])
		"dec":
			_change_selection(row_i - sm_sub_sel)
			_adjust_current(-1)
		"inc":
			_change_selection(row_i - sm_sub_sel)
			_adjust_current(1)


func _activate_row(row: Control) -> void:
	match row.data.get("type"):
		"bool":
			HQOptions.set(row.data["parent_value"], not HQOptions.get(row.data["parent_value"]))
			GenUtil.play_ui_sound(self, "off" if HQOptions.get(row.data["parent_value"]) else "on")
			HQOptions.save_data()
			row.refresh_value()
		"language":
			HQOptions.language = row.data["value"]
			HQOptions.save_data()
			GenUtil.play_ui_sound(self, "confirm")
			for r in category_rows[sm_cur_cat]:
				r.refresh_value()
		"control":
			changing_keybind = true
			target_control_row = row
			_prompt_key_change(row)
		"delete_data":
			# Real: `if (!data.fromSong) { ...open dialog... } else
			# playUISound('error')` — Destroy Save Data is blocked when
			# Settings was reached from the pause menu mid-song.
			# settings_return_scene is only non-empty in that exact case
			# (set by the pause screen right before switching here, cleared
			# by _go_back() on the way out), so it's this port's fromSong.
			if not HQSaves.settings_return_scene.is_empty():
				GenUtil.play_ui_sound(self, "error")
			else:
				_prompt_delete_data()


func _step_int(row: Control, direction: int) -> void:
	var pv: String = row.data["parent_value"]
	var v: int = clampi(int(HQOptions.get(pv)) + direction, int(row.data["lower"]), int(row.data["upper"]))
	HQOptions.set(pv, v)
	HQOptions.save_data()
	row.refresh_value()


func _step_float(row: Control, direction: int) -> void:
	var pv: String = row.data["parent_value"]
	var v: float = clampf(float(HQOptions.get(pv)) + direction * 0.1, row.data["lower"], row.data["upper"])
	v = snappedf(v, 0.1)
	HQOptions.set(pv, v)
	HQOptions.save_data()
	row.refresh_value()


func _back_selection() -> void:
	GenUtil.play_ui_sound(self, "back")
	if not in_sub_menu:
		can_control = false
		if is_instance_valid(music_player):
			music_player.stop()
		_go_back()
	else:
		in_sub_menu = false
		for row in category_rows[sm_cur_cat]:
			row.selected = false
			row.active = false
		sm_sub_sel = 0
		if _scroll_tween:
			_scroll_tween.kill()
		category_roots[sm_cur_cat].position = Vector2.ZERO
	_offsetting_option = false


func _go_back() -> void:
	var dest := "res://holyquintet_mod/menus/main/main_menu.tscn"
	if not HQSaves.settings_return_scene.is_empty():
		dest = HQSaves.settings_return_scene
		HQSaves.settings_return_scene = ""
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file(dest))


## Real: a fullscreen black overlay + "Press a key for X" prompt; the next
## keypress (FlxG.keys.justPressed.ANY) rebinds and closes it. Keyboard-only
## by nature, same as the real feature — nothing to adapt for touch, since
## no gameplay exists anywhere in this port yet to actually read any of
## these binds regardless.
func _prompt_key_change(row: Control) -> void:
	rebind_overlay = Control.new()
	rebind_overlay.position = Vector2.ZERO
	rebind_overlay.size = Vector2(1920.0, 1080.0)
	rebind_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rebind_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.position = Vector2.ZERO
	dim.size = Vector2(1920.0, 1080.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rebind_overlay.add_child(dim)

	var label := Label.new()
	label.position = Vector2(0.0, 490.0)
	label.size = Vector2(1920.0, 100.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.text = "Press a key for %s" % row.data.get("name", "")
	rebind_overlay.add_child(label)


func _finish_key_change(event: InputEventKey) -> void:
	if is_instance_valid(rebind_overlay):
		rebind_overlay.queue_free()
	rebind_overlay = null
	HQOptions.set(target_control_row.data["parent_value"], OS.get_keycode_string(event.keycode if event.keycode != 0 else event.physical_keycode))
	HQOptions.save_data()
	target_control_row.refresh_value()
	target_control_row = null
	changing_keybind = false


## Real: FlxG.save.data / Options.__save both erased, then Sys.exit() —
## see this file's header comment for why get_tree().quit() stands in.
func _prompt_delete_data() -> void:
	can_control = false
	message_window = MessageWindowScene.instantiate()
	message_window.title_text = "Destroy Save Data?"
	message_window.body_text = "This cannot be undone."
	message_window.icon_name = "danger"
	message_window.on_left = func(): pass
	message_window.on_right = func():
		HQSaves.erase_save_file()
		HQOptions.erase_save()
		get_tree().quit()
	message_window.on_complete = func():
		message_window.queue_free()
		message_window = null
		can_control = true
	message_window.on_back = func():
		message_window.queue_free()
		message_window = null
		can_control = true
	add_child(message_window)
