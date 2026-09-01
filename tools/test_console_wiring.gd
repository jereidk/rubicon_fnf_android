extends SceneTree

## Everything the Collector's Shop reaches into the console by, pinned after
## the console was deferred.
##
## The console was pulled out of the shop scene's initial load and mounted at
## runtime by console_deferred_loader.gd, saving 102 resources and 376ms from
## a cold load that is bound by per-file cost. This guard verifies the new
## wiring survives refactoring: the loader exists with its six cables, the
## shop's exports and animation tracks still point at the right paths, the
## packed console scene carries the full tree, and nothing below TabContainer
## is crossed from inside it.
##
## What makes that change dangerous is not the size, it is the failure mode.
## Twelve things in env_collector_shop.tscn point INTO the console, and none of
## them raises anything when the target is missing:
##
##   * five node exports - a null export just leaves a handler doing nothing
##   * six animation tracks across four shop sequences, driving
##     `Console:input_active`, `Console/Music:volume_db` and
##     `Console/Music/MusicFader`. A track whose node is absent is dropped
##     silently, so the console's music would stop fading and its input would
##     stop being gated during those sequences, with no error anywhere
##   * and the console points back OUT, through three node_paths of its own
##
## With inline loading these all failed silently; with deferred loading they
## work because the loader mounts the console before the first sequence runs.
## This guard pins that contract.
##
## Run with:
##   godot --headless --path . --script tools/test_console_wiring.gd

const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const CONSOLE_PACKED := "res://lullaby_mod/resources/console/console_shop.tscn"

## The six cables the deferred loader re-wires.
const LOADER_WIRES: Array[String] = [
	"shop", "sequences", "focus_right_area",
	"viewport_gate", "console_sfx", "mixer_root",
]

## The exports in the shop scene that resolve to the console, as
## (owning node, property).
const EXPORTS := [
	["CollectorShop", "console"],
	["Environment/Areas/FocusConsole", "console"],
	["Environment/Areas/FocusPowerConsole", "console"],
	["UI/Control/TouchControls", "force_active_source"],
	["UI/Control/TouchControls/SwitchCartridgeButton", "visible_source"],
]

## The properties shop animations drive inside the console. These are the ones
## that fail silently and the reason this file is not optional.
const ANIMATED := [
	"Console:input_active",
	"Console/Music:volume_db",
	"Console/Music/MusicFader",
]

## The deepest the shop ever reaches. Anything below this can move.
const SPLIT_POINT := "Console/Music/MusicFader"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var shop: String = _read(SHOP_SCENE)

	# --- 1. The console is NO LONGER inline. ---
	_check(not shop.contains('[node name="Console" parent="Viewports/ConsoleSubViewport"'),
		"la consola NO esta inline (deferred)")

	# --- 2. The deferred loader is present with its six wires. ---
	var loader_block: String = _node_block(shop, "Viewports/ConsoleSubViewport/ConsoleLoader")
	_check(not loader_block.is_empty(), "ConsoleLoader existe en la escena")
	_check(loader_block.contains("script ="),
		"ConsoleLoader tiene script asignado")
	for wire: String in LOADER_WIRES:
		_check(loader_block.contains("%s = NodePath(" % wire),
			"...con %s enganchado" % wire)

	# --- 3. The packed console scene exists and is complete. ---
	_check(ResourceLoader.exists(CONSOLE_PACKED), "console_shop.tscn existe")
	var packed: PackedScene = load(CONSOLE_PACKED)
	if _check(packed != null, "y se carga"):
		var node: Node = packed.instantiate()
		var n: int = _count(node)
		_check(n >= 350, "con la consola entera dentro (%d nodos)" % n)
		_check(node is Control, "y su raiz sigue siendo un Control")
		node.free()

	# --- 4. The shop's exports still point at the console path. ---
	for pair in EXPORTS:
		var owner: String = pair[0]
		var property: String = pair[1]
		var block: String = _node_block(shop, owner)
		var wired: bool = block.contains("%s = NodePath(\"" % property) \
			and block.find("ConsoleSubViewport/Console", block.find("%s = NodePath(" % property) >= 0)
		_check(wired, "%s.%s sigue apuntando a la consola" % [owner.get_file(), property])

	# --- 5. The shop's animations still reference the console path. ---
	for target: String in ANIMATED:
		var found: int = shop.count("ConsoleSubViewport/%s" % target)
		_check(found > 0,
			"alguna animacion sigue moviendo %s (%d pistas)" % [target, found])

	# --- 6. The deepest reference is still Console/Music/MusicFader. ---
	_check(shop.contains("ConsoleSubViewport/%s" % SPLIT_POINT),
		"la referencia mas profunda por NodePath sigue siendo %s" % SPLIT_POINT)

	# --- 7. TabContainer checks hold in the packed scene. ---
	var packed_text: String = FileAccess.get_file_as_string(CONSOLE_PACKED)
	var crossing: PackedStringArray = []
	for m in RegEx.create_from_string('NodePath\\("([^"]*TabContainer[^"]*)"\\)').search_all(packed_text):
		var t: String = m.get_string(1)
		if t.contains("TabContainer/"):
			crossing.append(t)
	_check(crossing.is_empty(),
		"dentro de la consola nadie apunta por debajo del TabContainer (%d cruces%s)"
			% [crossing.size(), "" if crossing.is_empty() else ": " + ", ".join(crossing.slice(0, 3))])
	var under: int = 0
	for m in RegEx.create_from_string('(?m)^\\[node name="[^"]*"[^\\]]*parent="TabContainer').search_all(packed_text):
		under += 1
	_check(under > 100,
		"y el TabContainer sigue siendo el bulto: %d nodos bajo el" % under)

	# --- 8. No stale overrides remain in the shop targeting the removed console. ---
	var stale: int = 0
	for m in RegEx.create_from_string(
			'(?m)^\\[node name="[^"]*"[^\\]]*parent="Viewports\\/ConsoleSubViewport\\/Console'
			).search_all(shop):
		stale += 1
	_check(stale == 0,
		"la tienda ya no sobreescribe nodos dentro de la consola (%d restantes)" % stale)

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n


func _node_block(scene: String, path: String) -> String:
	var n: String = path.get_file()
	var p: String = path.get_base_dir()
	var head: int = -1
	if p.is_empty():
		head = scene.find('[node name="%s"' % n)
	else:
		var re := RegEx.create_from_string(
			'(?m)^\\[node name="%s"[^\\]]*parent="%s"' % [n, p.replace("/", "\\/")])
		var m: RegExMatch = re.search(scene)
		head = m.get_start() if m != null else -1
	if head < 0:
		_check(false, "el nodo %s existe en la escena" % path)
		return ""
	var tail: int = scene.find("\n[", head + 1)
	return scene.substr(head, (tail - head) if tail > head else -1)


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
