extends Control
## HQ Game Over (Meguca) — meguca song's special gameover with gf-meguca's
## deathLoop -> deathEnd sequence. Ports the mod's HQGameoverMeguca. The gf
## character is built at runtime from the mod's GEEF sparrow atlas so no
## offline codegen is needed.

const GEEF_PNG := "res://holyquintet_mod/source/images/characters/meguca/GEEF.png"
const GEEF_XML := "res://holyquintet_mod/source/images/characters/meguca/GEEF.xml"

var can_control: bool = false
var _confirming: bool = false
var _char: Node2D
var _sym: Node
var _anim: AnimationPlayer
var _fading: bool = false

@onready var fade_rect: ColorRect = $FadeRect
@onready var prompt_label: Label = $PromptLabel
@onready var inst_player: AudioStreamPlayer = $InstPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fade_rect.modulate.a = 1.0
	_build_gf_meguca()
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): can_control = true)
	_play_inst()

func _build_gf_meguca() -> void:
	var sparrow_script: GDScript = load("res://addons/gdanimate/sparrow/sparrow_atlas.gd")
	var sym_script: GDScript = load("res://addons/gdanimate/animate_symbol.gd")
	var sparrow = sparrow_script.new()
	sparrow.texture = load(GEEF_PNG)
	sparrow.sparrow_path = GEEF_XML
	sparrow.parse()

	_char = Node2D.new()
	_char.name = "GFMeguca"
	_char.position = Vector2(1025, 200)
	_char.scale = Vector2(1.5, 1.5)
	_sym = sym_script.new()
	_sym.symbol = &"megucagf_dead loop"
	_sym.centered = false
	_sym.playing = true
	_sym.loop = true
	_sym.atlases = [sparrow]
	_char.add_child(_sym)

	_anim = AnimationPlayer.new()
	_anim.name = "DeathAnim"
	# The player lives under the symbol so ".:frame" / ".:symbol" target it.
	_sym.add_child(_anim)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"death_loop", _make_clip(_sym, "megucagf_dead loop", true))
	lib.add_animation(&"death_end", _make_clip(_sym, "megucagf_Dead confirm", false))
	_anim.add_animation_library("", lib)
	_anim.play(&"death_loop")
	add_child(_char)

func _make_clip(sym: Node, prefix: String, loop: bool) -> Animation:
	var atlas = sym.atlases[0]
	var count: int = atlas.get_count_filtered(prefix)
	var clip := Animation.new()
	clip.step = 1.0 / 24.0
	clip.length = maxf(float(count) / 24.0, clip.step)
	if loop:
		clip.loop_mode = Animation.LOOP_LINEAR
	var sym_track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(sym_track, NodePath(".:symbol"))
	clip.value_track_set_update_mode(sym_track, Animation.UPDATE_DISCRETE)
	clip.track_set_interpolation_type(sym_track, Animation.INTERPOLATION_NEAREST)
	clip.track_insert_key(sym_track, 0.0, prefix)
	var fr_track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(fr_track, NodePath(".:frame"))
	clip.value_track_set_update_mode(fr_track, Animation.UPDATE_DISCRETE)
	clip.track_set_interpolation_type(fr_track, Animation.INTERPOLATION_NEAREST)
	for f in count:
		clip.track_insert_key(fr_track, float(f) / 24.0, f)
	return clip

func _play_inst() -> void:
	var p := "res://songs/meguca/Inst.ogg"
	if ResourceLoader.exists(p):
		inst_player.stream = load(p)
		inst_player.volume_db = -14.0
		inst_player.play()

func _process(_delta: float) -> void:
	if _confirming or not can_control:
		return
	if Input.is_action_just_pressed("ui_accept"):
		_retry()
	elif Input.is_action_just_pressed("ui_cancel"):
		_quit()

func _retry() -> void:
	_confirming = true
	can_control = false
	if _anim != null:
		_anim.play(&"death_end")
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(fade_rect, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		HQSaves.death_counter += 1
		get_tree().reload_current_scene()
	)

func _quit() -> void:
	_confirming = true
	can_control = false
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn"))
