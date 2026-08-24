extends SceneTree

## Everything the Collector's Shop reaches into the console by, pinned before
## the console is ever deferred.
##
## Why this exists ahead of the change it guards: `console.tscn` drags 116 of
## the room's 363 files - 32% of a cold load that is bound by per-file cost -
## and the room does not need any of it to appear. Loading it on first open is
## the largest remaining win on a shop entry users measure in minutes.
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
## So this fixes the contract first. Every path below has to keep resolving,
## whatever shape the console ends up in.
##
## It also records why that change is NOT a rewiring job. The shop does not
## only point into the console - it OVERRIDES twenty nodes inside it from
## outside, fourteen of them below TabContainer, as deep as
## `TabContainer/Home/IconSubViewport/SubViewport/ui_credits/UI_Icons`. Godot
## resolves those against the instanced scene at load, so moving the subtree
## into a later-instanced scene drops them all, silently.
##
## Text, not instantiation, on purpose: neither scene can be loaded in a
## checkout with an incomplete import, and re-importing this one is killed for
## memory. The paths are what matter and they are all readable as strings.
##
## Run with:
##   godot --headless --path . --script tools/test_console_wiring.gd

const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const CONSOLE_SCENE := "res://lullaby_mod/resources/console/console.tscn"

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
	var console: String = _read(CONSOLE_SCENE)

	_check(shop.contains('[node name="Console" parent="Viewports/ConsoleSubViewport"'),
		"la consola sigue colgando de Viewports/ConsoleSubViewport")

	for pair in EXPORTS:
		var owner: String = pair[0]
		var property: String = pair[1]
		var block: String = _node_block(shop, owner)
		var wired: bool = block.contains("%s = NodePath(\"" % property) \
			and block.find("ConsoleSubViewport/Console", block.find("%s = NodePath(\"" % property)) >= 0
		_check(wired, "%s.%s sigue apuntando a la consola" % [owner.get_file(), property])

	for target: String in ANIMATED:
		var found: int = shop.count("ConsoleSubViewport/%s" % target)
		_check(found > 0,
			"alguna animacion sigue moviendo %s (%d pistas)" % [target, found])

	# Y hacia fuera: la consola necesita que la tienda le llegue.
	var console_node: String = _node_block(shop, "Viewports/ConsoleSubViewport/Console")
	for back: String in ["shop", "sequences", "focus_right_area"]:
		_check(console_node.contains(back),
			"la consola sigue recibiendo `%s` de la tienda" % back)

	_split_checks(shop, console)

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## The measurements that say where the console can be cut, so a future split is
## checked against the scene rather than against this file's memory of it.
func _split_checks(shop: String, console: String) -> void:
	_check(shop.contains("ConsoleSubViewport/%s" % SPLIT_POINT),
		"la referencia mas profunda por NodePath sigue siendo %s" % SPLIT_POINT)

	# And the thing that actually blocks the split, which this file found by
	# asserting the opposite and being wrong.
	#
	# The shop does not merely point into the console - it OVERRIDES nodes
	# inside it, from outside, the way an inherited scene does: twenty node
	# blocks with `parent="Viewports/ConsoleSubViewport/Console/..."`, fourteen
	# of them below TabContainer, reaching as deep as
	# `TabContainer/Home/IconSubViewport/SubViewport/ui_credits/UI_Icons`.
	#
	# Godot resolves those overrides against the instanced scene at load. Move
	# the TabContainer into a scene instanced later and every one of them has
	# nothing to attach to - dropped, with no error. So deferring the console
	# is not a matter of rewiring five exports and six animation tracks; the
	# room is authored INTO the console's tree, and that has to be undone first.
	#
	# Counted rather than described, so the day somebody does untangle it this
	# number moves and says so.
	var overrides: int = 0
	for m in RegEx.create_from_string(
			'(?m)^\\[node name="[^"]*"[^\\]]*parent="Viewports\\/ConsoleSubViewport\\/Console'
			).search_all(shop):
		overrides += 1
	_check(overrides == 20,
		"la tienda sigue sobreescribiendo %d nodos dentro de la consola" % overrides)

	var crossing: int = 0
	for m in RegEx.create_from_string('NodePath\\("([^"]*TabContainer[^"]*)"\\)').search_all(console):
		if m.get_string(1) != "TabContainer":
			crossing += 1
	_check(crossing == 0,
		"dentro de la consola nadie apunta por debajo del TabContainer (%d cruces)" % crossing)

	var under: int = 0
	for m in RegEx.create_from_string('(?m)^\\[node name="[^"]*"[^\\]]*parent="TabContainer').search_all(console):
		under += 1
	_check(under > 100,
		"y el TabContainer sigue siendo el bulto: %d nodos bajo el" % under)


## The `[node ...]` header plus its properties, for the node at `path`.
func _node_block(scene: String, path: String) -> String:
	var name: String = path.get_file()
	var parent: String = path.get_base_dir()
	var head: int = -1
	if parent.is_empty():
		head = scene.find('[node name="%s"' % name)
	else:
		var re := RegEx.create_from_string(
			'(?m)^\\[node name="%s"[^\\]]*parent="%s"' % [name, parent.replace("/", "\\/")])
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
