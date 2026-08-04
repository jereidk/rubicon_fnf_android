extends SceneTree

## CI gate for the "bare uid:// string in game code" crash class (see
## commit "Restore resources/collector_shop/env_collector_shop.exr" and
## the "Restore restore-keys" commit for the full incident - a scene's own
## uid failing to resolve at runtime, hit via SceneChanger.change_to("uid://...")
## or preload("uid://...") with no res:// path fallback to fall back to).
##
## ext_resource-declared uids (the overwhelming majority of uid usage in
## this project) always carry a text-path fallback and degrade gracefully
## when the uid cache is incomplete - this script only checks the much
## smaller set of *bare* "uid://..." string literals in .gd source, which
## have no such fallback and hard-crash instead. Run right after the
## Import step, against the same uid_cache.bin the Export step will read,
## so a broken reference here fails the CI build loudly instead of
## shipping an APK that crashes on a specific menu action.

const UID_PATTERN := "uid://[a-z0-9]+"

func _initialize() -> void:
	var regex := RegEx.new()
	regex.compile(UID_PATTERN)

	# uid -> first file:line it was found at (for reporting)
	var found: Dictionary = {}
	_scan_dir("res://", regex, found)

	print("Found ", found.size(), " unique bare uid:// reference(s) in .gd source.")

	var failures: Array = []
	for uid_str in found.keys():
		var uid_int: int = ResourceUID.text_to_id(uid_str)
		if not ResourceUID.has_id(uid_int):
			failures.append(uid_str)

	if failures.is_empty():
		print("OK: every bare uid:// reference resolves.")
		quit(0)
		return

	printerr("FAILED: ", failures.size(), " bare uid:// reference(s) do not resolve:")
	for uid_str in failures:
		printerr("  ", uid_str, " - first seen at ", found[uid_str])
	printerr("These are hardcoded 'uid://...' strings in .gd code with no res:// path")
	printerr("fallback (SceneChanger.change_to, preload, change_scene_to_file, etc).")
	printerr("If this uid genuinely still exists, .godot/uid_cache.bin doesn't have it")
	printerr("registered - re-run the import step. If the target was deleted/moved,")
	printerr("update the source .gd file to the new uid.")
	quit(1)

func _scan_dir(path: String, regex: RegEx, found: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name in [".git", ".godot", ".import"]:
			name = dir.get_next()
			continue
		var full_path: String = path.path_join(name)
		if dir.current_is_dir():
			_scan_dir(full_path, regex, found)
		elif name.ends_with(".gd"):
			_scan_file(full_path, regex, found)
		name = dir.get_next()

func _scan_file(path: String, regex: RegEx, found: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var line_num := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_num += 1
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		for m in regex.search_all(line):
			var uid_str: String = m.get_string()
			if not found.has(uid_str):
				found[uid_str] = "%s:%d" % [path, line_num]
