extends Node2D
## Story mode's week list — faithful port of animania::states::StoryMenu.
## All 27 binary methods + helpers implemented.

# ─── Statics ──────────────────────────────────────────────────────────────

static var _remembered_level_id: String = ""
static var _remembered_difficulty: String = ""

## MEASURED from StoryMenu_obj::__boot() in the mod binary: the static is
## written with `movl $0x190` at 0x32e9824, so BACKGROUND_HEIGHT is 400 Funkin
## pixels - a BAND across the middle, not the whole screen. The port had 1080
## here and painted the level colour edge to edge, which is why the render had
## no black letterbox above and below the way the mod does.
## It is a screen distance, so it takes the x1.5.
const BACKGROUND_HEIGHT := 400.0

## The band's TOP, not a centred offset. updateBackground loads 56 twice
## (0x32ed349 and 0x32ed701), and the 1280x720 reference confirms it to the
## pixel: the purple starts at y=57 in every clear column and the black bar
## above it is exactly 56 tall. The port centred the band instead, which put it
## 104 Funkin pixels too low and made the top bar four times too tall.
const BACKGROUND_Y := 56.0

## How far below the band's top edge the level props hang. Measured: their art
## tops sit at 77, 68 and 79 in the reference, a mean of 19 under the band's 56.
const PROP_TOP_DROP := 19.0
const DEFAULT_BACKGROUND_COLOR := Color(0.06, 0.05, 0.1)
const DEFAULT_BACKGROUND_COLOR_V3 := Vector3(0.06, 0.05, 0.1)
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

## MEASURED from StoryMenu_obj::update() at 0x32f616f: the string is
## "LEVEL SCORE: {1}", behind the localisation key "story_level_score".
## The port said "HIGH SCORE:", which is Funkin's wording, not Animania's.
const SCORE_FORMAT := "LEVEL SCORE: %d"

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
## x is MEASURED in buildLevelTitles (0x32e7f60) as screenCenter(X) minus 50,
## so the centre lands at 640-50 = 590 whatever the title measures. The
## 1280x720 reference agrees to within 6px: WEEK 1's white spans x 406..762,
## centre 584.
##
## y and the spacing come from that same reference, because buildLevelTitles
## leaves y at 0 and update()'s scroll drives it: the selected title's centre
## sits at 584 and the one above it at 470, so the step is 115. The port had
## 540 and 180 in RUBICON units - 360 and 120 in Funkin's - which floated the
## whole stack a hundred and fifty pixels high.
const TITLE_CENTRE := Vector2(590.0 * FUNKIN_TO_RUBICON, 584.0 * FUNKIN_TO_RUBICON)
const TITLE_SPACING := 115.0 * FUNKIN_TO_RUBICON
## MEASURED: the unselected titles are nearly invisible. WEEK 5's stroke reads
## (75, 72, 77) over a blot of (55, 52, 57), which is alpha 0.10 - not the 0.6
## the port used, which made them read as a second and third label competing
## with the selected week. TUTORIAL measures lower still (0.035) because its
## upper half is behind the band's edge.
const TITLE_ALPHA_OFF := 0.10

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
var week_diff_box: Sprite2D
var tracks_box: Sprite2D
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
	week_diff_box = $WeekDiffBox
	tracks_box = $TracksBox
	bars_viz = $BarsViz
	bass_sound = $BassSound
	diff_machine = $DiffSelector

	# After every node reference exists: these read the sprites' own sizes.
	_size_level_background()
	_place_boxes()
	_apply_z_order()
	_fit_difficulty_block()

	# Setup chroma key shader material
	# chroma_key exists for the PROPS, not for the background. The prop art is
	# green-screened - BF_STANDART_MENU samples as (0,240,0) over most of its
	# opaque area - and the shader keys that green out and redraws the rest as a
	# flat silhouette tinted by bg_col, which is what gives the mod's line-art
	# characters over the level colour.
	#
	# The port had it on level_background, a plain ColorRect where keying does
	# nothing useful, and on the LevelProps container. A material on a Node2D
	# parent is NOT inherited by its children in Godot - each CanvasItem needs
	# its own - so the props were drawn raw and came out bright green.
	theme_color_shader = ShaderMaterial.new()
	theme_color_shader.shader = load("res://animania_mod/source/shaders/storymenu/chroma_key.gdshader")
	theme_color_shader.set_shader_parameter("bg_col", DEFAULT_BACKGROUND_COLOR_V3)

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
		score_text.text = SCORE_FORMAT % int(high_score_lerp)
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
	# ONE tween for the whole list, built before the loop. It used to be created
	# inside it, so each week killed the tween of the week before and only the
	# LAST title ever reached its target - which is why the menu rendered with a
	# single week on screen and the others still stacked at the origin.
	if not instant:
		if _scroll_tween != null and _scroll_tween.is_valid():
			_scroll_tween.kill()
		_scroll_tween = create_tween().set_parallel(true) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

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
		score_text.text = SCORE_FORMAT % high_score
	if mode_text != null:
		mode_text.text = "In StoryMode"


# ─── Props (character sprites) ────────────────────────────────────────────

## Matches an animation by SUFFIX, because these atlases prefix every name with
## the character ("bf idle", "dad confirm").
func _find_anim(f: SpriteFrames, suffix: String) -> StringName:
	if f == null:
		return &""
	for n: StringName in f.get_animation_names():
		if String(n) == suffix or String(n).ends_with(" " + suffix):
			return n
	return &""


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

	var _prop_index: int = 0
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

		# These Animate atlases carry frameX/frameY that are NOT a trim inset:
		# BF's frame is 344x496 around a 338x487 region - a 6x9 difference - yet
		# frameY is 144, which cannot be an inset into it. The importer's
		# standard formula turns that into margin.position (-14,-144), and a
		# negative position on a Godot AtlasTexture draws the region outside the
		# padded frame, where it is CLIPPED. That is what beheaded BF.
		#
		# The padding is under 2% on both axes, so dropping it costs nothing and
		# the art draws whole. Done on a duplicate: the .tres is shared.
		frames = frames.duplicate(true)
		for anim_name: StringName in frames.get_animation_names():
			for fi: int in frames.get_frame_count(anim_name):
				var at: AtlasTexture = frames.get_frame_texture(anim_name, fi) as AtlasTexture
				if at != null and at.margin != Rect2():
					at.margin = Rect2()

		var anim_sprite := AnimatedSprite2D.new()
		anim_sprite.sprite_frames = frames
		anim_sprite.scale = Vector2.ONE * scale_val * FUNKIN_TO_RUBICON
		# Level_obj::buildProps (0x3ec1ee0) sets only x, and it does it as
		#     x = FlxG.width * 0.25 * index + offsets[0]
		# read off 0x3ec22a9..0x3ec2337 - FlxG.width, *0.25, * the loop index in
		# %r13d, the "offsets" entry added, all through set_x at vtable slot 0x210.
		# It takes set_y not once, so y never gets assigned there.
		#
		# That formula does NOT reproduce the reference, and the discrepancy is not
		# a constant bias, so it is not something to shim. Measured off the mod's
		# own 1280x720 capture, with both sides in idle and overlaid at 50%, the
		# cast's art centres sit at 213, 630 and 1053: a step of 417 and 423, near
		# enough constant, where that formula would step by 320. Those centres are
		# the screen split into equal slots with each prop in the middle of one -
		# 1280/6, 1280/2, 5*1280/6 = 213, 640, 1067, within 14px of measured.
		#
		# So the slots are what gets used, and it generalises to any number of
		# props. offsets[0] is left out for the same reason offsets[1] is: applying
		# it moves the cast away from where the mod draws it, not towards.
		# The residual against buildProps is unexplained and stays written down
		# rather than papered over.
		var slots: int = maxi(1, props_data.size())
		var centre_x: float = SCREEN.x * float(2 * _prop_index + 1) / float(2 * slots)
		# Not flush with the band's edge: the reference puts the cast's art tops
		# at 77, 68 and 79 against a band top of 56, so they hang about 19 below
		# it. Averaged, because the per-character spread is their own atlas trim.
		var top: float = (BACKGROUND_Y + PROP_TOP_DROP) * FUNKIN_TO_RUBICON
		var frame_size: Vector2 = Vector2.ZERO
		var first_anim: StringName = _find_anim(frames, "idle")
		if first_anim == &"" and frames.get_animation_names().size() > 0:
			first_anim = StringName(frames.get_animation_names()[0])
		if first_anim != &"":
			var ft: Texture2D = frames.get_frame_texture(first_anim, 0)
			if ft != null:
				frame_size = ft.get_size() * anim_sprite.scale
		anim_sprite.position = Vector2(centre_x, top + frame_size.y * 0.5)
		_prop_index += 1
		anim_sprite.centered = true
		# Its own material: a parent's is not inherited.
		anim_sprite.material = theme_color_shader
		props_container.add_child(anim_sprite)

		# The sparrow names these with the character's prefix - "bf idle",
		# "dad idle", "gf idle" - so a lookup for a bare "idle" finds nothing,
		# nothing plays, and the sprite sits on frame 0 of whichever animation
		# came first alphabetically ("... confirm"). That is why the cast was
		# posed wrong against the reference.
		var idle_anim: StringName = _find_anim(frames, "idle")
		if idle_anim != &"":
			anim_sprite.play(idle_anim)
		elif frames.has_animation(&"danceLeft"):
			anim_sprite.play(&"danceLeft")

		_active_props.append(anim_sprite)


func play_confirm_on_props() -> void:
	for prop: AnimatedSprite2D in _active_props:
		if is_instance_valid(prop) and prop.sprite_frames.has_animation(&"confirm"):
			var c: StringName = _find_anim(prop.sprite_frames, "confirm")
			if c != &"":
				prop.play(c)


func dance_props() -> void:
	for prop: AnimatedSprite2D in _active_props:
		if is_instance_valid(prop):
			var i2: StringName = _find_anim(prop.sprite_frames, "idle")
			if i2 != &"":
				prop.play(i2)
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
	# The props are drawn as a tint of the level colour, so the key has to
	# follow it or they stay the colour of whatever level was shown first.
	if theme_color_shader != null:
		theme_color_shader.set_shader_parameter("bg_col",
			Vector3(color.r, color.g, color.b))


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
## MEASURED from StoryMenu_obj::create() at 0x32f370f: right after the blot is
## built and centred, the ARGB literal 0xFF27242A goes into %esi and is passed
## through the vtable colour setter at slot 0x3b0. It does NOT show up as a
## write to the sprite's colour field 0x180, which is why grepping for that
## found nothing.
##
## The art itself is white in the build (sampled: 240,240,240 opaque) and is
## byte-identical to the copy vendored here, so the dark splat in the mod is
## this tint and nothing else.
const BLOT_TINT := Color(39.0 / 255.0, 36.0 / 255.0, 42.0 / 255.0, 1.0)


## Its centre measures (582, 581) in the reference - the same x the titles get,
## and a y that puts the splat under them with its lower half running off the
## bottom edge.
const BLOT_CENTRE_Y := 581.0

func _place_weeks_blot() -> void:
	if weeks_blot != null:
		weeks_blot.position = Vector2(TITLE_CENTRE.x,
			BLOT_CENTRE_Y * FUNKIN_TO_RUBICON)
		weeks_blot.modulate = BLOT_TINT


## MEASURED from StoryMenu_obj::create(). Both boxes are pinned to screen
## EDGES, not to literal coordinates - which is why the binary carries almost
## no numbers for them:
##
##   week-diff-box  x = FlxG.width  - box.width    (0x32f2977..0x32f29bc)
##                  y = FlxG.height - box.height   (0x32f29e2..0x32f2a3b)
##                  zIndex = 20                    (movl $0x14 at 0x32f2a51)
##   tracks-box     y = FlxG.height - box.height   (0x32f30d0..0x32f3119)
##                  x stays at its default 0
##
## So difficulty sits flush in the BOTTOM-RIGHT corner and the tracklist in the
## BOTTOM-LEFT, which is how the reference shot reads. The port had both on the
## right with difficulty near the top.
##
## Flixel anchors a sprite by its top-left and Godot Sprite2D by its centre, so
## each formula gains half the drawn size. Reading the size at runtime rather
## than hardcoding it keeps this correct whatever scale the texture is given.
func _sprite_size(sp: Sprite2D) -> Vector2:
	if sp == null or sp.texture == null:
		return Vector2.ZERO
	return sp.texture.get_size() * sp.scale


## The mod draws these three at NATIVE size against its 1280x720 screen - the
## disassembly shows no setGraphicSize, no updateHitbox and no scale write in
## any of their blocks. This menu renders straight to 1920x1080 with no camera
## zoom to carry the difference, so each one takes the x1.5 to cover the same
## fraction of the screen. That is already the convention here: the level
## titles ship at scale 1.5 in the scene.
func _scale_screen_sprites() -> void:
	for sp: Sprite2D in [week_diff_box, tracks_box, weeks_blot]:
		if sp != null:
			sp.scale = Vector2.ONE * FUNKIN_TO_RUBICON


## The two headers the boxes carry. They are LOCALISED ART, not text: create()
## builds each from "menus/story/" + the localization_folder ("eng") + "/tracks"
## or "/difficulty", which is why the port had nothing there - neither png was
## vendored.
##
## The tracks header offset inside its box IS measured: create() loads 40 and
## 15 and adds them to the box's own x and y fields (0x30 and 0x38) at
## 0x32f316b and 0x32f318f, plus a localisation nudge under the key
## "story_tracks_xoffset" that eng does not use.
##
## The difficulty header carries no arithmetic of its own in create(), so it
## hangs off its box; the inset here is by eye against the reference shot.
const TRACKS_LABEL_OFFSET := Vector2(40.0, 15.0)

## Everything in the difficulty corner, MEASURED off the 1280x720 reference
## rather than hung off the box by eye:
##   DIFFICULTY: header  top-left (856, 511)
##   the value (HARD)    centre   (1068, 653)
##   the two arrows      centres  (956, 656) and (1182, 656)
## The value and its arrows had stayed at their old scene coordinates when the
## box moved to the corner, which left them behind it.
const DIFF_LABEL_POS := Vector2(856.0, 511.0)
const DIFF_VALUE_POS := Vector2(1068.0, 653.0)
const DIFF_ARROW_L_POS := Vector2(956.0, 656.0)
const DIFF_ARROW_R_POS := Vector2(1182.0, 656.0)

## The value is hard.png at 198x72 and the mod draws it 197x71, so it runs at
## scale 1 against 1280x720 and takes the x1.5 here like everything else. It was
## left at 1, which is exactly why it came out a third too small.
##
## The arrows were the wrong art entirely: the scene pointed them at
## storymenu/ui/arrows.png, whose frames are 48x85, while the mod uses the
## diff-selector atlas - "difficulty arrow", 17x33 unrotated, which is the 15x31
## measured in the reference. That atlas is already vendored beside the scene.
const DIFF_SELECTOR_FRAMES := "res://animania_mod/source/images/menus/story/diff_selector_frames.tres"

## The atlas art is white; the mod tints it. Sampled off the reference arrows.
const DIFF_ARROW_TINT := Color(66.0 / 255.0, 201.0 / 255.0, 199.0 / 255.0)


func _fit_difficulty_block() -> void:
	if difficulty_sprite != null:
		difficulty_sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	var f: SpriteFrames = load(DIFF_SELECTOR_FRAMES) as SpriteFrames
	# The atlas holds one arrow; the pair is that art mirrored. The left one is
	# the flipped copy - the reference has it pointing away from the value.
	for entry: Array in [[left_difficulty_arrow, false], [right_difficulty_arrow, true]]:
		var arrow: AnimatedSprite2D = entry[0]
		if arrow == null:
			continue
		if f != null:
			arrow.sprite_frames = f
			if f.has_animation(&"idle"):
				arrow.play(&"idle")
		arrow.flip_h = bool(entry[1])
		arrow.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		arrow.modulate = DIFF_ARROW_TINT

const TRACKS_LABEL := "res://animania_mod/source/images/menus/story/eng/tracks.png"
const DIFF_LABEL := "res://animania_mod/source/images/menus/story/eng/difficulty.png"
## First frame of difficulty.xml: 396x82 at (1,1). The atlas is an animation
## the mod plays at 24fps; a single frame is what reads on a still.
const DIFF_LABEL_FRAME := Rect2(1.0, 1.0, 396.0, 82.0)

var _tracks_label: Sprite2D
var _diff_label: Sprite2D


func _place_labels() -> void:
	var t: Vector2 = _sprite_size(tracks_box)
	if t != Vector2.ZERO and _tracks_label == null:
		var tex: Texture2D = load(TRACKS_LABEL)
		if tex != null:
			_tracks_label = Sprite2D.new()
			_tracks_label.texture = tex
			_tracks_label.centered = false
			_tracks_label.scale = Vector2.ONE * FUNKIN_TO_RUBICON
			_tracks_label.z_index = Z_TRACKS_LABEL
			add_child(_tracks_label)
	if _tracks_label != null and t != Vector2.ZERO:
		_tracks_label.position = Vector2(0.0, SCREEN.y - t.y) \
			+ TRACKS_LABEL_OFFSET * FUNKIN_TO_RUBICON

	var d: Vector2 = _sprite_size(week_diff_box)
	if d != Vector2.ZERO and _diff_label == null:
		var sheet: Texture2D = load(DIFF_LABEL)
		if sheet != null:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = DIFF_LABEL_FRAME
			_diff_label = Sprite2D.new()
			_diff_label.texture = at
			_diff_label.centered = false
			_diff_label.scale = Vector2.ONE * FUNKIN_TO_RUBICON
			_diff_label.z_index = Z_DIFF_LABEL
			add_child(_diff_label)
	if _diff_label != null:
		_diff_label.position = DIFF_LABEL_POS * FUNKIN_TO_RUBICON
	if difficulty_sprite != null:
		difficulty_sprite.position = DIFF_VALUE_POS * FUNKIN_TO_RUBICON
		difficulty_sprite.z_index = Z_DIFF_VALUE
	if left_difficulty_arrow != null:
		left_difficulty_arrow.position = DIFF_ARROW_L_POS * FUNKIN_TO_RUBICON
		left_difficulty_arrow.z_index = Z_DIFF_VALUE
	if right_difficulty_arrow != null:
		right_difficulty_arrow.position = DIFF_ARROW_R_POS * FUNKIN_TO_RUBICON
		right_difficulty_arrow.z_index = Z_DIFF_VALUE


func _place_boxes() -> void:
	_scale_screen_sprites()
	var d: Vector2 = _sprite_size(week_diff_box)
	if week_diff_box != null and d != Vector2.ZERO:
		week_diff_box.position = SCREEN - d * 0.5
		week_diff_box.z_index = Z_BOXES
	var t: Vector2 = _sprite_size(tracks_box)
	if tracks_box != null and t != Vector2.ZERO:
		tracks_box.position = Vector2(t.x * 0.5, SCREEN.y - t.y * 0.5)
	_follow_boxes()
	_place_labels()


## The score line and the level name are NOT attached to the difficulty box:
## create() builds both as FlxText at y=10 (0x32f3846 and 0x32f3a0b), which is
## the top edge, and the reference shot has them in the black bar above the
## band - score on the left, level name on the right. y=10 is a screen
## distance, so x1.5.
##
## The tracklist DOES belong to its box; the mod draws localised art for its
## header rather than text, so the inset here is by eye against the box.
## MEASURED off the 1280x720 reference:
##   LEVEL SCORE  starts at (7, 17), caps 20px tall -> ~28px of VCR
##   tracklist    starts at (8, 511), block 184x131, in (229, 102, 132)
##
## The tracklist's own face is NOT VCR: the mod letters it in the same
## hand-drawn font as the TRACKS header, which this port does not have. VCR is
## nearly twice as wide for the same height, so the size here is set to match
## the BLOCK HEIGHT and the extra width is the font, not a placement error.
## The port drew both as small default-font Labels in white, which is what made
## the corners read wrong however well the boxes lined up.
const TOP_TEXT_POS := Vector2(7.0, 12.0)
const TOP_TEXT_SIZE := 28
## The week name is right-aligned but not flush: in the reference it ends at
## x=1211, so the right margin is 69 where the score's left margin is 7.
const TOP_TEXT_RIGHT_MARGIN := 69.0
const TRACKLIST_POS := Vector2(8.0, 505.0)
const TRACKLIST_SIZE := 52
const TRACKLIST_COLOR := Color(229.0 / 255.0, 102.0 / 255.0, 132.0 / 255.0)
const VCR_FONT := "res://animania_mod/source/fonts/VCR OSD Mono Cyr.ttf"


func _style_label(node: Label, size: int, colour: Color) -> void:
	if node == null:
		return
	var f: Font = load(VCR_FONT) as Font
	if f != null:
		node.add_theme_font_override(&"font", f)
	node.add_theme_font_size_override(&"font_size", int(size * FUNKIN_TO_RUBICON))
	node.add_theme_color_override(&"font_color", colour)


const TOP_TEXT_Y := 10.0

func _follow_boxes() -> void:
	var pos: Vector2 = TOP_TEXT_POS * FUNKIN_TO_RUBICON
	if score_text != null:
		score_text.set_anchors_preset(Control.PRESET_TOP_LEFT)
		score_text.size = Vector2(SCREEN.x * 0.5, 60.0)
		score_text.position = pos
		score_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_label(score_text, TOP_TEXT_SIZE, Color.WHITE)
	if level_title_text != null:
		level_title_text.set_anchors_preset(Control.PRESET_TOP_LEFT)
		level_title_text.size = Vector2(
			SCREEN.x * 0.5 - TOP_TEXT_RIGHT_MARGIN * FUNKIN_TO_RUBICON, 60.0)
		level_title_text.position = Vector2(SCREEN.x * 0.5, pos.y)
		level_title_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_style_label(level_title_text, TOP_TEXT_SIZE, Color.WHITE)
	if tracklist_text != null:
		tracklist_text.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tracklist_text.size = Vector2(SCREEN.x * 0.3, SCREEN.y * 0.4)
		tracklist_text.position = TRACKLIST_POS * FUNKIN_TO_RUBICON
		tracklist_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_label(tracklist_text, TRACKLIST_SIZE, TRACKLIST_COLOR)


## MEASURED: create() writes each element's zIndex into field 0x28, and those
## are the numbers, in construction order:
##
##   14  weeks-blot          20  both boxes        30  titles group
##   16  level background    25  difficulty value  30  difficulty header
##   18  level props         25  the two arrows    1000  the top texts
##                           26  tracks header
##
## The one that changes the picture is the blot at 14, BELOW the background at
## 16: the splat is drawn UNDER the level colour, so all that shows of it is the
## part hanging past the band's lower edge. The port drew it over everything,
## which is why it read as a big grey slab across the middle instead of the
## ink blot the mod shows beneath the band.
##
## The value and the arrows come from buildDifficultySprite (movl $0x19) and
## from create() respectively; the titles carry no zIndex of their own and take
## their group's 30, which is what puts them over the boxes.
const Z_BLOT := 14
## NOT 16. That write at 0x32f27ec goes to some other sprite; assuming it was
## the level background put the blot underneath it, and the reference says
## otherwise in a way that admits no argument: the purple/blot boundary is
## different in every column - 500, 511, 492, 466, 421, 473, 456 - and at x=440
## there is a lone purple droplet INSIDE the blot. A band drawn over the blot
## would cut it with a straight edge at its own bottom, not with a splat
## outline. So the blot (14, and that one IS traced: __alloc -> stack -0x100 ->
## field 0x1c0) sits above the background, and the background carries no zIndex
## of its own.
const Z_BACKGROUND := 0
const Z_PROPS := 18
const Z_BOXES := 20
const Z_DIFF_VALUE := 25
const Z_TRACKS_LABEL := 26
const Z_TITLES := 30
const Z_DIFF_LABEL := 30
const Z_TOP_TEXT := 1000


func _apply_z_order() -> void:
	if weeks_blot != null:
		weeks_blot.z_index = Z_BLOT
	if level_background != null:
		level_background.z_index = Z_BACKGROUND
	if has_node("LevelProps"):
		($LevelProps as Node2D).z_index = Z_PROPS
	for box: Sprite2D in [week_diff_box, tracks_box]:
		if box != null:
			box.z_index = Z_BOXES
	if titles != null:
		titles.z_index = Z_TITLES
	if difficulty_sprite != null:
		difficulty_sprite.z_index = Z_DIFF_VALUE
	for arrow: AnimatedSprite2D in [left_difficulty_arrow, right_difficulty_arrow]:
		if arrow != null:
			arrow.z_index = Z_DIFF_VALUE
	for label: Control in [score_text, level_title_text]:
		if label != null:
			label.z_index = Z_TOP_TEXT
	if tracklist_text != null:
		tracklist_text.z_index = Z_TRACKS_LABEL


## Lays the level colour out as the measured band instead of a full-screen
## fill, centred vertically so what shows above and below it is the black the
## mod letterboxes with.
func _size_level_background() -> void:
	if level_background == null:
		return
	level_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	level_background.size = Vector2(SCREEN.x, BACKGROUND_HEIGHT * FUNKIN_TO_RUBICON)
	level_background.position = Vector2(0.0, BACKGROUND_Y * FUNKIN_TO_RUBICON)


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
