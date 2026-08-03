extends Node
## Autoloaded as "Mods". Adds mods-folder support to Rubicon, similar to Psych Engine's
## backend/Mods.hx + backend/Paths.hx.
##
## A mod is a folder under [method get_mods_root]. Each mod folder may contain:
## - Any number of ".pck" files, mounted on top of "res://" at boot via
##   [method ProjectSettings.load_resource_pack]. This is the primary way to add or
##   override content (characters, songs, stages, scripts): export it from a Godot
##   project that uses the Rubicon addon, matching "res://" paths to override existing
##   content, or new paths to add content that the game already scans for.
## - Loose files (images, audio, json, etc.) that aren't part of a pack. These are
##   resolved on demand through [method get_asset_path], mirroring Psych's modFolders().
## - An optional "mod.json" manifest with metadata (name, description, version, author,
##   and "global", equivalent to Psych's pack.json "runsGlobally").
##
## Packs are additive for the lifetime of the process (Godot has no official "unload"
## for a mounted pack), so toggling a mod that ships a .pck only takes effect after a
## restart. Loose-file overrides resolved through [method get_asset_path] apply immediately.

const MANIFEST_FILENAME := "mod.json"
const STATE_PATH := "user://mods_list.json"

## All mods found on disk, in load priority order (index 0 loads/overrides last, i.e.
## has the final say — matches Psych's "top of the list wins").
var mod_list: Array[RubiconModInfo] = []

var _loose_dirs: Array[String] = []
var _mods_root_cache: String = ""

func _ready() -> void:
	reload()

## Returns the absolute path to the folder that contains mod subfolders.
## Desktop: next to the executable (or the project root, when running from the editor).
## Android/iOS/Web: under the app's persistent data directory, since those platforms
## don't allow writing next to the executable.
func get_mods_root() -> String:
	if _mods_root_cache != "":
		return _mods_root_cache

	var root: String
	match OS.get_name():
		"Android", "iOS", "Web":
			root = "user://mods"
		_:
			var base_dir: String = OS.get_executable_path().get_base_dir()
			if OS.has_feature("editor"):
				base_dir = ProjectSettings.globalize_path("res://")
			root = base_dir.path_join("mods")

	_mods_root_cache = root
	return root

## Re-scans the mods root, reconciles it with the saved enabled/order state, mounts
## packs for every active mod and rebuilds the loose-file resolver. Safe to call again
## later (e.g. after the user drops in a new mod folder), though already-mounted packs
## from a previous call can't be unmounted.
func reload() -> void:
	var root := get_mods_root()
	_ensure_dir(root)

	var saved := _load_saved_state()
	var found := _scan_mod_folders(root)

	var new_list: Array[RubiconModInfo] = []
	var seen := {}

	for entry in saved:
		if not (entry is Dictionary):
			continue
		var folder: String = entry.get("folder", "")
		if folder != "" and found.has(folder) and not seen.has(folder):
			var info := _load_mod_info(root, folder)
			info.enabled = entry.get("enabled", true)
			new_list.append(info)
			seen[folder] = true

	# Newly discovered folders that weren't in the saved list get appended, enabled by
	# default (matches Psych: new mod folders show up already turned on).
	for folder in found:
		if not seen.has(folder):
			new_list.append(_load_mod_info(root, folder))
			seen[folder] = true

	mod_list = new_list
	_save_state()
	_apply_mods()

## Resolves "relative_path" against every currently active mod folder, in priority
## order, falling back to the base game's "res://relative_path" if no mod provides it.
## Use this for loose-file overrides (e.g. Mods.get_asset_path("images/menu/bg.png")).
## Named get_asset_path (not get_path) because Node already defines get_path() -> NodePath
## with an incompatible signature; overriding it silently breaks the whole autoload.
func get_asset_path(relative_path: String) -> String:
	for mod_dir in _loose_dirs:
		var candidate := mod_dir.path_join(relative_path)
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return "res://" + relative_path

## Returns every enabled/global mod's absolute root folder, in priority order.
func get_active_mod_dirs() -> Array[String]:
	return _loose_dirs.duplicate()

func get_mod_list() -> Array[RubiconModInfo]:
	return mod_list

func get_mod(folder: String) -> RubiconModInfo:
	for info in mod_list:
		if info.folder_name == folder:
			return info
	return null

## Enables/disables a mod and persists the choice. Mods flagged "global" in their
## manifest ignore this. Packs already mounted from a .pck stay mounted until restart.
func set_mod_enabled(folder: String, enabled: bool) -> void:
	var info := get_mod(folder)
	if info == null or info.global:
		return
	info.enabled = enabled
	_save_state()
	_apply_mods()

## Moves a mod to a new index in [member mod_list] and persists the new order.
func set_mod_priority(folder: String, new_index: int) -> void:
	var index := -1
	for i in mod_list.size():
		if mod_list[i].folder_name == folder:
			index = i
			break
	if index == -1:
		return

	var info := mod_list[index]
	mod_list.remove_at(index)
	mod_list.insert(clampi(new_index, 0, mod_list.size()), info)
	_save_state()
	_apply_mods()

func _scan_mod_folders(root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			result.append(name)
		name = dir.get_next()
	dir.list_dir_end()

	# Directory listing order isn't guaranteed by the OS/filesystem; sort so newly
	# discovered mods get a stable, reproducible default priority instead of whatever
	# order readdir() happened to return.
	result.sort()
	return result

func _load_mod_info(root: String, folder: String) -> RubiconModInfo:
	var info := RubiconModInfo.new()
	info.folder_name = folder
	info.display_name = folder

	var manifest_path := root.path_join(folder).path_join(MANIFEST_FILENAME)
	if not FileAccess.file_exists(manifest_path):
		return info

	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return info
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed is Dictionary:
		info.display_name = parsed.get("name", folder)
		info.description = parsed.get("description", "")
		info.version = parsed.get("version", "")
		info.author = parsed.get("author", "")
		info.global = parsed.get("global", false)

	return info

## Mounts packs for every active mod and rebuilds the loose-file directory list.
## Mods earlier in [member mod_list] override mods later in the list, and both override
## the base game, matching Psych's priority order (current mod, then global mods, in
## list order, then the base "assets/" folder).
func _apply_mods() -> void:
	_loose_dirs.clear()
	var root := get_mods_root()

	for info in mod_list:
		if not (info.enabled or info.global):
			continue

		var mod_dir := root.path_join(info.folder_name)
		_loose_dirs.append(mod_dir)
		_mount_packs(mod_dir)

func _mount_packs(mod_dir: String) -> void:
	var dir := DirAccess.open(mod_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "pck":
			var pck_path := mod_dir.path_join(name)
			if not ProjectSettings.load_resource_pack(pck_path, true):
				push_warning("RubiconMods: failed to load pack '%s'" % pck_path)
		name = dir.get_next()
	dir.list_dir_end()

func _save_state() -> void:
	var arr := []
	for info in mod_list:
		arr.append({"folder": info.folder_name, "enabled": info.enabled})

	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("RubiconMods: couldn't write '%s'" % STATE_PATH)
		return
	file.store_string(JSON.stringify(arr, "\t"))
	file.close()

func _load_saved_state() -> Array:
	if not FileAccess.file_exists(STATE_PATH):
		return []

	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	return parsed if parsed is Array else []

func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
