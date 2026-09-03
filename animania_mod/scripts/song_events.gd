extends Node
## Chart events — the actions the chart calls by string name.
##
## These are NOT baked onto value tracks: they fire once from the chart's
## method tracks. The chart calls them as function keys on the level clock,
## AS METHODS ON THIS NODE — so every name the chart uses has to resolve
## here or on a subclass. A method that lives only on AnimaniaModule is
## invisible to the chart and fails at runtime with
## "Error calling deferred method: 'Node::<name>': Method not found."
##
## Generic gameplay (combo, splash, HUD lifecycle, camera nudge, etc.)
## lives in animania_module.gd (autoload). This script owns the chart's
## VOCABULARY and forwards to the module; it does not reimplement it.
##
## Per-song scripts extend this and override _on_beat() or add their own
## chart-event methods.

## ─── Exports ────────────────────────────────────────────────────────────────
## The level scene wires all of these; build_level_scene.gd writes them.
## They live here rather than on the per-song script because every Animania
## level scene has the same furniture, and module.setup() is fed
## from them.
@export var camera: Camera2D
@export var clock: Node
@export var hud: CanvasLayer
@export var bumper: Node
@export var player_point: Node2D
@export var opponent_point: Node2D
@export var player_lanes: Control
@export var opponent_lanes: Control
@export var cast: Dictionary[StringName, Node] = {}
@export var hud_root: Control
@export var hud_up: Array[Node] = []
@export var hud_down: Array[Node] = []

## Overlay rects. `flash_rect` is NOT called `flash`: that name is the chart
## event below, and a property would shadow the method.
@export var flash_rect: ColorRect
@export var fade_rect: ColorRect

## Letterbox bars for the chart's CinematicBars events.
@export var bar_top: CanvasItem
@export var bar_bottom: CanvasItem


## ─── The level's gameplay module ────────────────────────────────────────────
## Created here rather than wired by the builder, so every song scene gets one
## without having to carry it, and so it is freed WITH the level: a death retry
## then starts on a module whose first_time() guards and combo counter are
## empty, the way the first play did.
##
## Built in _init and wired on FIRST ACCESS, not in _ready. Both guards in
## tools/animania/ drive the level from a SceneTree script's _init, where root
## is not yet in the tree: an instantiated level never enters it, so neither
## _enter_tree nor _ready ever fires. Wiring from _ready would leave the module
## holding nulls for everything the guard then calls, and the guard would pass
## on nothing. Reading the exports lazily works either way, because Godot
## applies them right after instantiate() and before any method runs.
##
## The child has no owner, so PackedScene.pack() leaves it out and the builder
## does not bake a second one into the scene.
var _module: AnimaniaModule
var _module_wired: bool = false

var module: AnimaniaModule:
	get:
		if not _module_wired:
			_wire_module()
		return _module


func _init() -> void:
	_module = AnimaniaModule.new()
	_module.name = "AnimaniaModule"
	add_child(_module)


## The stage's resting camera zoom. Per-song scripts override it.
func stage_zoom() -> float:
	return 0.65


## Hands the module everything the scene wired onto this node. Uses _module
## directly: going through `module` here would recurse forever.
func _wire_module() -> void:
	_module_wired = true
	_module.setup(camera, hud, player_lanes, opponent_lanes, stage_zoom())
	_module.cast = cast
	_module.hud_root = hud_root
	_module.hud_up = hud_up
	_module.hud_down = hud_down
	_module.player_point = player_point
	_module.opponent_point = opponent_point


## death_sequence.gd stops the beat choreography through here rather than
## reaching into the module itself.
func set_dying(value: bool) -> void:
	module.dying = value


## ─── Chart event: FocusCamera ───────────────────────────────────────────────
## Instant camera aim. The chart writes the target as a baked value track
## and this fires the snap from the chart's method track.
func focus_camera(target: Vector2) -> void:
	if camera == null:
		return
	camera.position_interpolate_target = target
	camera.global_position = target


## ─── Chart event: snap_camera ───────────────────────────────────────────────
## What the baked charts actually name FocusCamera. Kept as its own entry
## point because phone-call's method track calls it by this name.
func snap_camera(target: Vector2) -> void:
	module.snap_camera(target)


## ─── Chart event: Shake ─────────────────────────────────────────────────────
## intensity is a fraction of screen width (Flixel convention).
## duration is in seconds.
func shake(intensity: float, duration: float) -> void:
	module.shake_screen(intensity, duration)


## ─── Chart event: punch / AddCameraZoom ─────────────────────────────────────
## One-shot zoom punch on the game camera, and optionally the HUD.
func punch(game_zoom: float, hud_zoom: float = 0.0) -> void:
	module.punch(game_zoom, hud_zoom)


func add_camera_zoom(amount: float) -> void:
	module.punch(amount)


## ─── Chart event: SetCameraBop ──────────────────────────────────────────────
## Changes the bumper's automatic beat-bop rate and strength.
## rate is in beats (e.g. 4 = every 4 beats). intensity is a multiplier.
## intensity=0 disables the bop.
##
## The chart calls this with two arguments — the bumper is the scene's, not
## the chart's — so the exported `bumper` supplies it.
func set_bop(rate: int, intensity: float) -> void:
	module.set_bop(bumper, rate, intensity)


func set_camera_bop(bump_node: Node, rate: int, intensity: float) -> void:
	module.set_bop(bump_node, rate, intensity)


## ─── Chart event: PlayAnimation ─────────────────────────────────────────────
## Makes a character play an animation the note chart would not.
## force=false means "play but don't restart if already running."
func play_character_animation(target: StringName, animation: StringName,
		force: bool = false) -> void:
	module.play_character_animation(target, animation, force)


func play_animation(target: StringName, animation: StringName,
		force: bool = false) -> void:
	module.play_character_animation(target, animation, force)


## ─── Chart event: SetProperty ───────────────────────────────────────────────
## Sets a property on a character. Most commonly:
##   SetProperty boyfriend.idleSuffix "-alt"
## which swaps the idle pose set for the rest of the song. The baked charts
## call set_idle_suffix directly; set_property is the generic entry point.
func set_idle_suffix(target: StringName, suffix: String) -> void:
	module.set_idle_suffix(target, suffix)


func set_property(target: StringName, property: String,
		value: Variant) -> void:
	if property == "idleSuffix":
		module.set_idle_suffix(target, str(value))
	else:
		push_warning("SetProperty: unknown property '%s'" % property)


## ─── Chart event: CinematicBars ─────────────────────────────────────────────
func show_cinematic_bars(height: float = 100.0, duration: float = 0.3) -> void:
	module.show_bars(bar_top, bar_bottom, height, duration)


func hide_cinematic_bars(duration: float = 0.3) -> void:
	module.hide_bars(bar_top, bar_bottom, duration)


## ─── Chart event: Flash ─────────────────────────────────────────────────────
## White or black screen flash. Duration in seconds.
func flash(color: Color = Color.WHITE, duration: float = 1.5) -> void:
	module.flash_screen(flash_rect, color, duration)


## ─── Chart event: Fade ──────────────────────────────────────────────────────
## Screen fade to black.
func fade_out(duration: float = 3.0) -> void:
	module.fade_out_node(fade_rect, duration)


## ─── Per-song beat override ─────────────────────────────────────────────────
## Override in subclass for per-song beat choreography.
func _on_beat() -> void:
	pass
