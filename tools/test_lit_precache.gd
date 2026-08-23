extends SceneTree

## The lit precache: the lights the scene ships dark are switched on for the
## sweep, so the shots that switch them on mid-song do not compile their
## pipelines while the player is watching.
##
## Why this file is mostly about ORDER. The same idea shipped once as `af85b29`
## and was reverted whole in `7dfa73a`, for one reason: it turned the lights on
## BEFORE `_hide_everything()`, so they came on over a scene that was still
## fully visible. Chimera's precache went 15092ms -> 38530ms with a single
## 20295ms frame, the shop's went 24402ms -> 45264ms, and the player's report
## was "rompió todo, literalmente todo el flujo de chimera". The measured
## control in the script's own KEEP_VISIBLE note says why the other order is
## free: with nothing visible, turning lights on compiles **0** pipelines.
##
## So the invariant with teeth is `_hide_everything()` first, `_force_dark_
## lights_on()` second, and nothing in between. That is checked by source
## position, and it is the check to keep if any other one here becomes
## inconvenient.
##
## The second invariant is that this reaches the RenderingServer and nothing
## else. Making the ancestor `visible` would work too and is what `af85b29`
## did - but it fires `visibility_changed` all the way down, which
## AnimationTree conditions, VisibleOnScreenNotifier3D and particle emitters
## can all see. `RS.instance_set_visible()` writes the single flag that
## `Node3D` visibility propagation writes anyway and touches nothing else.
##
## Run with:
##   godot --headless --path . --script tools/test_lit_precache.gd

const SCRIPT_PATH := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_order_checks()
	_confinement_checks()
	_behavioural_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## The one that matters. Both calls live in _ready(), and the hide has to come
## first - see the header.
func _order_checks() -> void:
	var code: String = _strip_comments(_read(SCRIPT_PATH))
	var ready_at: int = code.find("func _ready(")
	_check(ready_at >= 0, "_ready existe")
	if ready_at < 0:
		return
	var ready_body: String = code.substr(ready_at)
	ready_body = ready_body.substr(0, ready_body.find("\nfunc "))

	var hide_at: int = ready_body.find("_hide_everything()")
	var force_at: int = ready_body.find("_force_dark_lights_on()")
	_check(hide_at >= 0, "_ready sigue escondiendo la escena")
	_check(force_at >= 0, "_ready enciende las luces apagadas")
	_check(hide_at >= 0 and force_at > hide_at,
		"y lo hace DESPUES de esconderla (af85b29 lo hizo antes: 15092ms -> 38530ms)")

	var finish_at: int = code.find("func finish_preload(")
	_check(finish_at >= 0, "finish_preload existe")
	if finish_at >= 0:
		var finish_body: String = code.substr(finish_at)
		finish_body = finish_body.substr(0, finish_body.find("\nfunc "))
		var reveal_at: int = finish_body.find("_reveal(_hidden.size() - _revealed)")
		var restore_at: int = finish_body.find("_restore_forced_lights()")
		_check(restore_at >= 0, "finish_preload devuelve las luces a su sitio")
		_check(reveal_at >= 0 and restore_at > reveal_at,
			"...despues del ultimo revelado, para que ese lote tambien se caliente")


## It reaches the RenderingServer and nothing else.
func _confinement_checks() -> void:
	var code: String = _strip_comments(_read(SCRIPT_PATH))
	for fn_name: String in ["_force_dark_lights_on", "_restore_forced_lights"]:
		var at: int = code.find("func %s(" % fn_name)
		_check(at >= 0, "%s existe" % fn_name)
		if at < 0:
			continue
		var body: String = code.substr(at)
		body = body.substr(0, body.find("\nfunc "))
		_check(body.contains("RenderingServer.instance_set_visible("),
			"%s pasa por RenderingServer" % fn_name)
		_check(not body.contains(".visible = "),
			"%s no escribe visible en ningun nodo (eso dispara visibility_changed)" % fn_name)
		_check(not body.contains("get_parent()") and not body.contains("get_children()"),
			"%s no camina el arbol: solo mira _kept_lit/_forced_lit" % fn_name)

	# Y no puede ampliar el conjunto exento: si empezara a encender cosas que
	# _hide_everything no clasifico como luz, estaria revelando geometria.
	var force_at: int = code.find("func _force_dark_lights_on(")
	if force_at >= 0:
		var body: String = code.substr(force_at)
		body = body.substr(0, body.find("\nfunc "))
		_check(body.contains("for node in _kept_lit:"),
			"_force_dark_lights_on solo recorre _kept_lit, que es Light3D/LightmapGI")


func _behavioural_checks() -> void:
	var script: GDScript = load(SCRIPT_PATH)
	if script == null:
		_check(false, "el script carga")
		return

	var scene := Node3D.new()

	var lit_light := OmniLight3D.new()          # ya encendida: no se toca
	lit_light.name = "LitLight"
	scene.add_child(lit_light)

	var self_dark := OmniLight3D.new()          # apagada por el autor: se respeta
	self_dark.name = "SelfDarkLight"
	self_dark.visible = false
	scene.add_child(self_dark)

	var branch := Node3D.new()                  # rama apagada
	branch.name = "DarkBranch"
	branch.visible = false
	scene.add_child(branch)

	var dark_light := OmniLight3D.new()         # el caso: local visible, rama no
	dark_light.name = "DarkLight"
	branch.add_child(dark_light)

	var dark_mesh := MeshInstance3D.new()       # geometria bajo la misma rama
	dark_mesh.name = "DarkMesh"
	branch.add_child(dark_mesh)

	root.add_child(scene)

	var cam := Camera3D.new()
	cam.set_script(script)

	# El predicado, antes de nada: is_visible_in_tree() NO contesta esto en
	# Godot 4.7.1 - una luz bajo un Node3D con visible=false sigue diciendo
	# true, y sigue diciendolo tras sacar y volver a meter el subarbol. Si
	# alguna vez el motor lo arregla, esta comprobacion sigue pasando; lo que
	# no puede pasar es que _lit_in_tree vuelva a delegar en el.
	_check(not cam.call("_lit_in_tree", dark_light),
		"_lit_in_tree ve el ancestro apagado")
	_check(cam.call("_lit_in_tree", lit_light),
		"...y no confunde una luz encendida con una apagada")
	_check(not cam.call("_lit_in_tree", self_dark),
		"...ni una que se apago a si misma")
	if dark_light.is_visible_in_tree():
		print("  nota  is_visible_in_tree() sigue devolviendo true aqui: %s" % SCRIPT_PATH.get_file())

	cam.call("_hide_everything", scene)

	# La geometria bajo la rama apagada entra en _hidden aunque no se vea:
	# _hide_everything mira `visible` local, no is_visible_in_tree(). Eso es
	# lo que hace que encender la rama no revele nada - y por que encenderla
	# ANTES de esconder si lo revelaba todo de golpe.
	var hidden: Array = cam.get("_hidden")
	_check(hidden.has(dark_mesh),
		"la malla bajo una rama apagada tambien se esconde (por eso encender la luz no la revela)")

	var kept: Array = cam.get("_kept_lit")
	_check(kept.has(dark_light) and kept.has(lit_light),
		"las luces localmente visibles quedan exentas")
	_check(not kept.has(self_dark),
		"una luz que el autor apago no entra siquiera en el conjunto exento")

	cam.call("_force_dark_lights_on")
	var forced: Array = cam.get("_forced_lit")
	_check(forced.size() == 1 and forced.has(dark_light),
		"se fuerza solo la luz apagada por un ancestro (forzadas: %d)" % forced.size())

	var restored: int = cam.call("_restore_forced_lights")
	_check(restored == 1, "y se devuelve al terminar (devueltas: %d)" % restored)
	_check((cam.get("_forced_lit") as Array).is_empty(),
		"la lista queda vacia, asi que un segundo finish_preload no repite")

	# El caso que no se puede ver de otro modo: si la rama se ha encendido de
	# verdad mientras tanto, Node3D ya escribio true en la misma bandera y
	# apagarla dejaria una luz que la escena quiere encendida.
	cam.call("_force_dark_lights_on")
	branch.visible = true
	_check(cam.call("_restore_forced_lights") == 0,
		"si el ancestro se encendio de verdad, no se le pisa la visibilidad")

	cam.free()
	scene.queue_free()


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


## Comments in this file quote the very calls being searched for, so the
## position checks have to run against code only.
func _strip_comments(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(out)
