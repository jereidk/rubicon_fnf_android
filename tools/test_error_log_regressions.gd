extends SceneTree

## Tres errores del .error del dispositivo que llevaban todo el port sin tocar.
##
## Ninguno se ve jugando, y por eso siguen ahi. Los tres salen del mismo log,
## 10226-4fe0a6db, y los tres son de la misma familia: trabajo que llega en el
## momento equivocado del ciclo de vida.
##
## 1. RETIRAR UN CollisionObject DENTRO DE UN CALLBACK DE FISICA
##
##        ERROR Removing a CollisionObject node during a physics callback is not
##              allowed and will cause undesired behavior. Remove with
##              call_deferred() instead.        collision_object_3d.cpp:119
##
##    `mch_crawling._on_player_body_entered()` llega desde `body_entered`, o sea
##    desde dentro del paso de fisica, y acaba en `switch_to_gameover()`, que
##    cambia de escena - destruye el nivel entero y todos sus CollisionObject
##    mientras el servidor de fisica los esta recorriendo.
##
## 2. UN TWEEN VACIO CREADO EN UN INICIALIZADOR DE MIEMBRO
##
##        ERROR Tween (bound to .../Heart/HeartbeatController): started with no
##              Tweeners.                        tween.cpp:366
##
##    `var vignette_tween = create_tween()` a nivel de clase: nace al construirse
##    el nodo, sin Tweeners, Godot lo arranca solo y se queja. Ademas sobraba -
##    se reasigna con uno de verdad al primer latido.
##
## 3. REPRODUCIR AUDIO CON EL NODO YA FUERA DEL ARBOL
##
##        ERROR Playback can only happen when a node is inside the scene tree
##              audio_stream_player_internal.cpp:145
##
##    El `timeout` del gameover llega despues del `change_scene_to_file()` de al
##    lado, con la escena ya retirada. En el log cae a los 311.76s, cuatro
##    decimas antes del desmontaje que se mide como `vram_delta=-168.0MB`.
##
## Run with:
##   godot --headless --path . --script tools/test_error_log_regressions.gd

const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const CRAWL := "res://lullaby_mod/resources/funkin/songs/chimera/mch_crawling.gd"
const HEART := "res://lullaby_mod/scripts/lullaby/mechanics/chimera/heartbeat_controller.gd"
const OVER := "res://lullaby_mod/scripts/lullaby/gameover/chimera_gameover.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# 1
	var crawl: String = _strip_comments(_read(CRAWL))
	var body: String = _func_body(crawl, "_on_player_body_entered")
	_check(not body.is_empty(), "sigue existiendo _on_player_body_entered")
	_check(body.contains("check_completion.call_deferred()"),
		"el gameover se difiere al final del fotograma")
	_check(not body.contains("\tcheck_completion()"),
		"y ya no se llama en plena señal de fisica")

	# 2
	# Sin comentarios: la cabecera de este mismo fichero CITA la linea que
	# prohibe, y buscarla sobre el texto crudo se encuentra a si misma. Es la
	# tercera vez en esta sesion que un guard textual se cree roto por una linea
	# de prosa, asi que aqui se corta de raiz.
	var heart: String = _strip_comments(_read(HEART))
	_check(not heart.contains("var vignette_tween = create_tween()"),
		"el tween del viñeteado ya no se crea en el inicializador")
	_check(heart.contains("var vignette_tween: Tween = null"),
		"se declara vacio, tipado")
	_check(heart.contains("if vignette_tween != null and vignette_tween.is_running()"),
		"y el primer latido comprueba null antes de usarlo - sin esto seria un crash")

	# 3
	var over: String = _strip_comments(_read(OVER))
	var timeout: String = _func_body(over, "_on_timer_timeout")
	_check(not timeout.is_empty(), "sigue existiendo _on_timer_timeout")
	var guard_at: int = timeout.find("is_inside_tree()")
	var play_at: int = timeout.find(".play()")
	_check(guard_at >= 0, "comprueba estar en el arbol")
	_check(guard_at >= 0 and play_at >= 0 and guard_at < play_at,
		"y lo comprueba ANTES de reproducir, que es lo unico que sirve")

	# 4
	_animation_names_exist()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - los errores del log del dispositivo estan cerrados")
	quit(1 if _failures > 0 else 0)


## Ningun track puede pedirle a un sprite una animacion que su SpriteFrames no
## tiene.
##
## Del log del dispositivo, dos veces y en dos formas:
##
##     ERROR Animation 'Serena Walking' doesn't exist.
##           sprite_frames.cpp:72 get_frame_count
##     ERROR There is no animation with name ''.
##           animated_sprite_2d.cpp:585 set_animation
##
## El primero salia de la ultima clave de `taking_pictures`, en t=8.5 de una
## animacion que mide exactamente 8.5: se aplicaba en el instante final y dejaba
## al AnimatedSprite3D sin fotograma que dibujar. Que fuera un solo fotograma es
## la razon de que nadie lo viera jugando mientras llenaba el .error en cada
## pasada. Y la propiedad se quedaba puesta con el nombre roto, asi que cualquier
## cosa que volviera a enseñar ese nodo sin re-lanzar la secuencia desde cero lo
## enseñaba en blanco.
##
## Se comprueba resolviendo de verdad -cargar la escena, seguir el NodePath,
## mirar el SpriteFrames- en vez de buscar la cadena "Serena Walking". Un guard
## textual solo cierra el caso que ya paso; este cierra la familia, y el nombre
## vacio del segundo error tambien cae aqui.
func _animation_names_exist() -> void:
	var packed: PackedScene = load(CHIMERA)
	if not _check(packed != null, "sng_chimera.tscn carga"):
		return
	var root: Node = packed.instantiate()
	if not _check(root != null, "y se instancia"):
		return

	var bad: PackedStringArray = []
	var seen: int = 0
	for player: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
		var base: Node = player.get_node_or_null(player.root_node)
		if base == null:
			base = player
		for anim_name: StringName in player.get_animation_list():
			var anim: Animation = player.get_animation(anim_name)
			if anim == null:
				continue
			for i in anim.get_track_count():
				if anim.track_get_type(i) != Animation.TYPE_VALUE:
					continue
				var np: NodePath = anim.track_get_path(i)
				if np.get_concatenated_subnames() != "animation":
					continue
				var target: Node = base.get_node_or_null(
					NodePath(np.get_concatenated_names()))
				if target == null or not ("sprite_frames" in target):
					continue
				var frames: SpriteFrames = target.get("sprite_frames")
				if frames == null:
					continue
				for k in anim.track_get_key_count(i):
					seen += 1
					var wanted: StringName = anim.track_get_key_value(i, k)
					if not frames.has_animation(wanted):
						bad.append("%s/%s clave %d pide '%s'"
							% [player.name, anim_name, k, wanted])

	_check(seen > 0, "hay claves de :animation que revisar (%d)" % seen)
	_check(bad.is_empty(), "todas existen en su SpriteFrames%s"
		% ("" if bad.is_empty() else " - " + ", ".join(bad)))
	root.free()


## Fuera las lineas de comentario, para que una cita no cuente como codigo.
func _strip_comments(code: String) -> String:
	var out: PackedStringArray = []
	for line: String in code.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func _func_body(code: String, name: String) -> String:
	var at: int = code.find("func %s(" % name)
	if at < 0:
		return ""
	var next: int = code.find("\nfunc ", at + 1)
	return code.substr(at, -1 if next < 0 else next - at)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
