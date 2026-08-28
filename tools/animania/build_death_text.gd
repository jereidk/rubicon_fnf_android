# Builds the two "retry" text atlases the death sequence shows.
#
# Unlike tadano's character atlas, these are driven by FRAME LABELS on the main timeline -
# `start`, `loop` and `confirm` - and not by symbols. gdanimate plays symbols; a label is
# invisible to it. But AdobeAtlas falls back to the STAGE timeline for a symbol it cannot
# find, so playing the whole timeline and keying `frame` over the label's range gets there,
# and the ranges come straight out of Animation.json's own label list.
#
#   godot --headless --path . --script tools/animania/build_death_text.gd
extends SceneTree

const SOURCE := "res://animania_mod/source/images/phonecall"
const OUT := "res://animania_mod/characters"

# Read out of each Animation.json: the label's first frame and how many frames it covers.
const ATLASES := {
	"tadano-phone-death-text": {
		"basename": "tadano_death_text",
		"labels": {"start": [0, 6], "loop": [6, 15], "confirm": [21, 25]},
	},
	"tadano-phone-stand-death-text": {
		"basename": "tadano_stand_death_text",
		"labels": {"start": [0, 5], "loop": [5, 15], "confirm": [20, 25]},
	},
}


func _init() -> void:
	for folder: String in ATLASES:
		_build(folder, ATLASES[folder])
	quit(0)


func _build(folder: String, entry: Dictionary) -> void:
	var atlas := AdobeAtlas.new()
	atlas.folder_path = "%s/%s" % [SOURCE, folder]
	atlas.parse()
	atlas.cache()

	var basename: String = entry["basename"]
	var atlas_path: String = "%s/%s_atlas.tres" % [OUT, basename]
	var err: int = ResourceSaver.save(atlas, atlas_path)
	if err != OK:
		push_error("no se pudo guardar %s (%d)" % [atlas_path, err])
		quit(1)
		return

	var fps: float = atlas.get_framerate()
	var library := AnimationLibrary.new()

	for label: String in (entry["labels"] as Dictionary):
		var range: Array = (entry["labels"] as Dictionary)[label]
		var animation := Animation.new()
		animation.step = 1.0 / fps
		animation.length = maxf(float(range[1]) / fps, animation.step)
		# `loop` is what the sequence sits on while it waits for a retry.
		animation.loop_mode = Animation.LOOP_LINEAR if label == "loop" \
			else Animation.LOOP_NONE

		var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(frame_track, ^".:frame")
		animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)
		for i: int in int(range[1]):
			animation.track_insert_key(frame_track, float(i) / fps, int(range[0]) + i)

		library.add_animation(label, animation)
		print("OUT %-24s %-8s fotogramas %d..%d  %.3fs" % [
			basename, label, range[0], int(range[0]) + int(range[1]) - 1, animation.length])

	var library_path: String = "%s/%s_library.tres" % [OUT, basename]
	err = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("no se pudo guardar %s (%d)" % [library_path, err])
		quit(1)
		return
	print("OUT guardado %s" % library_path)
