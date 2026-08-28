# Builds an AdobeAtlas resource plus a per-symbol AnimationLibrary for a gdanimate
# AnimateSymbol, headlessly.
#
# gdanimate ships this behind an editor tool button (AnimateSymbol.make_player_from_current),
# which saves next to the atlas under a fixed name and drops one animation per symbol in
# the dictionary -- 63 of them for tadano, of which only 21 are animations a character
# ever plays. This does the same tracks (`:symbol`, `:frame`, `:offset`) but only for the
# symbols asked for, and names them after the character rather than after the symbol path.
#
#   godot --headless --path . --script tools/animania/build_adobe_character.gd \
#       -- <atlas_folder> <out_dir> <basename> <name=symbol> [name=symbol ...]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("usage: <atlas_folder> <out_dir> <basename> <name=symbol> ...")
		quit(1)
		return

	var folder: String = args[0]
	var out_dir: String = args[1]
	var basename: String = args[2]

	var atlas := AdobeAtlas.new()
	atlas.folder_path = folder
	atlas.parse()
	# gdanimate re-reads Animation.json on every parse unless an animation_cache.res sits
	# beside it; writing one here means the phone gets the parsed symbol tree instead of
	# 106KB of JSON at load. The addon looks for it by name, so it has to live in the
	# atlas folder rather than next to the character scene.
	atlas.cache()

	if atlas.symbols.is_empty():
		push_error("no symbols parsed out of %s" % folder)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var atlas_path: String = "%s/%s_atlas.tres" % [out_dir, basename]
	var err: int = ResourceSaver.save(atlas, atlas_path)
	if err != OK:
		push_error("could not save %s (%d)" % [atlas_path, err])
		quit(1)
		return

	var fps: float = atlas.get_framerate()
	var library := AnimationLibrary.new()
	var missing: PackedStringArray = []

	for i: int in range(3, args.size()):
		var pair: PackedStringArray = args[i].split("=", true, 1)
		var anim_name: String = pair[0]
		var symbol: StringName = StringName(pair[1])

		# A composition's top level is not in the symbol dictionary: it lives in
		# `stage_symbol`, taken from the Animation.json's AN.SN. gdanimate plays it by
		# FALLING BACK to it whenever the requested symbol is unknown, so the runtime needs
		# nothing special - but this loop would drop it as missing. The title screen's logo
		# is exactly that shape: 159 symbols composed by a 200-frame stage called `Logolol`,
		# with no single symbol wrapping them.
		var is_stage: bool = symbol == atlas.stage_symbol
		if not atlas.symbols.has(symbol) and not is_stage:
			missing.append(String(symbol))
			continue

		var length: int = atlas.get_length_of(symbol)
		var animation := Animation.new()
		animation.step = 1.0 / fps
		animation.length = maxf(float(length) / fps, animation.step)

		var symbol_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(symbol_track, ^".:symbol")
		animation.value_track_set_update_mode(symbol_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(symbol_track, Animation.INTERPOLATION_NEAREST)
		animation.track_insert_key(symbol_track, 0.0, String(symbol))

		var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(frame_track, ^".:frame")
		animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)
		for f: int in length:
			animation.track_insert_key(frame_track, float(f) / fps, f)

		library.add_animation("%s_%s" % [basename, anim_name], animation)
		print("OUT %-16s frames=%-4d length=%.3fs  <- %s%s" % [
			anim_name, length, animation.length, symbol, " (stage)" if is_stage else ""])

	if not missing.is_empty():
		push_error("symbols not in the atlas: %s" % ", ".join(missing))
		quit(1)
		return

	var library_path: String = "%s/%s_library.tres" % [out_dir, basename]
	err = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("could not save %s (%d)" % [library_path, err])
		quit(1)
		return

	print("OUT framerate=%.1f symbols_in_atlas=%d" % [fps, atlas.symbols.size()])
	print("OUT saved %s" % atlas_path)
	print("OUT saved %s" % library_path)
	quit(0)
