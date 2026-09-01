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
	_handover_checks()

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

	# El predicado, antes de nada, y por que no es is_visible_in_tree().
	#
	# El motor contesta lo mismo EN EJECUCION. Lo que no hace es contestarlo
	# fuera del arbol: Node3D cachea su padre 3D en ENTER_TREE, y bajo --script
	# el arbol no esta montado hasta que _initialize() termina. Medido sobre la
	# misma luz, antes y despues de montarlo:
	#
	#     dentro=false   is_visible_in_tree()=true    walk=false
	#     dentro=true    is_visible_in_tree()=false   walk=false
	#
	# O sea que la version de esta comprobacion que preguntaba al motor pasaba
	# por accidente, y habria seguido pasando con la seleccion invertida. El
	# recorrido explicito contesta igual en los dos estados, que es lo que hace
	# que esto se pueda comprobar.
	_check(not dark_light.is_inside_tree(),
		"(aqui los nodos aun no estan dentro del arbol, que es justo el caso)")
	_check(not cam.call("_lit_in_tree", dark_light),
		"_lit_in_tree ve el ancestro apagado")
	_check(cam.call("_lit_in_tree", lit_light),
		"...y no confunde una luz encendida con una apagada")
	_check(not cam.call("_lit_in_tree", self_dark),
		"...ni una que se apago a si misma")

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


## La entrega, y de que ha dejado de depender.
##
## Del log del 2026-08-24, en la tienda: el plazo vence a los 64.11s, revela
## los 116 nodos que faltaban y llama a _try_finish()... que se niega. La
## entrega llega a los 99.12s, cuando termina una animacion autorada en 1.0
## segundos que no hace bucle. Treinta y cinco segundos esperando algo que ya
## no podia cambiar nada: la animacion existe para pasear la camara y que cada
## material se dibuje, y con los 116 revelados no le queda a quien revelarselos.
## `revelado_al_fin_anim=116/116` es lo que prueba el orden.
func _handover_checks() -> void:
	var code: String = _strip_comments(_read(SCRIPT_PATH))

	var try_body: String = _func_body(code, "_try_finish")
	_check(not try_body.contains("_anim_done"),
		"_try_finish ya no espera a la animacion")
	_check(try_body.contains("_revealed >= _hidden.size()"),
		"...pero sigue exigiendo que todo este revelado, que es la parte que protege")

	# El plazo, medido desde que la camara puede trabajar y no desde el
	# escondite: en ese mismo log, 11695ms de un presupuesto de 15000 se fueron
	# antes del primer _process, y el barrido revelo 2 de 116.
	var proc_body: String = _func_body(code, "_process")
	_check(proc_body.contains("_budget_msec = Time.get_ticks_msec()"),
		"el presupuesto arranca en el primer _process")
	# `_deadline_msec` y no `int(DEADLINE_SECONDS * 1000.0)`: el plazo vive ahora
	# en una variable, para que test_sweep_covers_every_sequence.gd pueda
	# vencerlo sin esperar quince segundos de reloj. Lo que esta linea fija es
	# contra QUE se mide - `_budget_msec`, el primer _process - y eso no cambia.
	_check(proc_body.contains("Time.get_ticks_msec() - _budget_msec >= _deadline_msec"),
		"...y el plazo se mide contra el, no contra el escondite")
	_check(not proc_body.contains("Time.get_ticks_msec() - _started_msec >= _deadline_msec"),
		"...ya no contra _started_msec, que incluye el arbol bloqueado")

	# Y la instrumentacion que contesta por que una animacion de 1s no terminaba.
	var progress: String = _func_body(code, "_animation_progress")
	for what: String in ["current_animation_position", "is_playing()", "_anim_done"]:
		_check(progress.contains(what), "el log dice %s de la animacion" % what)
	_check(code.count("_animation_progress()") >= 3,
		"y se imprime al vencer el plazo Y al entregar (%d usos)"
			% code.count("_animation_progress()"))


## The body of a top-level function, anchored at column 0.
func _func_body(text: String, name: String) -> String:
	var head: int = -1
	var from: int = 0
	while true:
		var at: int = text.find("func %s(" % name, from)
		if at < 0:
			break
		if at == 0 or text[at - 1] == "\n":
			head = at
			break
		from = at + 1
	if head < 0:
		_check(false, "%s() existe al nivel superior" % name)
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
