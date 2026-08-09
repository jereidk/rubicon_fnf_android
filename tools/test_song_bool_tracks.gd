extends SceneTree

## Checks that the tracks the songs use to switch things on and off now do it
## at their keys.
##
## 220 value tracks across 28 files were rewritten from CONTINUOUS to
## DISCRETE at once. That is a lot to change on the strength of a rule, so
## this reads the shipped animations back and asserts the rule holds for the
## ones whose misfiring was actually visible on the device: Monochrome's
## typing mechanic, its grey KingsEye, its HUD - which is where the hitboxes
## live - and the vignette whose disabled tracks are switched back on here.
##
## Run with:
##   godot --headless --path . --script tools/test_song_bool_tracks.gd

const SONGS := [
	"res://lullaby_mod/songs/monochrome/sng_monochrome.tscn",
	"res://lullaby_mod/songs/chimera/sng_chimera.tscn",
	"res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn",
]

## The ones whose wrong timing was reported from the device.
const WATCHED := [
	"TypingChallenge:active",
	"KingsEye:visible",
	"UILayer/GameUI:visible",
	"UnownKing/TextureRect:visible",
]

var _failures: int = 0
var _continuous: int = 0
var _checked: int = 0
var _seen: Dictionary = {}
## Songs whose assets this checkout has not imported. Not a failure: an
## incomplete local import is an environment problem, and CI imports
## everything before it runs. Printed so it can never be silent.
var _skipped: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for song: String in SONGS:
		_scan(song)

	print("")
	print("pistas de bool revisadas : %d" % _checked)
	print("todavia CONTINUOUS       : %d" % _continuous)
	if not _skipped.is_empty():
		print("canciones sin importar   : %s" % ", ".join(_skipped))
	print("")

	for path: String in WATCHED:
		if _seen.has(path):
			print("  ok    %-34s DISCRETE, %d claves" % [path, _seen[path]])
		else:
			_failures += 1
			print("  FALLO %-34s no la encontre en ninguna cancion" % path)

	if _continuous > 0:
		_failures += 1
		print("  FALLO quedan %d pistas de bool interpolandose" % _continuous)

	print("")
	if _failures == 0:
		print("todo OK - los bools conmutan en su clave")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## Walks every animation a song's scene file references and reports the value
## tracks whose values are all booleans.
func _scan(song: String) -> void:
	var packed: PackedScene = ResourceLoader.load(song, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		_skipped.append(song.get_file())
		return

	var state: SceneState = packed.get_state()
	for node: int in state.get_node_count():
		for prop: int in state.get_node_property_count(node):
			var value: Variant = state.get_node_property_value(node, prop)
			if value is AnimationLibrary:
				for name: StringName in value.get_animation_list():
					_scan_animation(value.get_animation(name))
			elif value is Animation:
				_scan_animation(value)

func _scan_animation(animation: Animation) -> void:
	if animation == null:
		return

	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_VALUE:
			continue
		if animation.track_get_key_count(track) < 2:
			continue

		var all_bool: bool = true
		for key: int in animation.track_get_key_count(track):
			if typeof(animation.track_get_key_value(track, key)) != TYPE_BOOL:
				all_bool = false
				break
		if not all_bool:
			continue

		_checked += 1
		var mode: int = animation.value_track_get_update_mode(track)
		if mode == Animation.UPDATE_CONTINUOUS:
			_continuous += 1
			print("  CONTINUOUS todavia: %s" % animation.track_get_path(track))

		var path: String = str(animation.track_get_path(track))
		for watched: String in WATCHED:
			if path.ends_with(watched) and mode == Animation.UPDATE_DISCRETE:
				_seen[watched] = animation.track_get_key_count(track)
