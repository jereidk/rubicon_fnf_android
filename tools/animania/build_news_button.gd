# Builds animania_mod/menus/main/news_button_atlas.tres and its AnimationLibrary.
#
#   godot --headless --path . --script tools/animania/build_news_button.gd
#
# createNewsButton (0x18017a0) does NOT use symbols the way the characters do - it uses
# FRAME LABELS on the composition's main timeline:
#
#     addByFrameLabel("idle",     "loop white")     # 0x18019af
#     addByFrameLabel("selected", "loop white2")    # 0x1801a63
#     addByFrameLabel("open",     "open")           # 0x1801b0d
#
# and Animation.json carries exactly those three, at 0(+6), 6(+4) and 10(+20). So this
# emits one animation per label: the stage symbol on the `:symbol` track and that label's
# own frame range on `:frame`. build_adobe_character.gd cannot do it - it spans a whole
# symbol - which is why this is its own script rather than one more argument there.
extends SceneTree

const FOLDER := "res://animania_mod/source/images/menus/changelog/news_button"
const OUT_DIR := "res://animania_mod/menus/main"
const BASENAME := "news_button"

## label -> animation name, straight off the three addByFrameLabel calls.
const WANTED := {"loop white": "idle", "loop white2": "selected", "open": "open"}


func _init() -> void:
	var stale: String = "%s/animation_cache.res" % FOLDER
	if FileAccess.file_exists(stale):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))

	var atlas := AdobeAtlas.new()
	atlas.folder_path = FOLDER
	atlas.parse()
	atlas.cache()

	var json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/Animation.json" % FOLDER)) as Dictionary
	var labels: Array = _labels(json)
	if labels.is_empty():
		push_error("no frame labels in Animation.json")
		quit(1)
		return

	var fps: float = atlas.get_framerate()
	var library := AnimationLibrary.new()
	for entry: Dictionary in labels:
		var label: String = String(entry["name"])
		if not WANTED.has(label):
			continue
		var first: int = int(entry["index"])
		var count: int = maxi(1, int(entry["duration"]))

		var animation := Animation.new()
		animation.step = 1.0 / fps
		animation.length = maxf(float(count) / fps, animation.step)
		# `open` is the one that must not loop: it is the press, and the menu waits it out.
		animation.loop_mode = Animation.LOOP_NONE if label == "open" else Animation.LOOP_LINEAR

		var symbol_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(symbol_track, ^".:symbol")
		animation.value_track_set_update_mode(symbol_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(symbol_track, Animation.INTERPOLATION_NEAREST)
		animation.track_insert_key(symbol_track, 0.0, String(atlas.stage_symbol))

		var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(frame_track, ^".:frame")
		animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)
		for f: int in count:
			animation.track_insert_key(frame_track, float(f) / fps, first + f)

		library.add_animation("%s_%s" % [BASENAME, String(WANTED[label])], animation)
		print("OUT %-10s frames %d..%d  %.3fs" % [
			WANTED[label], first, first + count - 1, animation.length])

	var atlas_path: String = "%s/%s_atlas.tres" % [OUT_DIR, BASENAME]
	var library_path: String = "%s/%s_library.tres" % [OUT_DIR, BASENAME]
	var err: int = ResourceSaver.save(atlas, atlas_path)
	err = err if err != OK else ResourceSaver.save(library, library_path)
	print("OUT framerate=%.1f  %s" % [fps, "saved" if err == OK else "FAILED"])
	quit(0 if err == OK else 1)


## The labels live on the timeline's layers as frames carrying a name (`N`).
func _labels(json: Dictionary) -> Array:
	var out: Array = []
	var an: Dictionary = json.get("AN", {}) as Dictionary
	var tl: Dictionary = an.get("TL", {}) as Dictionary
	for layer: Variant in tl.get("L", []) as Array:
		for frame: Variant in (layer as Dictionary).get("FR", []) as Array:
			var f: Dictionary = frame as Dictionary
			if not f.has("N"):
				continue
			out.append({
				"name": String(f["N"]),
				"index": int(f.get("I", 0)),
				"duration": int(f.get("DU", 1)),
			})
	return out
