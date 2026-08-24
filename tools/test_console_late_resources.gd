extends SceneTree

## The console's tab resources are held by path, and every one of them still
## resolves to a real node, a real file and a real animation.
##
## Why they moved: the Collector's Shop cold load is bound by per-file cost -
## about 53ms a file on the device, which is how a room of 363 files becomes
## the two-minute entry users report - and console.tscn was 118 of those files.
## Thirty of its ext_resources are reached only from inside a tab, and a tab
## cannot be seen until the player navigates to one: the TabContainer is
## authored at modulate.a = 0 and only change_tab() raises it. Measured against
## the room's real dependency graph, moving them out took it to 332 files.
##
## Why this file has to exist: every failure mode of that change is silent.
##
##   * a key naming a node that is not there applies nothing, and the tab just
##     renders without its icon
##   * a path with a typo is a string nobody validates at import time
##   * and the one that is not obvious at all: assigning `animation` to an
##     AnimatedSprite2D whose sprite_frames is null does NOT keep the value.
##     Godot pushes a red error, clears the property and remembers the name
##     internally. It does come back when the frames arrive, so the scene may
##     not author it any more - it has to travel in the table instead, and the
##     name in the table has to be one the sheet actually has.
##
## The animation names are checked against the loaded SpriteFrames rather than
## against a list here, so renaming an animation in the sheet fails this
## instead of failing quietly on the device.
##
## Run with:
##   godot --headless --path . --script tools/test_console_late_resources.gd

const SCENE := "res://lullaby_mod/resources/console/console.tscn"
const SCRIPT := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/console_late_resources.gd"
const CONTAINER := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/console_tab_container.gd"

## What the table held when this was written. Pinned so that shrinking it back
## - the easy way to "fix" a failure here - has to be deliberate.
const EXPECTED_ENTRIES := 43
const EXPECTED_RESOURCES := 30

var _failures: int = 0
var _checks: int = 0

var _scene: String = ""
var _deferred: Dictionary = {}
var _animations: Dictionary = {}
var _autoplay: PackedStringArray = []

## Set by the last line of _behaviour_checks. A runtime error in GDScript
## abandons the function it happens in and returns to the caller, so without
## this a section that blew up halfway looks exactly like a section that
## passed - which is what the first run of this file did.
var _behaviour_done: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_scene = _read(SCENE)
	_deferred = _parse_map("deferred = Dictionary[String, String]({")
	_animations = _parse_map("sprite_animations = Dictionary[String, StringName]({")
	_autoplay = _parse_array("sprite_autoplay = Array[String]([")

	_table_checks()
	_scene_checks()
	_animation_checks()
	_wiring_checks()
	await _behaviour_checks()
	_check(_behaviour_done, "las comprobaciones de comportamiento llegaron al final")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _table_checks() -> void:
	_check(_deferred.size() == EXPECTED_ENTRIES,
		"la tabla lleva %d entradas (lleva %d)" % [EXPECTED_ENTRIES, _deferred.size()])

	var resources: Dictionary = {}
	for key: String in _deferred:
		resources[_deferred[key]] = true
	_check(resources.size() == EXPECTED_RESOURCES,
		"para %d recursos distintos (hay %d)" % [EXPECTED_RESOURCES, resources.size()])

	# Cada clave tiene que ser nodo Y propiedad, o set() no tiene a que apuntar.
	var shapeless: PackedStringArray = []
	for key: String in _deferred:
		if not key.contains(":") or NodePath(key).get_concatenated_subnames().is_empty():
			shapeless.append(key)
	_check(shapeless.is_empty(), "cada clave es `nodo:propiedad`%s"
		% ["" if shapeless.is_empty() else ": " + ", ".join(shapeless.slice(0, 3))])

	# Y cada ruta tiene que existir. Es una cadena: nadie la valida al importar,
	# y un fallo aqui es un icono que no aparece meses despues.
	var missing: PackedStringArray = []
	for path: String in resources:
		if not ResourceLoader.exists(path):
			missing.append(path.get_file())
	_check(missing.is_empty(), "las %d rutas existen%s"
		% [resources.size(), "" if missing.is_empty() else ": " + ", ".join(missing)])


func _scene_checks() -> void:
	# Lo que da el ahorro: la escena ya no las declara como dependencia.
	var still: PackedStringArray = []
	for key: String in _deferred:
		var path: String = _deferred[key]
		if _scene.contains('path="%s" id=' % path):
			still.append(path.get_file())
	_check(still.is_empty(), "ningun ext_resource las declara ya%s"
		% ["" if still.is_empty() else ": " + ", ".join(still.slice(0, 3))])

	# Y los nodos siguen ahi: la sala sobreescribe veinte de ellos desde fuera
	# (tools/test_console_wiring.gd), asi que mover el subarbol no es opcion -
	# solo se mueven los recursos colgados de el.
	var orphans: PackedStringArray = []
	var authored: PackedStringArray = []
	for key: String in _deferred:
		var node_path: String = String(NodePath(key).get_concatenated_names())
		var property: String = String(NodePath(key).get_concatenated_subnames())
		var block: String = _node_block("TabContainer/" + node_path)
		if block.is_empty():
			orphans.append(node_path)
			continue
		if block.contains("\n%s = " % property):
			authored.append(key)
	_check(orphans.is_empty(), "todas las claves apuntan a un nodo real%s"
		% ["" if orphans.is_empty() else ": " + ", ".join(orphans.slice(0, 3))])
	_check(authored.is_empty(),
		"y la escena ya no escribe esas propiedades a mano%s"
			% ["" if authored.is_empty() else ": " + ", ".join(authored.slice(0, 3))])


func _animation_checks() -> void:
	_check(not _animations.is_empty(), "hay animaciones que restaurar (%d)" % _animations.size())

	var no_sheet: PackedStringArray = []
	var unknown: PackedStringArray = []
	var still_authored: PackedStringArray = []
	for node_path: String in _animations:
		var key: String = node_path + ":sprite_frames"
		if not _deferred.has(key):
			no_sheet.append(node_path)
			continue

		# El fallo silencioso que justifica la mitad de este fichero: si el
		# .tscn sigue escribiendo animation/autoplay con sprite_frames a null,
		# Godot suelta un error rojo por nodo en cada carga de la sala.
		var block: String = _node_block("TabContainer/" + node_path)
		if block.contains("\nanimation = ") or block.contains("\nautoplay = "):
			still_authored.append(node_path)

		var sheet: SpriteFrames = ResourceLoader.load(_deferred[key]) as SpriteFrames
		if sheet == null:
			continue
		if not sheet.has_animation(StringName(_animations[node_path])):
			unknown.append("%s -> \"%s\"" % [node_path.get_file(), _animations[node_path]])

	_check(no_sheet.is_empty(), "cada animacion acompana a su sprite_frames diferido%s"
		% ["" if no_sheet.is_empty() else ": " + ", ".join(no_sheet.slice(0, 3))])
	_check(still_authored.is_empty(),
		"y la escena ya no las escribe (error rojo por nodo si lo hiciera)%s"
			% ["" if still_authored.is_empty() else ": " + ", ".join(still_authored.slice(0, 3))])
	_check(unknown.is_empty(), "y cada nombre existe en su hoja%s"
		% ["" if unknown.is_empty() else ": " + ", ".join(unknown.slice(0, 3))])

	var stray: PackedStringArray = []
	for node_path: String in _autoplay:
		if not _animations.has(node_path):
			stray.append(node_path)
	_check(stray.is_empty(), "y los %d autoplay son un subconjunto%s"
		% [_autoplay.size(), "" if stray.is_empty() else ": " + ", ".join(stray)])


func _wiring_checks() -> void:
	var node: String = _node_block("LateResources")
	_check(node.contains("console_late_resources.gd") or node.contains("script = ExtResource"),
		"el nodo LateResources lleva su script")
	_check(node.contains('node_paths=PackedStringArray("tab_root")')
			and node.contains('tab_root = NodePath("TabContainer")'),
		"y apunta al TabContainer, que es a lo que son relativas las claves")

	var container: String = _node_block("TabContainer")
	_check(container.contains('"late_resources"'),
		"el TabContainer declara late_resources en node_paths, o llega en null")
	_check(container.contains('late_resources = NodePath("../LateResources")'),
		"...y lo tiene cableado")

	var code: String = _read(CONTAINER)
	var change: String = _func_body(code, "change_tab")
	var dress_at: int = change.find("_dress(")
	var show_at: int = change.find("modulate.a = 1")
	_check(dress_at >= 0 and show_at > dress_at,
		"change_tab viste la pestana ANTES de subirle el alpha")
	_check(_func_body(code, "_on_tab_changed").contains("_dress("),
		"y el cambio de pestana tambien la viste")

	# Por nombre de nodo, no por tabs_array: esa lista es el texto de cabecera y
	# dice "Codes" donde el hijo se llama "Hacks", asi que indexarla dejaria una
	# pestana entera sin vestir y nada lo diria.
	var dress: String = _func_body(code, "_dress")
	_check(dress.contains("get_child(tab)") and dress.contains(".name"),
		"y lo hace por el nombre del hijo, no por tabs_array")
	_check(not dress.contains("tabs_array"), "...que dice \"Codes\" donde el nodo es \"Hacks\"")

	_check(code.contains("@export var late_resources: ConsoleLateResources"),
		"el export esta tipado")


## The part that cannot be read off the text: that applying actually works.
func _behaviour_checks() -> void:
	var script: GDScript = load(SCRIPT)
	_check(script != null, "console_late_resources.gd compila")
	if script == null:
		return

	var font_path := "res://lullaby_mod/resources/fonts/fnt_funkin.ttf"
	var sheet_path := "res://lullaby_mod/assets/menus/console/cartridge/spr_cartridge_name.tres"

	var tabs := Node.new()
	tabs.name = "TabRoot"
	var home := Node.new()
	home.name = "Home"
	var label := Label.new()
	label.name = "Label"
	home.add_child(label)
	var cartridges := Node.new()
	cartridges.name = "Cartridges"
	# Dos, porque los dos casos reales son distintos: Cartridges/Name y
	# SettingsPortraits llevan `animation` sin autoplay, y si el unico sujeto de
	# prueba autoplayase, play() pondria la animacion por su cuenta y taparia el
	# fallo de no restaurarla. (Lo hizo: esta version existe porque quitar
	# `node.animation = animation` no rompia nada.)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Name"
	cartridges.add_child(sprite)
	var auto_sprite := AnimatedSprite2D.new()
	auto_sprite.name = "Auto"
	cartridges.add_child(auto_sprite)
	tabs.add_child(home)
	tabs.add_child(cartridges)

	var late: Node = script.new()
	late.tab_root = tabs
	# Tipados a mano: un literal suelto no se puede asignar a un
	# Dictionary[String, String], y en GDScript eso aborta la funcion sin
	# tocar el contador de fallos - que es como la primera version de este
	# fichero llego a imprimir "todo OK" sin haber probado nada. De ahi
	# tambien _behaviour_done.
	var table: Dictionary[String, String] = {
		"Home/Label:theme_override_fonts/font": font_path,
		"Cartridges/Name:sprite_frames": sheet_path,
		"Cartridges/Auto:sprite_frames": sheet_path,
	}
	var anims: Dictionary[String, StringName] = {
		"Cartridges/Name": &"girlfriend",
		"Cartridges/Auto": &"serena",
	}
	var autoplay: Array[String] = ["Cartridges/Auto"]
	late.deferred = table
	late.sprite_animations = anims
	late.sprite_autoplay = autoplay

	root.add_child(tabs)
	root.add_child(late)
	await process_frame

	# Una pestana se viste entera y sola: la otra sigue pendiente.
	late.flush_tab(&"Home")
	# has_theme_font_override y no get_theme_font: lo segundo devuelve la fuente
	# por defecto del tema aunque no se haya asignado nada, asi que pasaria
	# tambien con la tabla vacia.
	_check(label.has_theme_font_override("font"), "flush_tab viste su pestana")
	_check(sprite.sprite_frames == null,
		"...y solo la suya, la otra sigue pendiente")

	late.flush_tab(&"Cartridges")
	_check(sprite.sprite_frames != null, "y la segunda pestana tambien se viste")
	_check(String(sprite.animation) == "girlfriend",
		"restaurando la animacion que la escena ya no escribe (es '%s')" % sprite.animation)
	_check(not sprite.is_playing(), "...sin arrancar la que no era de autoplay")
	_check(String(auto_sprite.animation) == "serena" and auto_sprite.is_playing(),
		"y arrancando la que si, que autoplay contra una hoja nula no lo hace")

	# Y el goteo de fondo, que es lo que cubre cualquier camino que no pase por
	# change_tab: sin tocar nada mas, lo pendiente se aplica solo.
	var drip: Node = script.new()
	var sprite2 := AnimatedSprite2D.new()
	sprite2.name = "Name"
	var holder := Node.new()
	holder.name = "Cartridges"
	holder.add_child(sprite2)
	var root2 := Node.new()
	root2.name = "TabRoot2"
	root2.add_child(holder)
	drip.tab_root = root2
	var drip_table: Dictionary[String, String] = {"Cartridges/Name:sprite_frames": sheet_path}
	drip.deferred = drip_table
	root.add_child(root2)
	root.add_child(drip)
	await process_frame
	await process_frame
	_check(sprite2.sprite_frames != null, "y el goteo de fondo lo aplica sin que nadie lo pida")

	tabs.queue_free()
	late.queue_free()
	root2.queue_free()
	drip.queue_free()
	_behaviour_done = true


## The `[node ...]` header plus its properties, for the node at `path`.
func _node_block(path: String) -> String:
	var name: String = path.get_file()
	var parent: String = path.get_base_dir()
	var head: int = -1
	if parent.is_empty():
		var re_root := RegEx.create_from_string('(?m)^\\[node name="%s"(?![^\\]]*parent=)' % name)
		var root_match: RegExMatch = re_root.search(_scene)
		if root_match == null:
			var re_top := RegEx.create_from_string(
				'(?m)^\\[node name="%s"[^\\]]*parent="\\."' % name)
			var top: RegExMatch = re_top.search(_scene)
			head = top.get_start() if top != null else -1
		else:
			head = root_match.get_start()
	else:
		var re := RegEx.create_from_string('(?m)^\\[node name="%s"[^\\]]*parent="%s"'
			% [name, parent.replace("/", "\\/")])
		var m: RegExMatch = re.search(_scene)
		head = m.get_start() if m != null else -1
	if head < 0:
		return ""
	var tail: int = _scene.find("\n[", head + 1)
	return _scene.substr(head, (tail - head) if tail > head else -1)


## The dictionary literal that starts at `prefix`, out of the .tscn.
func _parse_map(prefix: String) -> Dictionary:
	var head: int = _scene.find(prefix)
	if head < 0:
		_check(false, "la escena declara `%s`" % prefix.get_slice(" ", 0))
		return {}
	var from: int = _scene.find("{", head)
	var to: int = _scene.find("})", from)
	var out: Dictionary = {}
	for m in RegEx.create_from_string('"([^"]+)"\\s*:\\s*&?"([^"]*)"').search_all(
			_scene.substr(from + 1, to - from - 1)):
		out[m.get_string(1)] = m.get_string(2)
	return out


func _parse_array(prefix: String) -> PackedStringArray:
	var head: int = _scene.find(prefix)
	if head < 0:
		_check(false, "la escena declara `%s`" % prefix.get_slice(" ", 0))
		return []
	var to: int = _scene.find("])", head)
	var out: PackedStringArray = []
	for m in RegEx.create_from_string('"([^"]+)"').search_all(
			_scene.substr(head + prefix.length(), to - head - prefix.length())):
		out.append(m.get_string(1))
	return out


## The body of the top-level function `name`, anchored at column 0.
func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	while head > 0 and text[head - 1] != "\n":
		head = text.find("func %s(" % name, head + 1)
	if head < 0:
		_check(false, "%s() existe" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


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
