extends Node

## El vigilante de probe_mixer_caches.gd. Vive colgado de `root` para sobrevivir
## al cambio de escena.

var _until: float = 25.0
var _t: float = 0.0
var _hooked: bool = false
var _clears: Dictionary = {}
var _per_second: Dictionary = {}
var _frames: int = 0
var _slow: Array = []
var _mixers: int = 0
var _tracks: int = 0
var _scans: int = 0


func setup(until: float) -> void:
	_until = until
	set_process(true)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	var song: Node = get_tree().current_scene
	if song == null or song == self:
		return

	if not _hooked:
		_hook(song)
		return

	_t += delta
	_frames += 1

	# Los fotogramas lentos, para poder cruzar las dos series.
	if delta > 0.1:
		_slow.append("%.2fs:%.0fms" % [_t, delta * 1000.0])

	var sec: int = int(_t)
	if not _per_second.has(sec):
		_per_second[sec] = 0

	if _t >= _until:
		_report()
		get_tree().quit()


## Engancha `caches_cleared` en cada AnimationMixer del árbol.
func _hook(song: Node) -> void:
	var stack: Array[Node] = [song]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationMixer:
			_mixers += 1
			var path: String = String(song.get_path_to(n))
			_clears[path] = 0
			_tracks += _count_tracks(n)
			n.caches_cleared.connect(_on_cleared.bind(path))
		stack.append_array(n.get_children())

	# NO se da por enganchado si no encontró ninguno.
	#
	# La primera versión marcaba `_hooked = true` pase lo que pase, y el primer
	# fotograma en que `current_scene` no es null todavía es la escena de la
	# SONDA - el cambio a Chimera no se ha resuelto aún. Escaneaba un árbol de un
	# nodo, encontraba cero mixers, y se quedaba así los veinticinco segundos:
	# "0 mixers, 0 pistas, 1500 fotogramas, 0 fotogramas lentos", que parece una
	# medición y es una escena vacía.
	if _mixers == 0:
		_scans += 1
		if _scans % 300 == 0:
			print("OUT (esperando escena con mixers, escena=%s, %d intentos)"
				% [song.name, _scans])
		_clears.clear()
		_tracks = 0
		return

	_hooked = true
	print("OUT enganchados %d AnimationMixer en '%s', %d pistas en total"
		% [_mixers, song.name, _tracks])


func _count_tracks(mixer: AnimationMixer) -> int:
	var total: int = 0
	for lib_name: StringName in mixer.get_animation_library_list():
		var lib: AnimationLibrary = mixer.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			total += lib.get_animation(anim_name).get_track_count()
	return total


func _on_cleared(path: String) -> void:
	_clears[path] = int(_clears.get(path, 0)) + 1
	var sec: int = int(_t)
	_per_second[sec] = int(_per_second.get(sec, 0)) + 1


func _report() -> void:
	var total: int = 0
	var busiest: Array = []
	for path: String in _clears:
		var n: int = _clears[path]
		total += n
		if n > 0:
			busiest.append([n, path])
	busiest.sort_custom(func(a, b): return a[0] > b[0])

	print("")
	print("OUT === %d mixers, %d pistas, %.1fs, %d fotogramas ==="
		% [_mixers, _tracks, _t, _frames])
	print("OUT reconstrucciones de cache: %d en total" % total)
	print("OUT los que mas: ")
	for row: Array in busiest.slice(0, 12):
		print("OUT    %4d x  %s" % [row[0], row[1]])

	print("OUT por segundo:")
	var line: PackedStringArray = []
	for sec: int in range(0, int(_t) + 1):
		line.append("%ds:%d" % [sec, int(_per_second.get(sec, 0))])
	print("OUT    %s" % " ".join(line))

	print("OUT fotogramas lentos (>100ms): %d" % _slow.size())
	if not _slow.is_empty():
		print("OUT    %s" % " ".join(PackedStringArray(_slow).slice(0, 20)))
