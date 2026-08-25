extends SceneTree

## The art a pre-rendered cutscene video replaces must stay in the project.
##
## The question this answers, written down because it will be asked again: now
## that Safety Lullaby's intro and Chimera's prelude are .ogv files, can the
## sprites and backgrounds they were made from be deleted?
##
## No. Only two presets ask for video:
##
##     qol_low.tres       prefer_cutscene_video = true
##     qol_very_low.tres  prefer_cutscene_video = true
##
## Medium, High and Ultra run the LIVE cutscene, and LullabyCutsceneVideo
## retires silently when the preset does not want it or the .ogv is missing.
## The art is not the old path; it is the path most players are on. Deleting it
## would leave the majority of the game blank, and nothing would raise an error
## - the video node simply would not engage and the scene would draw nothing.
##
## Measured, so the trade is on the record rather than argued from memory:
##
##     Safety Lullaby  intro.tscn      29 ficheros  8.3 MB  ->  intro.ogv   3.2 MB
##     Chimera         Intro+Prelude   13 ficheros  9.3 MB  ->  prelude.ogv 3.5 MB
##
## The videos are smaller than the art they stand in for - 6.7 MB against 17.6
## - which is exactly what makes deleting the art look like a free win. It is
## not free; it is the Medium-and-above rendering path.
##
## What IS wasted, and is left alone on purpose: on Low the scene still loads
## the art it will not draw, because the cutscene is a dependency of the song
## scene. For Safety Lullaby that is ~0.5s of a 3.19s load and it could be
## deferred - the instance has zero external overrides and only seven NodePath
## references. For Chimera it could not: Intro is seventeen inline nodes and
## about twenty-four references reach inside it, down to
## Intro/IntroAnimationPlayer and Prelude/Black. Half a second, bought with the
## exact failure mode that had already silently dropped Chimera's caption -
## a reference that stops resolving and says nothing - is not a good trade
## today. This file exists so that decision stays deliberate.
##
## Run with:
##   godot --headless --path . --script tools/test_cutscene_assets_kept.gd

const VIDEO_SCRIPT := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"

## Songs known to hand a cutscene over to a video, and what each one replaces.
## Listed rather than discovered so that a scene LOSING its video node is a red
## line here instead of a silently shorter run.
const WIRED := {
	"safety lullaby": "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn",
	"chimera": "res://lullaby_mod/songs/chimera/sng_chimera.tscn",
}

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_preset_checks()
	for label: String in WIRED:
		_song_checks(label, WIRED[label])

	print("")
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el arte que sustituyen los videos sigue entero")
	quit(1 if _failures > 0 else 0)


## The premise the whole file rests on: that some preset still runs the live
## cutscene. If every preset ever switched to video, the art really would be
## dead and this guard would be arguing from a fact that stopped being true.
func _preset_checks() -> void:
	var dir: DirAccess = DirAccess.open("res://lullaby_mod/resources/quality_presets")
	_check("se lee la carpeta de presets", dir != null)
	if dir == null:
		return

	var video: PackedStringArray = []
	var live: PackedStringArray = []
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var text: String = FileAccess.get_file_as_string(
			"res://lullaby_mod/resources/quality_presets/".path_join(file))
		if text.contains("prefer_cutscene_video = true"):
			video.append(file)
		else:
			live.append(file)

	_check("algun preset pide video", not video.is_empty(), ", ".join(video))
	_check("y alguno sigue corriendo la cutscene viva", not live.is_empty(),
		", ".join(live))


func _song_checks(label: String, path: String) -> void:
	var scene: String = FileAccess.get_file_as_string(path)
	_check("[%s] la escena se lee" % label, not scene.is_empty())
	if scene.is_empty():
		return

	# El id del script del nodo de video en ESTA escena.
	var script_id: String = ""
	var re := RegEx.create_from_string(
		'\\[ext_resource type="Script"[^\\]]*path="%s"[^\\]]*id="([^"]+)"'
			% VIDEO_SCRIPT.replace("/", "\\/").replace(".", "\\."))
	var found: RegExMatch = re.search(scene)
	if found != null:
		script_id = found.get_string(1)
	_check("[%s] la escena usa LullabyCutsceneVideo" % label, not script_id.is_empty())
	if script_id.is_empty():
		return

	var block: String = _block_with(scene, 'script = ExtResource("%s")' % script_id)
	_check("[%s] su nodo de video esta en la escena" % label, not block.is_empty())
	if block.is_empty():
		return

	# El .ogv. Que exista es lo que hace que el camino de video sea real; sin
	# el, el nodo se retira en silencio y Low se queda con la cutscene viva -
	# que funciona, pero entonces el video no esta haciendo nada.
	var video_path: String = _quoted(block, "video_path = \"")
	_check("[%s] declara un video_path" % label, not video_path.is_empty())
	if not video_path.is_empty():
		_check("[%s] y el .ogv esta en el repo: %s" % [label, video_path.get_file()],
			FileAccess.file_exists(video_path))

	# Y la cutscene viva: el nodo, y todo el arte del que cuelga.
	var live_path: String = _quoted(block, "live_cutscene = NodePath(\"")
	_check("[%s] declara un live_cutscene" % label, not live_path.is_empty())
	if live_path.is_empty():
		return

	var live_name: String = live_path.trim_prefix("../")
	_check("[%s] el nodo '%s' sigue en la escena" % [label, live_name],
		scene.contains('[node name="%s"' % live_name))

	_art_checks(label, scene, live_name)


## Every file the live cutscene draws from, still on disk.
##
## This is the check the rest of the file exists for. A cleanup pass that
## deletes "unused" sprites because a video now covers them turns this red
## instead of shipping a blank cutscene to everyone above Low.
##
## Two shapes, because the two songs are authored differently. Safety Lullaby's
## IntroCutscene is an instance of intro.tscn, so the art hangs off that scene
## and is followed into it. Chimera's Intro is seventeen inline nodes, so the
## art is whatever ExtResource its own blocks name.
func _art_checks(label: String, scene: String, live_name: String) -> void:
	var ids: Dictionary = {}
	for m in RegEx.create_from_string(
			'\\[ext_resource type="([^"]+)"[^\\]]*path="([^"]+)"[^\\]]*id="([^"]+)"'
			).search_all(scene):
		ids[m.get_string(3)] = m.get_string(2)

	var wanted: Dictionary = {}
	for block: String in scene.split("\n[node "):
		var head: String = block.split("\n", true, 1)[0]
		var name: String = _quoted(head, 'name="')
		var parent: String = _quoted(head, 'parent="')
		if parent.is_empty():
			continue
		var inside: bool = parent.begins_with(live_name) \
			or (parent == "." and name == live_name)
		if not inside:
			continue
		for m in RegEx.create_from_string('ExtResource\\("([^"]+)"\\)').search_all(block):
			var id: String = m.get_string(1)
			if ids.has(id):
				wanted[ids[id]] = true

	# Una instancia trae su arte dentro de su propia escena, no aqui.
	var followed: Dictionary = {}
	for res: String in wanted:
		followed[res] = true
		if not res.ends_with(".tscn"):
			continue
		var inner: String = FileAccess.get_file_as_string(res)
		for m in RegEx.create_from_string(
				'\\[ext_resource [^\\]]*path="([^"]+)"').search_all(inner):
			followed[m.get_string(1)] = true

	_check("[%s] la cutscene viva sigue teniendo arte del que tirar" % label,
		followed.size() >= 3, "%d recursos" % followed.size())

	var missing: PackedStringArray = []
	for res: String in followed:
		if not FileAccess.file_exists(res) and not ResourceLoader.exists(res):
			missing.append(res.get_file())
	_check("[%s] y ninguno de sus %d recursos falta" % [label, followed.size()],
		missing.is_empty(),
		"" if missing.is_empty() else "faltan: " + ", ".join(missing.slice(0, 5)))


## El bloque `[node ...]` que contiene `needle`.
func _block_with(scene: String, needle: String) -> String:
	var at: int = scene.find(needle)
	if at < 0:
		return ""
	var head: int = scene.rfind("[node ", at)
	if head < 0:
		return ""
	var tail: int = scene.find("\n[", at)
	return scene.substr(head, (tail - head) if tail > head else -1)


## Lo que va entre comillas justo despues de `prefix`.
func _quoted(text: String, prefix: String) -> String:
	var at: int = text.find(prefix)
	if at < 0:
		return ""
	var start: int = at + prefix.length()
	var end: int = text.find("\"", start)
	return text.substr(start, end - start) if end > start else ""


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-58s%s" % [what, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		printerr("  FALLO %-58s%s" % [what, "  (%s)" % detail if detail else ""])
