extends SceneTree

## Guards the songs' animated bool tracks against being "fixed" again.
##
## fce21be rewrote 220 value tracks across 28 files from CONTINUOUS to
## DISCRETE, on the reasoning that a bool ought to switch at its keyframe
## rather than interpolate to the midpoint between two. b61aed2 reverted all
## of it: the device showed three scenes broken by the change - Gold's head
## vanishing, Chimera going black - and the PC pck, which was available to
## check the whole time, ships these tracks CONTINUOUS. The rule was right
## about how Godot interpolates and wrong about what the mod was authored
## against.
##
## This test shipped with the change and asserted DISCRETE. The revert took
## the data back and left the test, so it has been failing since 9 August
## while asserting a contract the project deliberately does not have - which
## is worse than no test, because a permanently red suite teaches everyone to
## stop reading it.
##
## Inverted rather than deleted. The mistake actually happened and cost three
## broken scenes, so a guard that catches a second attempt is worth keeping;
## it just has to point the other way. CONTINUOUS is the shipped state and the
## state the PC build has.
##
## Run with:
##   godot --headless --path . --script tools/test_song_bool_tracks.gd

const SONGS := [
	"res://lullaby_mod/songs/monochrome/sng_monochrome.tscn",
	"res://lullaby_mod/songs/chimera/sng_chimera.tscn",
	"res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn",
]

## The tracks whose misfiring was visible on the device when they were
## DISCRETE. If any of these turns up switched again, this is the change being
## repeated.
const WATCHED := [
	"TypingChallenge:active",
	"KingsEye:visible",
	"UILayer/GameUI:visible",
	"UnownKing/TextureRect:visible",
]

var _failures: int = 0
var _continuous: int = 0
var _discrete: int = 0
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
	print("CONTINUOUS (lo correcto) : %d" % _continuous)
	print("DISCRETE (regresion)     : %d" % _discrete)
	if not _skipped.is_empty():
		print("canciones sin importar   : %s" % ", ".join(_skipped))
	print("")

	# _seen holds the watched tracks found switched to DISCRETE. It should now
	# be empty: finding one means the reverted change is creeping back.
	for path: String in WATCHED:
		if _seen.has(path):
			_failures += 1
			print("  FALLO %-34s vuelve a estar en DISCRETE" % path)
		else:
			print("  ok    %-34s sigue CONTINUOUS" % path)

	if _discrete > 0:
		_failures += 1
		print("  FALLO %d pistas de bool pasaron a DISCRETE" % _discrete)

	# An import-less checkout finds nothing at all, which would pass this
	# vacuously - the exact failure mode that has bitten twice already.
	if _checked == 0:
		_failures += 1
		print("  FALLO no se examino ninguna pista - checkout sin importar?")

	print("")
	if _failures == 0:
		print("todo OK - los bools siguen CONTINUOUS, como el pck de PC")
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
		elif mode == Animation.UPDATE_DISCRETE:
			_discrete += 1
			print("  DISCRETE: %s" % animation.track_get_path(track))

		var path: String = str(animation.track_get_path(track))
		for watched: String in WATCHED:
			if path.ends_with(watched) and mode == Animation.UPDATE_DISCRETE:
				_seen[watched] = animation.track_get_key_count(track)
