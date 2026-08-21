class_name LullabyLoadingScreen extends Node

@export var animation_start: StringName
@export var animation_end: StringName
@export var animation_player: AnimationPlayer

signal progress_updated(value: float)

## Shown only while the driver's shader cache is cold for this build.
##
## The first launch after installing is not slightly slower, it is a different
## experience. Two logs from the same Redmi on 10154-8d1ee1ac, same build:
##
##     arranque 1   tienda: 52014ms de carga + 30089ms de precache = 82s
##     arranque 2   tienda:  5998ms de carga +  1270ms de precache =  7s
##
## `bench` is comparable across both windows, so it is not the governor, and
## the pipeline count is the same in both (233 against 243) - it is the driver
## compiling shaders it has never seen and then keeping them. A minute and a
## half of loading screen with no explanation reads as a hang, and the log has
## a player pressing Back nine times on a screen that was simply busy.
##
## Built here rather than in the two loading .tscn files so both get it from
## one place, and only when it is actually needed - a warm session allocates
## nothing.
const NOTICE_TEXT := "First run - preparing shaders.\nThis only happens once."
const NOTICE_FONT := "res://lullaby_mod/resources/fonts/fnt_pokemon_bw.otf"

var _notice: Label = null

func start() -> void :
	_show_notice_if_cold()

	animation_player.play(animation_start)
	animation_player.seek(0.0)

	await animation_player.animation_finished

func update_progress(value: float) -> void :
	progress_updated.emit(value)

func complete() -> void :
	animation_player.play(animation_end)
	animation_player.seek(0.0)

	await animation_player.animation_finished

## Adds the notice as a child of this node, centred above the progress bar.
##
## The host is `self`, not get_parent(): this script sits on the loading
## screen's ROOT, which is a full-rect ColorRect in both load_hypno.tscn and
## load_default.tscn. Attached with add_child() and laid out with anchors, so
## nothing here needs to cast `self` to Control - which is the shape that
## silently killed lullaby_fps_display.gd (a script declaring `extends Node`
## on a CanvasLayer, casting to its real type, and failing to parse on device
## while GDRE compiled it happily).
##
## Defensive about the rest: Settings may not carry the flag on a save written
## before it landed, and the font may be missing. Neither should cost a
## loading screen.
func _show_notice_if_cold() -> void :
	if _notice != null:
		return
	if not is_instance_valid(Settings) or not ("shader_cache_cold" in Settings):
		return
	if not Settings.shader_cache_cold:
		return

	build_notice()

## The half that does not read Settings, so a gate can exercise it.
##
## Split for exactly that: every CI check in this project runs through
## `--script`, which does not give you the autoloads (see CLAUDE.md), so a
## test that had to go through Settings could not run at all. Idempotent -
## start() can be called more than once in a session.
func build_notice() -> void :
	if _notice != null:
		return

	_notice = Label.new()
	_notice.name = "FirstRunNotice"
	_notice.text = NOTICE_TEXT
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Above the progress bar, which sits in the bottom 25 pixels.
	_notice.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_bottom = -48.0
	_notice.offset_left = -420.0
	_notice.offset_right = 420.0
	# Never eats a touch: the loading screen is not interactive and a stray
	# Control that does would be a new way to swallow input.
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var font: Font = load(NOTICE_FONT) if ResourceLoader.exists(NOTICE_FONT) else null
	if font != null:
		_notice.add_theme_font_override("font", font)
	_notice.add_theme_font_size_override("font_size", 28)
	_notice.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))

	add_child(_notice)
