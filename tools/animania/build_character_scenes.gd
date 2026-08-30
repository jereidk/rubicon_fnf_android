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

# Funkin's characterOrigin, which is (width / 2, height) of the sprite's FRAME - not of
# the art drawn inside it. For komi the two are the same thing: her sparrow frame is
# 307x776 (idle0000 in komi.xml) and measure_character.gd renders 305x769 sitting centred
# on the frame's bottom, so anchoring by the drawn bounds anchors by the frame.
#
# tadano is an Animate atlas and they are NOT the same thing. gdanimate draws him out of a
# symbol tree with no authored frame, so this used his drawn bounds - and Funkin's frame
# turns out to be far bigger than his art, with the art low and to the left inside it.
# Using the drawn bounds put him 755px right and 21px low, which a capture of the original
# at 9.2s measures directly: with the camera on its (corrected) mark the stage lines up to
# a pixel and tadano did not. Both numbers below are that measurement.
#
# TADANO_ORIGIN is the frame's bottom-centre expressed in the symbol's own space, so
# `symbol.position = -TADANO_ORIGIN` puts the character node's origin there.
# TADANO_FRAME_HEIGHT is the same frame's height, and the camera needs it: Funkin aims at
# the frame's MIDPOINT, so an 833 there aimed 150px below where the original aims.
const KOMI_FRAME := Vector2(307.0, 776.0)
const TADANO_ORIGIN := Vector2(543.5, 876.0)
const TADANO_FRAME_HEIGHT := 1133.0


func _init() -> void:
	_build_komi()
	_build_tadano()
	_build_stand_characters()
	_build_week1_characters()
	quit(0)


## bf and gf, which four of story mode's seven songs need. Both are Adobe atlases; their
## symbol names are in the atlas's own Animation.json and are NOT the `prefix` their
## character JSON gives - gf's JSON says `idle` where the atlas says
## "EVERYTHING/GF/anims/GF DANCE LEFT".
##
## The origins are MEASURED, with tools/animania/harness/measure_character.gd - an Adobe
## atlas has no authored size, so the only way to know where a character's feet are is to
## render it and count opaque pixels. Guessed first and both floated above the stage and
## overlapped each other; the harness reported the drift and these are those numbers folded
## in. `singTime` is the character JSON's: bf 8, gf 6.1 rounded to 6.
func _build_week1_characters() -> void:
	_build_adobe_character("bf", Vector2(155.0, 343.0), "render/BF IDLE", [
		"dance_idle", "sing_left", "sing_down", "sing_up", "sing_right",
		"miss_left", "miss_down", "miss_up", "miss_right", "hey",
	], 8, false)

	# dad. Origin measured like the other two - see the note above.
	_build_adobe_character("dad", Vector2(200.0, 775.0), "EVERYTHING/RENDER/anims/Idle", [
		"dance_idle", "sing_left", "sing_down", "sing_up", "sing_right",
	], 8, true)

	# gf has no miss art at all - she never misses - so miss_* fall back to the sing
	# animations, which is what Funkin does when `<anim>miss` is absent.
	_build_adobe_character("gf", Vector2(184.5, 436.0), "EVERYTHING/GF/anims/GF DANCE LEFT",
		[
			"dance_left", "dance_right", "sing_left", "sing_down", "sing_up", "sing_right",
			"cheer", "sob",
		], 6, true)


# The two characters phone-call.script's standUP() swaps in at beat 232 - 91.6s at 152bpm,
# which is where the song stops being a phone call and the two of them are finally standing
# in front of each other. Both are multisparrow like komi, so the shape is hers; only the
# animation tables and the frame sizes differ, and both come straight out of the character
# JSONs and the atlas XML.
func _build_stand_characters() -> void:
	_build_sparrow_character("komi_stand", Vector2(269.0, 670.0), false, 8, {
		&"dance_idle": [&"komi_stand_idle", Vector2(0, 0)],
		&"sing_left": [&"komi_stand_left", Vector2(4, -2)],
		&"sing_down": [&"komi_stand_down", Vector2(3, -11)],
		&"sing_up": [&"komi_stand_up", Vector2(-5, 14)],
		&"sing_right": [&"komi_stand_right", Vector2(-2, -4)],
		# The chart's PlayAnimation at 132.2s, and the reason this character exists.
		&"end_conv": [&"komi_stand_endkun", Vector2(-1, 2)],
		&"game_over": [&"komi_stand_komigameover", Vector2(-1, 0)],
		# komi-stand.json declares gameOver AND gameOver-loop, the second one
		# `frameIndices: [6, 7, 8, 9, 10]` of the same prefix with `looped: true`. Funkin
		# hands over to `<name>-loop` when `<name>` finishes, and death_sequence.gd already
		# looks for it - it just was not being built, so komi froze on her last frame.
		&"game_over_loop": [&"komi_stand_komigameover", Vector2(-1, 0), Vector2i(6, 10)],
	}, true)

	# NOT mirrored. tadano-stand's art already faces komi, who stands to his right, and this
	# port had it flipped - the same mistake the phone tadano had, and settled the same way:
	# a capture of the mod has his hair sweeping right and the star at his upper right, and
	# he is pointing at her. Observation over the flag.
	_build_sparrow_character("tadano_stand", Vector2(290.0, 667.0), false, 8, {
		&"dance_idle": [&"tadano_stand_idle", Vector2(0, 0)],
		&"sing_left": [&"tadano_stand_left", Vector2(49, -4)],
		&"sing_down": [&"tadano_stand_down", Vector2(10, -18)],
		&"sing_up": [&"tadano_stand_up", Vector2(12, 15)],
		&"sing_right": [&"tadano_stand_right", Vector2(-10, -1)],
		&"miss_left": [&"tadano_stand_missleft", Vector2(49, -4)],
		&"miss_down": [&"tadano_stand_missdown", Vector2(10, -18)],
		&"miss_up": [&"tadano_stand_missup", Vector2(12, 15)],
		&"miss_right": [&"tadano_stand_missright", Vector2(-10, -1)],
		&"end_animation": [&"tadano_stand_end", Vector2(3, 2)],
		&"first_death": [&"tadano_stand_tadanodeath", Vector2(0, 0)],
	}, false)


## `frame` is the sparrow frame size of idle0000, which is Funkin's characterOrigin - see
## the note at the top of this file. `miss_falls_back` is for a character with no miss art.
func _build_sparrow_character(basename: String, frame: Vector2, flip: bool,
		sing_time: int, table: Dictionary, miss_falls_back: bool) -> void:
	var sprite_frames: SpriteFrames = load("%s/%s_frames.tres" % [OUT_DIR, basename])
	var sprite_library: AnimationLibrary = load(
		"%s/%s_library.tres" % [OUT_DIR, basename])

	var clips: Dictionary = {}
	var offsets: Dictionary = {}
	var looping: Dictionary = {}
	for anim_name: StringName in table:
		var entry: Array = table[anim_name] as Array
		var clip: StringName = entry[0]
		offsets[anim_name] = entry[1]
		# A third element is a frame WINDOW of the clip, which is what a character JSON's
		# `frameIndices` is. It becomes an animation of its own in the sprite library, and
		# it loops - a window is only ever declared here for a `-loop`.
		if entry.size() > 2:
			clip = _window(sprite_frames, sprite_library, basename, clip,
				entry[2] as Vector2i)
			looping[anim_name] = true
		clips[anim_name] = clip
	if not looping.is_empty():
		ResourceSaver.save(sprite_library, "%s/%s_library.tres" % [OUT_DIR, basename])

	var root := Node2D.new()
	root.name = basename
	root.set_script(load(CHARACTER_SCRIPT))

	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = sprite_frames
	sprite.animation = &"idle"
	sprite.centered = false
	sprite.position = Vector2(-frame.x * 0.5, -frame.y)
	if flip:
		sprite.scale = Vector2(-1.0, 1.0)
		sprite.position.x = frame.x * 0.5
	root.add_child(sprite)
	sprite.owner = root

	var sprite_player := AnimationPlayer.new()
	sprite_player.name = "AnimationPlayer"
	sprite_player.add_animation_library(&"", sprite_library)
	sprite.add_child(sprite_player)
	sprite_player.owner = root

	var root_player := AnimationPlayer.new()
	root_player.name = "RootAnimationPlayer"
	root_player.add_animation_library(&"", _root_library(
		clips, offsets, ^"AnimatedSprite2D/AnimationPlayer", ^"AnimatedSprite2D:offset",
		sprite_library, looping))
	root_player.autoplay = &"dance_idle"
	root.add_child(root_player)
	root_player.owner = root

	root.animation_player = root_player
	root.animations = _sing_and_miss_map(miss_falls_back)
	root.mania_anim_groups = _anim_groups()
	root.dancing_animations = [&"dance_idle"] as Array[StringName]
	# loopHold in every one of these characters' JSONs. Rubicon re-triggers the dance
	# animation on every dance step whatever it is doing, so a bop that is longer than a beat
	# gets cut off and restarted and the idle reads as a twitch. With this off it plays out
	# and then waits for the next step, which is the hold the flag asks for.
	root.dancing_force_dance = false
	root.dancing_measure_step = 0.25
	root.singing_sing_to_dance_interval = sing_time
	root.singing_repeat_loop_point = 2.0 / FPS

	_save(root, "%s/chr_%s.tscn" % [OUT_DIR, basename])


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
	# loopHold in every one of these characters' JSONs. Rubicon re-triggers the dance
	# animation on every dance step whatever it is doing, so a bop that is longer than a beat
	# gets cut off and restarted and the idle reads as a twitch. With this off it plays out
	# and then waits for the next step, which is the hold the flag asks for.
	root.dancing_force_dance = false
	root.dancing_measure_step = 0.25          # danceEvery 1 beat: 4 / (4 * 4)
	root.singing_sing_to_dance_interval = 8   # singTime
	root.singing_repeat_loop_point = 2.0 / FPS  # loopHoldFrame
	root.transition_update_queued_animations = false

	_save(root, "%s/chr_komi.tscn" % OUT_DIR)


# tadano.json: multianimateatlas, singTime 6, loopHoldFrame 2, offsets [250, 180],
# flipX true. Its animation list carries no per-animation offsets at all - unlike komi -
# so every root animation keys the sprite offset back to zero and nothing else.
func _build_tadano() -> void:
	# dance_idle_alt rather than idle_alt: the chart's SetProperty boyfriend.idleSuffix
	# switch remaps every animation by appending the suffix, so the alt of dance_idle has
	# to be named that way for the same rule to reach it.
	var names: PackedStringArray = [
		"dance_idle", "dance_idle_alt",
		"sing_left", "sing_down", "sing_up", "sing_right",
		"sing_left_alt", "sing_down_alt", "sing_up_alt", "sing_right_alt",
		"miss_left", "miss_down", "miss_up", "miss_right",
		"miss_left_alt", "miss_down_alt", "miss_up_alt", "miss_right_alt",
		# firstDeath / deathLoop in tadano.json, named the way tadano-stand's are so the
		# death sequence can ask for one name and reach either form.
		"intro", "first_death", "death_loop",
	]
	var clips: Dictionary = {}
	var offsets: Dictionary = {}
	for anim_name: String in names:
		# dance_idle is what Rubicon dances; the clip behind it is tadano_idle.
		var clip: String = "tadano_idle" if anim_name == "dance_idle" \
			else ("tadano_idle_alt" if anim_name == "dance_idle_alt"
				else ("tadano_death_start" if anim_name == "first_death"
					else "tadano_%s" % anim_name))
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
	symbol.position = -TADANO_ORIGIN
	# tadano.json declares flipX and this port applied it, which left him facing AWAY from
	# komi - she stands to his right and he was looking right. Observation wins over the
	# flag, the same way it did for the strumline sides: he faces her.
	#
	# Mirroring the node rather than the art keeps the atlas untouched and the symbol names
	# comparable against Animation.json.
	symbol.scale = Vector2(1.0, 1.0)
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
	# loopHold in every one of these characters' JSONs. Rubicon re-triggers the dance
	# animation on every dance step whatever it is doing, so a bop that is longer than a beat
	# gets cut off and restarted and the idle reads as a twitch. With this off it plays out
	# and then waits for the next step, which is the hold the flag asks for.
	root.dancing_force_dance = false
	root.dancing_measure_step = 0.25
	root.singing_sing_to_dance_interval = 6
	root.singing_repeat_loop_point = 2.0 / FPS
	# gdanimate sprites need the queued animation refreshed the same frame or the first
	# drawn frame is the previous symbol's - the export's own documentation says so.
	root.transition_update_queued_animations = true

	_save(root, "%s/chr_tadano.tscn" % OUT_DIR)


## An Adobe character's scene, from its already-built atlas and library. The same shape
## _build_tadano lays out by hand - he keeps his own builder because of the idleSuffix
## remapping and the two death forms - but driven by a table so bf, gf and whatever comes
## next are a list of names rather than a copied function.
##
## `origin` is Funkin's characterOrigin: horizontal centre, vertical BOTTOM. `names` maps
## the Rubicon animation to the clip in the library, which build_adobe_character.gd already
## named after the character.
func _build_adobe_character(basename: String, origin: Vector2, symbol: String,
		names: PackedStringArray, sing_time: int, miss_falls_back: bool) -> void:
	var clips: Dictionary = {}
	var offsets: Dictionary = {}
	var library: AnimationLibrary = load("%s/%s_library.tres" % [OUT_DIR, basename])
	for anim_name: String in names:
		var clip := StringName("%s_%s" % [basename, anim_name])
		if not library.has_animation(clip):
			push_error("%s has no clip %s" % [basename, clip])
			quit(1)
			return
		clips[StringName(anim_name)] = clip
		offsets[StringName(anim_name)] = Vector2.ZERO

	var root := Node2D.new()
	root.name = basename
	root.set_script(load(CHARACTER_SCRIPT))

	var sprite := AnimateSymbol.new()
	sprite.name = "AnimateSymbol"
	sprite.atlases = [load("%s/%s_atlas.tres" % [OUT_DIR, basename])] as Array[AnimateAtlas]
	sprite.atlas_index = 0
	sprite.symbol = symbol
	sprite.centered = false
	sprite.position = -origin
	root.add_child(sprite)
	sprite.owner = root

	var sprite_player := AnimationPlayer.new()
	sprite_player.name = "AnimationPlayer"
	sprite_player.add_animation_library(&"", library)
	sprite.add_child(sprite_player)
	sprite_player.owner = root

	# The dance is danceLeft/danceRight when the character has them and dance_idle when it
	# does not - gf alternates, bf holds one idle - and Rubicon takes the list either way.
	var dancing: Array[StringName] = []
	for candidate: String in ["dance_left", "dance_right", "dance_idle"]:
		if clips.has(StringName(candidate)):
			dancing.append(StringName(candidate))
	if dancing.size() > 1:
		dancing.erase(&"dance_idle")

	var root_player := AnimationPlayer.new()
	root_player.name = "RootAnimationPlayer"
	root_player.add_animation_library(&"", _root_library(
		clips, offsets, ^"AnimateSymbol/AnimationPlayer", ^"AnimateSymbol:offset", library))
	root_player.autoplay = dancing[0]
	root.add_child(root_player)
	root_player.owner = root

	root.animation_player = root_player
	root.animations = _sing_and_miss_map(miss_falls_back)
	root.mania_anim_groups = _anim_groups()
	root.dancing_animations = dancing
	root.dancing_force_dance = false
	root.dancing_measure_step = 0.25
	root.singing_sing_to_dance_interval = sing_time
	root.singing_repeat_loop_point = 2.0 / FPS
	# gdanimate sprites need the queued animation refreshed the same frame or the first
	# drawn frame is the previous symbol's - the export's own documentation says so.
	root.transition_update_queued_animations = true

	_save(root, "%s/chr_%s.tscn" % [OUT_DIR, basename])


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
		offset_path: NodePath, source: AnimationLibrary,
		looping: Dictionary = {}) -> AnimationLibrary:
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
		# The root animation has to loop too, or the root player stops after one pass and
		# takes the sprite player's clip back to its start with it.
		if looping.has(anim_name):
			animation.loop_mode = Animation.LOOP_LINEAR

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


## One animation over a WINDOW of another clip's frames, looping - a character JSON's
## `frameIndices` with `looped: true`. Added to the sprite library beside the clip it cuts
## from, so the sprite player and the root library both see it.
##
## The window counts the ATLAS's frames, and the importer does not keep those: it dedups
## runs of identical frames into one held longer, and komi's `komigameover` goes from 100
## frames in the XML to 50 held for two each. So indices 6..10 taken against the imported
## list are neither the right pictures nor the right length - which is exactly what this
## did on the first pass, and came out 0.417s instead of 0.208s.
##
## What is exact is to key one frame per ATLAS frame, each showing whichever imported frame
## covers it: the timing is then the mod's whatever the dedup did.
func _window(frames: SpriteFrames, library: AnimationLibrary, basename: String,
		clip: StringName, window: Vector2i) -> StringName:
	var name := StringName("%s_loop" % clip)
	# Dropped rather than skipped if it is already there. The library is a saved resource,
	# so a previous run's version is loaded with it - and returning early on that is how a
	# rebuild reports success while changing nothing, which is what happened here on the
	# first pass and left the wrong 0.417s animation in place.
	if library.has_animation(name):
		library.remove_animation(name)

	var source: Animation = library.get_animation(clip)
	var sprite_clip: String = String(clip).trim_prefix("%s_" % basename)

	# Atlas frame -> imported frame, by running duration.
	var covers: PackedInt32Array = []
	for i: int in frames.get_frame_count(sprite_clip):
		for _held: int in maxi(1, int(round(frames.get_frame_duration(sprite_clip, i)))):
			covers.append(i)

	var animation := Animation.new()
	animation.step = source.step
	animation.loop_mode = Animation.LOOP_LINEAR

	var name_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(name_track, ^".:animation")
	animation.value_track_set_update_mode(name_track, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(name_track, Animation.INTERPOLATION_NEAREST)
	animation.track_insert_key(name_track, 0.0, sprite_clip)

	var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(frame_track, ^".:frame")
	animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)

	var last: int = mini(window.y, covers.size() - 1)
	for k: int in range(window.x, last + 1):
		animation.track_insert_key(
			frame_track, float(k - window.x) * animation.step, covers[k])
	animation.length = maxf(float(last - window.x + 1) * animation.step, animation.step)

	library.add_animation(name, animation)
	print("OUT %s atlas %d..%d -> importados %d..%d, %.3fs" % [
		name, window.x, last, covers[window.x], covers[last], animation.length])
	return name


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
