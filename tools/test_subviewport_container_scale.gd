extends SceneTree

## The render scale has to reach a SubViewport owned by a SubViewportContainer,
## and until now it did not reach a single one.
##
## `_scale_subviewport()` scales by writing `viewport.size`. A container with
## `stretch` on owns that property and writes it back **on the spot** - not on
## the next resize, immediately. Measured on 4.7.1, container 720x540:
##
##     viewport.size = 360x270        ->  size sigue 720x540
##     container.stretch_shrink = 2   ->  size 360x270, override 720x540
##
## So every SubViewport inside a stretching container has been rendering at its
## authored size on a phone running everything else at 0.50. The two that cost
## something are in the shop's console, both 720x540, and the device log names
## them live at exactly that:
##
##     sub=6/7 sub_gpu=5.18-9.73ms sub_px=1.38M
##     sub_top=.../Home/IconSubViewport/SubViewport(720x540),
##             .../console_bg/Control/SubViewportContainer/SubViewport(720x540),
##             Viewports/KollectadexSubViewport(620x464)
##
## KollectadexSubViewport is authored 1240x928 and runs at 620x464 - scaled,
## because nothing owns its size. The two console ones are 0.78 Mpx of that
## 1.38 Mpx, unscaled, and they are what tips the room over a 60Hz frame: the
## shop medians 16.90ms with the console shut and 20.75ms with it open, and the
## frame histogram splits clean into 12-20ms and 28-40ms, because a frame that
## misses a refresh waits for the next one.
##
## What this pins is the mechanism, not the numbers: that the container branch
## exists, that it uses stretch_shrink rather than fighting for `size`, and -
## the part a textual check cannot see - that writing `size` really is futile
## and stretch_shrink really does shrink the render target while leaving the
## layout size alone.
##
## Run with:
##   godot --headless --path . --script tools/test_subviewport_container_scale.gd

const SETTINGS_PATH := "res://menus/settings.gd"
const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0

## Built here rather than in _process, so the container has had a frame to lay
## itself out before anything is asserted about it. `viewport.size` updates the
## instant stretch_shrink is written; `get_visible_rect()` does not, and reading
## it on a container created in the same call reports the pre-shrink rect.
var _probe_container: SubViewportContainer
var _probe_viewport: SubViewport


func _initialize() -> void:
	_source_checks()
	_scene_checks()

	_probe_container = SubViewportContainer.new()
	_probe_container.stretch = true
	_probe_container.size = Vector2(720, 540)
	_probe_viewport = SubViewport.new()
	_probe_viewport.size = Vector2i(720, 540)
	_probe_container.add_child(_probe_viewport)
	root.add_child(_probe_container)


## The behavioural half needs a live tree: the autoload is only reachable once
## the SceneTree is wired, and a container only resizes its child in-tree.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_engine_checks()
	_scaler_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
	return true


func _source_checks() -> void:
	var code: String = _strip_comments(_read(SETTINGS_PATH))
	var at: int = code.find("func _scale_subviewport(")
	_check(at >= 0, "_scale_subviewport existe")
	if at < 0:
		return
	var body: String = code.substr(at)
	body = body.substr(0, body.find("\nfunc "))

	_check(body.contains("as SubViewportContainer"),
		"reconoce el caso del contenedor")
	_check(body.contains("container.stretch_shrink"),
		"y lo escala por stretch_shrink, no peleando por `size`")
	_check(body.contains("container.stretch"),
		"solo cuando el contenedor tiene stretch: sin el no toca el tamaño")

	# El orden importa: si la rama del contenedor fuese despues, el bloque de
	# `size` habria dejado ya un size_2d_override que el contenedor pisa.
	var container_at: int = body.find("as SubViewportContainer")
	var size_at: int = body.find("viewport.size_2d_override = authored")
	_check(size_at < 0 or container_at < size_at,
		"y sale por ahi antes de tocar size/size_2d_override")


func _scene_checks() -> void:
	var console: String = _read(CONSOLE)
	var owned: int = 0
	for m in RegEx.create_from_string("size = Vector2i\\((\\d+), (\\d+)\\)").search_all(console):
		if int(m.get_string(1)) * int(m.get_string(2)) >= 720 * 540:
			owned += 1
	_check(owned >= 2,
		"la consola sigue teniendo los SubViewport grandes que motivaron esto (%d)" % owned)
	_check(console.contains("stretch = true"),
		"y siguen dentro de contenedores con stretch")


## The engine behaviour the fix depends on. If a future Godot stops letting the
## container win, the first of these fails and the branch can go.
func _engine_checks() -> void:
	var container: SubViewportContainer = _probe_container
	var viewport: SubViewport = _probe_viewport

	# The Settings autoload keeps a node_added hook so a scene loaded later gets
	# scaled too, and this probe was added to the tree, so the fix has already
	# run on it. Undone here to get the engine's own behaviour back - and the
	# fact that it needs undoing is itself the hook working.
	container.stretch_shrink = 1
	viewport.size_2d_override = Vector2i.ZERO
	viewport.size_2d_override_stretch = false
	viewport.size = Vector2i(720, 540)

	viewport.size = Vector2i(360, 270)
	_check(viewport.size == Vector2i(720, 540),
		"escribir size bajo un contenedor con stretch no hace nada (es %s)" % viewport.size)

	container.stretch_shrink = 2
	_check(viewport.size == Vector2i(360, 270),
		"stretch_shrink=2 si reduce el objetivo de render (es %s)" % viewport.size)

	# Y por que el shrink solo no basta: el contenedor escribe `size` y nunca
	# `size_2d_override`, asi que el espacio de maquetacion se encoge con el.
	_check(viewport.get_visible_rect().size == Vector2(360, 270),
		"pero el shrink solo tambien encoge la maquetacion (es %s)" % viewport.get_visible_rect().size)
	viewport.size_2d_override = Vector2i(720, 540)
	viewport.size_2d_override_stretch = true
	_check(viewport.get_visible_rect().size == Vector2(720, 540),
		"y el override la devuelve (es %s)" % viewport.get_visible_rect().size)
	container.size = Vector2(720, 541)
	_check(viewport.size_2d_override == Vector2i(720, 540),
		"y sobrevive a un resize del contenedor, que solo escribe `size`")

	container.queue_free()


## And the scaler itself, through the autoload, at a scale the phone uses.
func _scaler_checks() -> void:
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		_check(false, "existe el autoload Settings")
		return

	var previous: float = settings.graphics_render_scale
	settings.graphics_render_scale = 0.5

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size = Vector2(720, 540)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 540)
	container.add_child(viewport)
	root.add_child(container)

	settings.call("_scale_subviewport", viewport)
	_check(container.stretch_shrink == 2,
		"a escala 0.50 el contenedor queda en stretch_shrink=2 (es %d)" % container.stretch_shrink)
	_check(viewport.size == Vector2i(360, 270),
		"o sea 0.25 de los pixeles que renderizaba (es %s)" % viewport.size)
	_check(viewport.get_visible_rect().size == Vector2(720, 540),
		"y la maquetacion sigue siendo la de siempre (es %s)" % viewport.get_visible_rect().size)

	# Y el caso suelto sigue por el camino de siempre.
	var loose := SubViewport.new()
	loose.size = Vector2i(1240, 928)
	root.add_child(loose)
	settings.call("_scale_subviewport", loose)
	_check(loose.size == Vector2i(620, 464),
		"un SubViewport sin contenedor se escala como siempre (es %s)" % loose.size)
	_check(loose.size_2d_override == Vector2i(1240, 928),
		"conservando su tamaño autorado como override")

	settings.graphics_render_scale = previous
	container.queue_free()
	loose.queue_free()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text


func _strip_comments(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(out)
