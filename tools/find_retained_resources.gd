extends SceneTree

## Which of a song's resources are still cached after the song is gone.
##
## Leaving Monochrome gives the memory back but not the objects: measured at
## 3,373 of 4,461 resources still resident here, and around 23,000 on the
## device. That is what makes the next shop load take 18.4s instead of 5.0s.
##
## Rather than guess at the mechanism, this asks the engine directly.
## ResourceLoader.has_cached() answers per path, and get_dependencies() walks
## the tree to get the paths, so after the scene is freed every dependency
## can be asked whether it is still there - and the ones that say yes are
## grouped so the pattern shows rather than 3,000 lines of filenames.
##
## Run with:
##   godot --headless --path . --script tools/find_retained_resources.gd

const SCENE := "res://lullaby_mod/songs/monochrome/sng_monochrome.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	print("recogiendo dependencias de %s ..." % SCENE.get_file())
	var deps: Array[String] = []
	var seen: Dictionary = {}
	_collect(SCENE, deps, seen, 0)
	print("  %d dependencias unicas" % deps.size())

	# Anything already cached before the scene loads belongs to the boot
	# state, not to the song, and would be a false positive.
	var pre_cached: Dictionary = {}
	for path: String in deps:
		if ResourceLoader.has_cached(path):
			pre_cached[path] = true
	print("  %d ya estaban cacheadas antes de cargar" % pre_cached.size())

	var before: int = _resources()
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("no pude cargar la escena")
		quit(1)
		return

	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var live: int = _resources()

	instance.queue_free()
	packed = null
	await process_frame
	await process_frame
	await process_frame
	var after: int = _resources()

	print("")
	print("recursos: %d -> %d montada -> %d tras liberar  (retiene %d)" % [
		before, live, after, after - before])
	print("")

	var retained: Array[String] = []
	for path: String in deps:
		if pre_cached.has(path):
			continue
		if ResourceLoader.has_cached(path):
			retained.append(path)

	print("dependencias que siguen cacheadas: %d de %d" % [retained.size(), deps.size() - pre_cached.size()])
	print("")

	_report_by(retained, "extension", func(p: String) -> String: return p.get_extension())
	_report_by(retained, "carpeta", func(p: String) -> String:
		var parts: PackedStringArray = p.trim_prefix("res://").split("/")
		return "/".join(parts.slice(0, mini(3, parts.size() - 1))))

	print("")
	print("los que NO son scripts:")
	for path: String in retained:
		if path.get_extension() == "gd":
			continue
		print("  %s" % path.trim_prefix("res://"))

	quit(0)

## get_dependencies() is one level deep, so this walks it. Depth-capped
## because a cyclic reference between two scenes would otherwise not stop.
func _collect(path: String, out: Array[String], seen: Dictionary, depth: int) -> void:
	if depth > 12 or seen.has(path):
		return
	seen[path] = true
	out.append(path)

	for entry: String in ResourceLoader.get_dependencies(path):
		# Entries come as "uid::type::path" or just a path.
		var dep: String = entry.get_slice("::", entry.count("::"))
		if dep.is_empty() or not dep.begins_with("res://"):
			continue
		_collect(dep, out, seen, depth + 1)

func _report_by(paths: Array[String], label: String, key: Callable) -> void:
	var counts: Dictionary = {}
	for path: String in paths:
		var k: String = key.call(path)
		counts[k] = counts.get(k, 0) + 1

	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])

	print("por %s:" % label)
	for k in keys.slice(0, 10):
		print("  %5d  %s" % [counts[k], k])
	print("")

func _resources() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
