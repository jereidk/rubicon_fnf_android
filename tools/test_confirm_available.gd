extends SceneTree

## The overlay's confirm button only shows while pressing it would do
## something.
##
## It is one control doing two jobs. The shop swaps its action between
## "RightClick" and "ui_accept" as the state changes (env_collector_shop.gd),
## and only the first of those goes through MouseController's raycast - so
## "does this button do anything right now" has two different answers and only
## one of them is about aiming.
##
## While a menu owns the confirm - console, briefcase, notepad, Kollectadex -
## it always does something, and the raycast is not even running. While the
## player is aiming at the 3D world it does something exactly when there is
## something under the aim, which the game already says twice over: the cursor
## turns into a pointing hand and the Collector's hand points at it.
##
## The half worth pinning down is the first one. Hiding a shortcut that does
## nothing is a small win; hiding the confirm button inside a menu would
## strand the player in it, so "not casting means always available" is the
## line that must not move, including when camera or ray_cast is unset - a
## wiring mistake is not a reason to take the button away.
##
## Run with:
##   godot --headless --path . --script tools/test_confirm_available.gd

const CONTROLLER := "res://lullaby_mod/scripts/lullaby/collectors_shop/controllers/mouse_controller.gd"
const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# Never added to the tree: _ready() reaches for a shop and a hand rig this
	# double does not have, and the property under test touches neither.
	var controller: Node = Node.new()
	controller.set_script(load(CONTROLLER))

	# No camera and no ray_cast - the wiring-mistake case.
	controller.should_cast_ray = true
	controller.colliding = false
	_check("sin camara ni raycast el boton sigue estando",
		controller.confirm_is_available)

	var camera := Camera3D.new()
	var ray := RayCast3D.new()
	controller.camera = camera
	controller.ray_cast = ray

	# BUSY: the shop turns the raycast off and the button becomes a menu
	# ui_accept, which every menu here always has something to do with.
	controller.should_cast_ray = false
	controller.colliding = false
	controller.can_click = true
	_check("en un menu, sin raycast, siempre disponible",
		controller.confirm_is_available)

	controller.should_cast_ray = true
	controller.can_click = true

	controller.colliding = false
	_check("apuntando a la nada, no disponible", not controller.confirm_is_available)

	controller.colliding = true
	_check("apuntando a algo, disponible", controller.confirm_is_available)

	# can_click false is the shop saying clicks are off entirely - the same
	# thing _input() checks before it triggers anything.
	controller.can_click = false
	_check("con los clicks apagados, no disponible", not controller.confirm_is_available)

	camera.free()
	ray.free()
	controller.free()

	_scene_check()

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - Enter solo se ve cuando confirma algo")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The property is only worth anything if the scene reads it. Checked against
## the scene text rather than by loading the shop, which pulls in the whole
## room - and the failure this guards against is a NodePath that no longer
## resolves, which is a text-level mistake.
func _scene_check() -> void:
	var text: String = FileAccess.get_file_as_string(SHOP_SCENE)
	var wired: bool = text.contains('visible_property = &"confirm_is_available"')
	_check("la escena engancha el boton OK a la propiedad", wired)

	# The path is written from the button, four levels below the room's root.
	# PowerButton beside it uses the same four, which is what makes this the
	# right count rather than a guess.
	_check("y por una ruta que sale de TouchControls hasta la raiz",
		text.contains('visible_source = NodePath("../../../../MouseController")'))

	# A Node-typed @export filled from a scene only resolves if the property
	# is named in the node header's node_paths list. Left out, Godot keeps a
	# bare NodePath the script never reads and the button just never hides,
	# which is indistinguishable from never having wired it.
	_check("y declara visible_source en el node_paths del boton",
		text.contains('[node name="AcceptButton" parent="UI/Control/TouchControls" '
			+ 'index="2" node_paths=PackedStringArray("visible_source")]'))

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
