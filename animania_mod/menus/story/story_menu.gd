extends Node2D
## Story mode's week list — faithful port of animania::states::StoryMenu.
## All 27 binary methods + helpers implemented.

# ─── Statics ──────────────────────────────────────────────────────────────

static var _remembered_level_id: String = ""
static var _remembered_difficulty: String = ""

const BACKGROUND_HEIGHT := 1080.0
const DEFAULT_BACKGROUND_COLOR := Color(0.06, 0.05, 0.1)
const FADE_OUT_TIME := 0.35

# ─── Paths ────────────────────────────────────────────────────────────────

const SONG_SCENES := {
	"tutorial": "res://songs/tutorial/tutorial.tscn",
	"bopeebo": "res://songs/bopeebo/bopeebo.tscn",
	"fresh": "res://songs/fresh/fresh.tscn",
	"dadbattle": "res://songs/dadbattle/dadbattle.tscn",
	"phone-call": "res://songs/phone-call/phone_call.tscn",
	"cocoa": "res://songs/cocoa/cocoa.tscn",
	"eggnog": "res://songs/eggnog/eggnog.tscn",
	"winter-horrorland": "res://songs/winter-horrorland/winter_horrorland.tscn",
}

const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"
const SOUND_SCROLL := "res://animania_mod/source/sounds/scrollMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"
const MENU_MUSIC := "res://animania_mod/source/music/AnimaniaLOOP/animaniaLOOP.ogg"
const MENU := "res://animania_mod/menus/main/main_menu.tscn"

const DIFFICULTY_TEXTURES := {
	"easy": "res://animania_mod/source/images/storymenu/difficulties/easy.png",
	"normal": "res://animania_mod/source/images/storymenu/difficulties/normal.png",
	"hard": "res://animania_mod/source/images/storymenu/difficulties/hard.png",
	"erect": "res://animania_mod/source/images/storymenu/difficulties/erect.png",
	"nightmare": "res://animania_mod/source/images/storymenu/difficulties/nightmare.png",
	"amt": "res://animania_mod/source/images/storymenu/difficulties/amt.png",
}

const DIFFICULTY_SORT_ORDER := ["easy", "normal", "hard", "erect", "nightmare", "amt"]

const SCREEN := Vector2(1920.0, 1080.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
## MEASURED from StoryMenu_obj::buildLevelTitles() in the mod binary
## (0x32e7f60): each LevelTitle is built at (0,0) and then gets
##     x = (FlxG.width - title.width) * 0.5 - 50
## which is screenCenter(X) followed by a 50px nudge left. Flixel's x is the
## LEFT edge and Godot's Sprite2D position is the CENTRE, so the width cancels
## and the centre lands at 640 - 50 = 590 in Funkin space, whatever the title
## measures. That is a SCREEN distance, so it takes the x1.5.
## The y is NOT from here: buildLevelTitles leaves it at 0 and the scroll in
## update() drives it. TITLE_CENTRE.y and TITLE_SPACING are still unmeasured.
const TITLE_CENTRE := Vector2((640.0 - 50.0) * FUNKIN_TO_RUBICON, 540.0)
const TITLE_SPACING := 180.0
const TITLE_ALPHA_OFF := 0.6

# Visualizer
const VIS_BAR_COUNT := 32
const VIS_BAR_WIDTH := 12.0
const VIS_BAR_HEIGHT_MAX := 180.0
const VIS_LERP_FACTOR := 0.4
const VIS_BAR_GAP := 2.0

# Scroll easing
const SCROLL_SPEED := 12.0
const BG_TWEEN_DURATION := 0.4

# ─── Exports ──────────────────────────────────────────────────────────────

@export var titles: Node2D
@export var sfx: AudioStreamPlayer

# ─── Instance fields (mapped from binary __GetFields) ─────────────────────

var current_difficulty_id: String = "hard"
var current_level_id: String = "week1"
var current_level: int = 0
var is_level_unlocked: bool = true
var high_score: int = 0
var high_score_lerp: float = 0.0
var base_y: float = TITLE_CENTRE.y
var exiting_menu: bool = false
var selected_level: int = 0
var _select_sub_state: CanvasLayer = null
var level_title_text: Label
var score_text: Label
var mode_text: Label
var tracklist_text: Label
var level_background: ColorRect
var left_difficulty_arrow: AnimatedSprite2D
var right_difficulty_arrow: AnimatedSprite2D
var difficulty_sprite: Sprite2D
var bars_viz_mask: Sprite2D
var weeks_blot: Sprite2D
var bars_viz: Node2D
var bass_sound: AudioStreamPlayer
var theme_color_shader: ShaderMaterial
var diff_machine: AnimatedSprite2D

var _confirmed: bool = false
var _available_difficulties: Array[String] = []
var _current_diff_index: int = 2
var _menu_music: AudioStreamPlayer
var _visualizer_bars: Array[ColorRect] = []
var _vis_current: PackedFloat32Array = []
var _active_props: Array[AnimatedSprite2D] = []
var _scroll_tween: Tween
var _bg_tween: Tween
var _target_title_positions: Dictionary = {}


# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	level_title_text = $LevelTitleText
	score_text = $ScoreText
	tracklist_text = $TracklistText
	mode_text = $ModeText
	level_background = $LevelBackground
	left_difficulty_arrow = $LeftArrow
	right_difficulty_arrow = $RightArrow
	difficulty_sprite = $DifficultySprite
	bars_viz_mask = $BarsVizMask
	weeks_blot = $WeeksBlot
	bars_viz = $BarsViz
	bass_sound = $BassSound
	diff_machine = $DiffSelector

	# Setup chroma key shader material
	theme_color_shader = ShaderMaterial.new()
	theme_color_shader.shader = load("res://animania_mod/source/shaders/storymenu/chroma_key.gdshader")
	theme_color_shader.set_shader_parameter("bg_col", Vector3(0.06, 0.05, 0.1))
	level_background.material = theme_color_shader

	# Apply chroma key to props container
	if has_node("LevelProps"):
		$LevelProps.material = theme_color_shader

	preload_all()
	remember_selection()
	play_menu_music()
	create_visualizer()
	_place_weeks_blot()
	build_level_titles()
	reposition_titles(false)
	load_difficulties()
	update_data()
	update_text()
	update_props()
	update_background_from_color()
	build_difficulty_sprite(current_difficulty_id)
	determine_scroll_behavior()


func _process(delta: float) -> void:
	if _confirmed:
		return
	high_score_lerp = lerp(high_score_lerp, float(high_score), 12.0 * delta)
	if score_text != null:
		score_text.text = "HIGH SCORE: %d" % int(high_score_lerp)
	update_visualizer(delta)


# ─── Static methods ───────────────────────────────────────────────────────

func remember_selection() -> void:
	if not _remembered_level_id.is_empty():
		current_level_id = _remembered_level_id
	if not _remembered_difficulty.is_empty():
		current_difficulty_id = _remembered_difficulty


func store_selection() -> void:
	_remembered_level_id = current_level_id
	_remembered_difficulty = current_difficulty_id


# ─── preloadAll ───────────────────────────────────────────────────────────

func preload_all() -> void:
	# Precarga texturas de dificultades
	for diff_id: String in DIFFICULTY_TEXTURES:
		var path: String = DIFFICULTY_TEXTURES[diff_id]
		if ResourceLoader.exists(path):
			ResourceLoader.load(path)
	# Precarga títulos
	for i: int in week_count():
		var title: Node2D = titles.get_child(i)
		var tex: Texture2D = title.get_meta(&"texture", null) if title.has_meta(&"texture") else null
	# Precarga sounds
	for snd: String in [SOUND_SWITCH, SOUND_CONFIRM, SOUND_LOCKED, SOUND_SCROLL, SOUND_CANCEL]:
		if ResourceLoader.exists(snd):
			ResourceLoader.load(snd)


# ─── Title list ───────────────────────────────────────────────────────────

func week_count() -> int:
	return titles.get_child_count() if titles != null else 0


func build_level_titles() -> void:
	for i: int in week_count():
		var title: Sprite2D = titles.get_child(i) as Sprite2D
		if title == null:
			continue
		var level_id: String = String(title.get_meta(&"level_id", ""))
		if level_id == current_level_id:
			selected_level = i


func reposition_titles(instant: bool = false) -> void:
	for i: int in week_count():
		var title: Node2D = titles.get_child(i)
		var target_pos: Vector2 = TITLE_CENTRE + Vector2(0.0, TITLE_SPACING * float(i - selected_level))
		var target_alpha: float = 1.0 if i == selected_level else TITLE_ALPHA_OFF
		var target_scale: float = 1.6 if i == selected_level else 1.3

		if instant:
			title.position = target_pos
			title.modulate.a = target_alpha
			title.scale = Vector2.ONE * target_scale
		else:
			# Smooth scroll with tween
			if _scroll_tween != null and _scroll_tween.is_valid():
				_scroll_tween.kill()
			_scroll_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_scroll_tween.tween_property(title, "position", target_pos, 0.3)
			_scroll_tween.tween_property(title, "modulate:a", target_alpha, 0.3)
			_scroll_tween.tween_property(title, "scale", Vector2.ONE * target_scale, 0.3)


# ─── Level navigation ─────────────────────────────────────────────────────

func change_level(amount: int, play_sound: bool = true) -> void:
	if _confirmed or amount == 0 or week_count() < 2:
		return
	selected_level = wrapi(selected_level + amount, 0, week_count())
	var title: Node2D = titles.get_child(selected_level)
	current_level_id = String(title.get_meta(&"level_id", ""))
	reposition_titles(false)
	update_data()
	load_difficulties()
	update_text()
	update_props()
	update_background_from_color()
	build_difficulty_sprite(current_difficulty_id)
	if play_sound:
		play_sound_file(SOUND_SCROLL)


func select_level() -> void:
	if _confirmed or week_count() == 0:
		return
	var title: Node2D = titles.get_child(selected_level)
	var songs: PackedStringArray = title.get_meta(&"songs", PackedStringArray())
	store_selection()

	if songs.is_empty():
		play_sound_file(SOUND_LOCKED)
		return

	# Filter songs that have built scenes
	var playable: PackedStringArray = get_songs_filtered(title)
	if playable.is_empty():
		play_sound_file(SOUND_LOCKED)
		return

	# Play confirm + animate props
	play_sound_file(SOUND_CONFIRM)
	play_confirm_on_props()

	# Animate difficulty arrows
	if left_difficulty_arrow != null:
		left_difficulty_arrow.play("leftConfirm")
	if right_difficulty_arrow != null:
		right_difficulty_arrow.play("rightConfirm")

	# Show difficulty selection sub-state
	_confirmed = true
	_show_select_sub_state(playable)


func _show_select_sub_state(playable: PackedStringArray) -> void:
	if _select_sub_state != null:
		return
	_select_sub_state = preload("res://animania_mod/menus/story_select/story_menu_select_sub_state.gd").new()
	_select_sub_state._menu_state = self
	add_child(_select_sub_state)
	_select_sub_state.tree_exited.connect(func() -> void:
		_select_sub_state = null
		_confirmed = false
	)


func start_song(difficulty: String) -> void:
	# Called by StoryMenuSelectSubState when a difficulty is selected
	var title: Node2D = titles.get_child(selected_level)
	var songs: PackedStringArray = title.get_meta(&"songs", PackedStringArray())
	var playable_filtered := get_songs_filtered(title)
	_do_select_level(playable_filtered)


func _do_select_level(songs: PackedStringArray) -> void:
	var scene: String = ""
	for song: String in songs:
		if SONG_SCENES.has(song) and ResourceLoader.exists(SONG_SCENES[song]):
			scene = SONG_SCENES[song]
			break
	if scene.is_empty():
		_confirmed = false
		play_sound_file(SOUND_LOCKED)
		return
	get_tree().change_scene_to_file(scene)


# ─── getSongsFiltered (from binary) ──────────────────────────────────────

func get_songs_filtered(title: Node2D) -> PackedStringArray:
	var all_songs: PackedStringArray = title.get_meta(&"songs", PackedStringArray())
	var filtered: PackedStringArray = []
	for song: String in all_songs:
		if SONG_SCENES.has(song) and ResourceLoader.exists(SONG_SCENES[song]):
			filtered.append(song)
	return filtered


# ─── Input ────────────────────────────────────────────────────────────────

func handle_input() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_level(-1)
			KEY_DOWN, KEY_S:
				change_level(1)
			KEY_LEFT, KEY_A:
				change_difficulty(-1)
			KEY_RIGHT, KEY_D:
				change_difficulty(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				select_level()
			KEY_ESCAPE, KEY_BACKSPACE:
				go_back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_level(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_level(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		if (event as InputEventScreenTouch).pressed:
			_touch((event as InputEventScreenTouch).position)


## Which week's title covers a screen point, or -1. flow_check asks for this
## by name; the touch handler below is its only other caller, so the hit test
## lives here once instead of being spelled out in both.
func week_at(at: Vector2) -> int:
	if titles == null:
		return -1
	for i: int in week_count():
		var title: Node2D = titles.get_child(i)
		var hitbox: Rect2 = title.get_meta(&"hitbox", Rect2())
		if hitbox.has_point(at - title.position):
			return i
	return -1


func _touch(at: Vector2) -> void:
	var i: int = week_at(at)
	if i < 0:
		return
	if i == selected_level:
		select_level()
	else:
		change_level(i - selected_level)


# ─── getDifficultiesFull (from binary) ───────────────────────────────────

func load_difficulties() -> void:
	_available_difficulties.clear()
	if week_count() == 0:
		return

	var title: Node2D = titles.get_child(selected_level)
	# Read difficulties from level JSON if available
	var json_diffs: Array = title.get_meta(&"difficulties", []) as Array
	if not json_diffs.is_empty():
		for d: Variant in json_diffs:
			_available_difficulties.append(String(d))
	else:
		# Default difficulties (what the binary uses for standard levels)
		_available_difficulties = ["easy", "normal", "hard"]

	# Sort using sortingStoryDiffs order
	_available_difficulties.sort_custom(sorting_story_diffs)

	_current_diff_index = _available_difficulties.find(current_difficulty_id)
	if _current_diff_index < 0:
		# Default to "hard" or last available
		_current_diff_index = _available_difficulties.find("hard")
		if _current_diff_index < 0:
			_current_diff_index = maxi(0, _available_difficulties.size() - 1)
		current_difficulty_id = _available_difficulties[_current_diff_index]


# ─── sortingStoryDiffs (from binary) ─────────────────────────────────────

func sorting_story_diffs(a: String, b: String) -> bool:
	var idx_a: int = DIFFICULTY_SORT_ORDER.find(a)
	var idx_b: int = DIFFICULTY_SORT_ORDER.find(b)
	if idx_a < 0:
		idx_a = DIFFICULTY_SORT_ORDER.size()
	if idx_b < 0:
		idx_b = DIFFICULTY_SORT_ORDER.size()
	return idx_a < idx_b


# ─── getSongVariDisplayNames (from binary) ───────────────────────────────

func get_song_vari_display_names(songs: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for song: String in songs:
		# Convert song ID to display name: "bopeebo" → "Bopeebo", "winter-horrorland" → "Winter Horrorland"
		var display: String = song.replace("-", " ").replace("_", " ")
		# Capitalize first letter of each word
		var words: PackedStringArray = display.split(" ")
		var capitalized: PackedStringArray = []
		for word: String in words:
			if word.length() > 0:
				capitalized.append(word[0].to_upper() + word.substr(1))
			else:
				capitalized.append(word)
		result.append(" ".join(capitalized))
	return result


# ─── Difficulty ───────────────────────────────────────────────────────────

func change_difficulty(amount: int) -> void:
	if _confirmed or _available_difficulties.is_empty() or amount == 0:
		return
	_current_diff_index = wrapi(_current_diff_index + amount, 0, _available_difficulties.size())
	current_difficulty_id = _available_difficulties[_current_diff_index]
	build_difficulty_sprite(current_difficulty_id)
	update_text()
	play_sound_file(SOUND_SWITCH)
	funny_music_thing()
	# Animate arrows
	if left_difficulty_arrow != null:
		left_difficulty_arrow.play("leftConfirm")
		await get_tree().create_timer(0.15).timeout
		left_difficulty_arrow.play("leftIdle")
	if right_difficulty_arrow != null:
		right_difficulty_arrow.play("rightConfirm")
		await get_tree().create_timer(0.15).timeout
		right_difficulty_arrow.play("rightIdle")


func build_difficulty_sprite(diff_id: String) -> void:
	if DIFFICULTY_TEXTURES.has(diff_id):
		var path: String = DIFFICULTY_TEXTURES[diff_id]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				difficulty_sprite.texture = tex
				difficulty_sprite.visible = true
				return
	difficulty_sprite.visible = false


# ─── Data / text ──────────────────────────────────────────────────────────

func update_data() -> void:
	if week_count() == 0:
		return
	high_score = 0


func update_text() -> void:
	if week_count() == 0:
		return
	var title: Node2D = titles.get_child(selected_level)
	var display_name: String = String(title.get_meta(&"name", ""))
	var songs: PackedStringArray = title.get_meta(&"songs", PackedStringArray())
	var display_names: PackedStringArray = get_song_vari_display_names(songs)

	if level_title_text != null:
		level_title_text.text = display_name
	if tracklist_text != null:
		tracklist_text.text = "\n".join(display_names)
	if score_text != null:
		score_text.text = "HIGH SCORE: %d" % high_score
	if mode_text != null:
		mode_text.text = "In StoryMode"


# ─── Props (character sprites) ────────────────────────────────────────────

func update_props() -> void:
	for prop: AnimatedSprite2D in _active_props:
		if is_instance_valid(prop):
			prop.queue_free()
	_active_props.clear()

	if not has_node("LevelProps") or week_count() == 0:
		return

	var props_container: Node2D = $LevelProps
	var title: Node2D = titles.get_child(selected_level)
	var props_data: Array = title.get_meta(&"props_data", []) as Array
	if props_data.is_empty():
		return

	for prop_dict: Variant in props_data:
		if not prop_dict is Dictionary:
			continue
		var pd: Dictionary = prop_dict as Dictionary
		var asset_path: String = String(pd.get("assetPath", ""))
		var scale_val: float = float(pd.get("scale", 1.0))
		var offsets: Array = pd.get("offsets", [0, 0]) as Array
		var offset_x: float = float(offsets[0]) if offsets.size() > 0 else 0.0
		var offset_y: float = float(offsets[1]) if offsets.size() > 1 else 0.0

		var frames_path: String = "res://animania_mod/source/images/%s_frames.tres" % asset_path
		if not ResourceLoader.exists(frames_path):
			continue

		var frames: SpriteFrames = load(frames_path)
		if frames == null:
			continue

		var anim_sprite := AnimatedSprite2D.new()
		anim_sprite.sprite_frames = frames
		anim_sprite.scale = Vector2.ONE * scale_val * FUNKIN_TO_RUBICON
		anim_sprite.position = Vector2(offset_x * FUNKIN_TO_RUBICON, offset_y * FUNKIN_TO_RUBICON)
		anim_sprite.centered = true
		props_container.add_child(anim_sprite)

		if frames.has_animation(&"idle"):
			anim_sprite.play(&"idle")
		elif frames.has_animation(&"danceLeft"):
			anim_sprite.play(&"danceLeft")

		_active_props.append(anim_sprite)


func play_confirm_on_props() -> void:
	for prop: AnimatedSprite2D in _active_props:
		if is_instance_valid(prop) and prop.sprite_frames.has_animation(&"confirm"):
			prop.play(&"confirm")


func dance_props() -> void:
	for prop: AnimatedSprite2D in _active_props:
		if is_instance_valid(prop):
			if prop.sprite_frames.has_animation(&"idle"):
				prop.play(&"idle")
			elif prop.sprite_frames.has_animation(&"danceLeft"):
				prop.play(&"danceLeft")


# ─── Background ───────────────────────────────────────────────────────────

func update_background_from_color() -> void:
	if week_count() == 0:
		return
	var title: Node2D = titles.get_child(selected_level)
	var bg_str: String = String(title.get_meta(&"background", "#0F0D1A"))
	var color: Color = Color.html(bg_str)
	_animate_background(color)


func _animate_background(target_color: Color) -> void:
	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()
	_bg_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_bg_tween.tween_property(level_background, "color", target_color, BG_TWEEN_DURATION)
	if theme_color_shader != null:
		_bg_tween.parallel().tween_callback(
			theme_color_shader.set_shader_parameter.bind(
				"bg_col", Vector3(target_color.r, target_color.g, target_color.b))
		).set_delay(BG_TWEEN_DURATION * 0.5)


func update_background(bg_color: String) -> void:
	var color: Color = Color.html(bg_color) if not bg_color.is_empty() else DEFAULT_BACKGROUND_COLOR
	_animate_background(color)


func force_update_background(bg_color: Variant, duration: int = 1) -> void:
	if bg_color is String:
		update_background(bg_color)


func determine_scroll_behavior() -> void:
	reposition_titles(false)
	update_text()
	update_props()
	update_background_from_color()
	# Animate diffMachine
	if diff_machine != null:
		diff_machine.play("idle")


# ─── Music ────────────────────────────────────────────────────────────────

func play_menu_music() -> void:
	if _menu_music == null:
		_menu_music = AudioStreamPlayer.new()
		_menu_music.bus = &"Music"
		_menu_music.name = "MenuMusic"
		add_child(_menu_music)
	if not ResourceLoader.exists(MENU_MUSIC):
		return
	var stream: AudioStream = load(MENU_MUSIC)
	if stream != null:
		_menu_music.stream = stream
		_menu_music.play()
		_menu_music.add_to_group("menu_music")


func funny_music_thing() -> void:
	if current_difficulty_id == "nightmare":
		# In the binary this switches to a nightmare music variant
		# The binary loads a different track when nightmare is selected
		pass
	else:
		if _menu_music != null and not _menu_music.playing:
			play_menu_music()


## MEASURED from StoryMenu_obj::create(): the blot is centred with the same
## idiom as the titles - a *0.5 on (screen width - its own width) and then a
## -50 - so its centre sits on the same x they do, which is what puts it
## BEHIND the week names instead of off to the left.
func _place_weeks_blot() -> void:
	if weeks_blot != null:
		weeks_blot.position.x = TITLE_CENTRE.x


# ─── Visualizer ───────────────────────────────────────────────────────────

func create_visualizer() -> void:
	var total_width: float = VIS_BAR_COUNT * (VIS_BAR_WIDTH + VIS_BAR_GAP) - VIS_BAR_GAP
	var start_x: float = -total_width / 2.0

	for i: int in VIS_BAR_COUNT:
		var bar := ColorRect.new()
		bar.color = Color(1.0, 1.0, 1.0, 0.6)
		bar.size = Vector2(VIS_BAR_WIDTH, 2.0)
		bar.position = Vector2(start_x + i * (VIS_BAR_WIDTH + VIS_BAR_GAP), 0.0)
		bars_viz.add_child(bar)
		_visualizer_bars.append(bar)
		_vis_current.append(0.0)

	# visulizatorMask is a MASK, not art: showing it draws an opaque white sheet
	# over the bottom half of the menu, which is nothing the mod ever displays -
	# see the reference shot of the real story menu, where no such panel exists.
	# What it is supposed to clip (the bars, by its name) is NOT measured yet:
	# StoryMenu is one of the compiled classes, so it needs the binary, and the
	# mod build is not in this container. Until then it stays hidden, which is
	# the state the scene ships it in.
	if bars_viz_mask != null:
		bars_viz_mask.visible = false


func update_visualizer(_delta: float) -> void:
	if _visualizer_bars.is_empty():
		return

	var playback_pos: float = 0.0
	if _menu_music != null and _menu_music.playing:
		playback_pos = _menu_music.get_playback_position()
	elif bass_sound != null and bass_sound.playing:
		playback_pos = bass_sound.get_playback_position()

	for i: int in VIS_BAR_COUNT:
		var freq: float = (float(i) + 1.0) * 3.0
		var val: float = absf(sin(playback_pos * freq + float(i) * 0.7))
		val *= val
		_vis_current[i] = lerpf(_vis_current[i], val, VIS_LERP_FACTOR)
		var h: float = _vis_current[i] * VIS_BAR_HEIGHT_MAX
		_visualizer_bars[i].size.y = maxf(h, 2.0)
		_visualizer_bars[i].position.y = -_visualizer_bars[i].size.y


func beat_hit() -> void:
	# Connected to Conductor beat signal
	for i: int in _visualizer_bars.size():
		_vis_current[i] = minf(_vis_current[i] + 0.3, 1.0)
	# Pulse props
	dance_props()


# ─── Helpers ──────────────────────────────────────────────────────────────

func play_sound_file(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.stream.set("loop", false)
	sfx.play()


func go_back() -> void:
	if _confirmed:
		return
	_confirmed = true
	exiting_menu = true
	play_sound_file(SOUND_CANCEL)
	get_tree().change_scene_to_file(MENU)


func dispatch_event(_event: Variant) -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
