# Authors chr_komi.tscn and chr_tadano.tscn from the data Animania ships.
#
# Building these by packing a live tree rather than by writing .tscn text means the
# uids, the typed dictionaries rubicon_character.gd exports and the sub-resource ids
# all come out of the engine instead of out of a template, which is the half of a
# hand-written scene that goes wrong silently.
#
# Two conventions this fixes in one place, both taken from the mod's own data:
#
#   * Animania is a Funkin (V-Slice) mod, so its coordinates are 1280x720 and this
#     project's are 1920x1080. Positions and scales are carried over VERBATIM and the
#     1.5x lives on the level camera instead -- that keeps every number here diffable
#     against phoneCallStreet.json and komi/tadano.json, and avoids resampling the art.
#   * Funkin applies a per-animation offset as `offset.set(-x, -y)`, so the offsets in
#     the character JSON are negated here. Getting that sign backwards is invisible on
#     idle (0, 0) and doubles the error on everything else.
#   * Stage.addCharacter anchors a character by `characterOrigin`, which is
#     (width / 2, height) - horizontal centre, vertical BOTTOM. A stage position is where
#     the feet go, not where the corner goes. That anchor is baked into the sprite's
#     `position` here so a character node's own origin already means what the stage JSON
#     means, and placing one is just `marker.position + json offsets`. Skipping this puts
#     komi three quarters of her own height below the pavement, which is exactly what the
#     first render of this port showed.
extends SceneTree

const CHARACTER_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_character.gd"
const OUT_DIR := "res://animania_mod/characters"

# 24fps in both atlases; the loop point is loopHoldFrame frames in.
const FPS := 24.0

# Funkin's characterOrigin. komi's is the sparrow frame size of idle0000 (307x776 in
# komi.xml); tadano is an Animate atlas with no authored size, so its drawn bounds were
# measured by rendering it - see tools/animania/harness/measure_character.gd. Re-measure
# rather than adjust by eye if either character's art changes.
const KOMI_FRAME := Vector2(307.0, 776.0)
const TADANO_DRAWN_ORIGIN := Vector2(-211.5, 855.0)


func _init() -> void:
	_build_komi()
	_build_tadano()
	quit(0)


# komi.json: sparrow, danceEvery 1, singTime 8, loopHoldFrame 2, offsets [200, 50].
# It ships no miss animations at all, so miss_* map onto the sing animations - which is
# what Funkin does anyway when `<anim>miss` is absent from the atlas.
func _build_komi() -> void:
	var offsets: Dictionary = {
		&"dance_idle": Vector2(0, 0),
		&"sing_left": Vector2(5, 2),
		&"sing_down": Vector2(-4, -5),
		&"sing_up": Vector2(-3, 10),
		&"sing_right": Vector2(-8, -2),
		&"breath": Vector2(-6, -4),
		&"reaction": Vector2(-3, 17),
	}
	var clips: Dictionary = {
		&"dance_idle": &"komi_idle",
		&"sing_left": &"komi_left",
		&"sing_down": &"komi_down",
		&"sing_up": &"komi_up",
		&"sing_right": &"komi_right",
		&"breath": &"komi_breath",
		&"reaction": &"komi_reaction",
	}

	var root := Node2D.new()
	root.name = "komi"
	root.set_script(load(CHARACTER_SCRIPT))

	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = load("%s/komi_frames.tres" % OUT_DIR)
	sprite.animation = &"idle"
	sprite.centered = false
	sprite.position = Vector2(-KOMI_FRAME.x * 0.5, -KOMI_FRAME.y)
	root.add_child(sprite)
	sprite.owner = root

	var sprite_player := AnimationPlayer.new()
	sprite_player.name = "AnimationPlayer"
	sprite_player.add_animation_library(&"", load("%s/komi_library.tres" % OUT_DIR))
	sprite.add_child(sprite_player)
	sprite_player.owner = root

	var root_player := AnimationPlayer.new()
	root_player.name = "RootAnimationPlayer"
	root_player.add_animation_library(&"", _root_library(
		clips, offsets, ^"AnimatedSprite2D/AnimationPlayer", ^"AnimatedSprite2D:offset",
		load("%s/komi_library.tres" % OUT_DIR)))
	root_player.autoplay = &"dance_idle"
	root.add_child(root_player)
	root_player.owner = root

	root.animation_player = root_player
	root.animations = _sing_and_miss_map(true)
	root.mania_anim_groups = _anim_groups()
	root.dancing_animations = [&"dance_idle"] as Array[StringName]
	root.dancing_measure_step = 0.25          # danceEvery 1 beat: 4 / (4 * 4)
	root.singing_sing_to_dance_interval = 8   # singTime
	root.singing_repeat_loop_point = 2.0 / FPS  # loopHoldFrame
	root.transition_update_queued_animations = false

	_save(root, "%s/chr_komi.tscn" % OUT_DIR)


# tadano.json: multianimateatlas, singTime 6, loopHoldFrame 2, offsets [250, 180],
# flipX true. Its animation list carries no per-animation offsets at all - unlike komi -
# so every root animation keys the sprite offset back to zero and nothing else.
func _build_tadano() -> void:
	var names: PackedStringArray = [
		"dance_idle", "idle_alt",
		"sing_left", "sing_down", "sing_up", "sing_right",
		"sing_left_alt", "sing_down_alt", "sing_up_alt", "sing_right_alt",
		"miss_left", "miss_down", "miss_up", "miss_right",
		"miss_left_alt", "miss_down_alt", "miss_up_alt", "miss_right_alt",
		"intro", "death_start", "death_loop",
	]
	var clips: Dictionary = {}
	var offsets: Dictionary = {}
	for anim_name: String in names:
		# dance_idle is what Rubicon dances; the clip behind it is tadano_idle.
		var clip: String = "tadano_idle" if anim_name == "dance_idle" \
			else "tadano_%s" % anim_name
		clips[StringName(anim_name)] = StringName(clip)
		offsets[StringName(anim_name)] = Vector2.ZERO

	var root := Node2D.new()
	root.name = "tadano"
	root.set_script(load(CHARACTER_SCRIPT))

	var symbol := AnimateSymbol.new()
	symbol.name = "AnimateSymbol"
	symbol.atlases = [load("%s/tadano_atlas.tres" % OUT_DIR)] as Array[AnimateAtlas]
	symbol.atlas_index = 0
	symbol.symbol = "chars render/tadano 1/tadano idle"
	symbol.centered = false
	symbol.position = -TADANO_DRAWN_ORIGIN
	# flipX in the character data. Mirroring the node rather than the art keeps the
	# atlas untouched and the symbol names comparable against Animation.json.
	symbol.scale = Vector2(-1.0, 1.0)
	root.add_child(symbol)
	symbol.owner = root

	var symbol_player := AnimationPlayer.new()
	symbol_player.name = "AnimationPlayer"
	symbol_player.add_animation_library(&"", load("%s/tadano_library.tres" % OUT_DIR))
	symbol.add_child(symbol_player)
	symbol_player.owner = root

	var root_player := AnimationPlayer.new()
	root_player.name = "RootAnimationPlayer"
	root_player.add_animation_library(&"", _root_library(
		clips, offsets, ^"AnimateSymbol/AnimationPlayer", ^"AnimateSymbol:offset",
		load("%s/tadano_library.tres" % OUT_DIR)))
	root_player.autoplay = &"dance_idle"
	root.add_child(root_player)
	root_player.owner = root

	root.animation_player = root_player
	root.animations = _sing_and_miss_map(false)
	root.mania_anim_groups = _anim_groups()
	root.dancing_animations = [&"dance_idle"] as Array[StringName]
	root.dancing_measure_step = 0.25
	root.singing_sing_to_dance_interval = 6
	root.singing_repeat_loop_point = 2.0 / FPS
	# gdanimate sprites need the queued animation refreshed the same frame or the first
	# drawn frame is the previous symbol's - the export's own documentation says so.
	root.transition_update_queued_animations = true

	_save(root, "%s/chr_tadano.tscn" % OUT_DIR)


func _anim_groups() -> Dictionary:
	var groups: Dictionary[StringName, int] = {&"sing": 4, &"miss": 4}
	return groups


func _sing_and_miss_map(miss_falls_back_to_sing: bool) -> Dictionary:
	var map: Dictionary[StringName, StringName] = {}
	for direction: String in ["left", "down", "up", "right"]:
		map[StringName("sing_%s" % direction)] = StringName("sing_%s" % direction)
		map[StringName("miss_%s" % direction)] = StringName(
			"sing_%s" % direction if miss_falls_back_to_sing else "miss_%s" % direction)
	return map


# One root animation per entry: an animation track dispatching the clip on the child
# player, and a value track pinning the sprite offset. Same shape as bf.tscn.
func _root_library(clips: Dictionary, offsets: Dictionary, player_path: NodePath,
		offset_path: NodePath, source: AnimationLibrary) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.001

	var reset_offset: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_offset, offset_path)
	reset.value_track_set_update_mode(reset_offset, Animation.UPDATE_DISCRETE)
	reset.track_insert_key(reset_offset, 0.0, Vector2.ZERO)

	for anim_name: StringName in clips:
		var clip: StringName = clips[anim_name]
		var clip_animation: Animation = source.get_animation(clip)
		if clip_animation == null:
			push_error("no clip %s in the source library" % clip)
			quit(1)
			return library

		var animation := Animation.new()
		animation.length = clip_animation.length
		animation.step = clip_animation.step

		var clip_track: int = animation.add_track(Animation.TYPE_ANIMATION)
		animation.track_set_path(clip_track, player_path)
		animation.track_insert_key(clip_track, 0.0, clip)

		var offset_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(offset_track, offset_path)
		animation.value_track_set_update_mode(offset_track, Animation.UPDATE_DISCRETE)
		# Funkin negates the authored offset when it applies it.
		animation.track_insert_key(offset_track, 0.0, -(offsets[anim_name] as Vector2))

		library.add_animation(anim_name, animation)

	library.add_animation(&"RESET", reset)
	return library


func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("could not pack %s (%d)" % [path, err])
		quit(1)
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		quit(1)
		return
	print("OUT saved %s (%d root animations)" % [path, root.get_node("RootAnimationPlayer").get_animation_list().size()])
