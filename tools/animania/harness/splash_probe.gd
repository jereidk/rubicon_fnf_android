# El salpicon de notas contra los numeros del binario.
#
# La duda era si el arte era el equivocado. No lo es: noteSplashes.png del puerto es
# IDENTICO byte a byte al de assets/images/ui/notes/amtake_base del mod, con los mismos
# prefijos y los mismos 4 fotogramas por variante. Lo que estaba mal era como se dibuja.
#
# Esto comprueba lo que se puede comprobar sin jugar: que el sprite nace con la alfa del
# mod, que la escala y la variacion de giro son las del notestyle, y que estan las ocho
# animaciones -dos variantes por carril- con sus cuatro fotogramas.
#
#   godot --headless --path . --script tools/animania/harness/splash_probe.gd
extends SceneTree

const LANE := "res://animania_mod/notestyle/Lane.tscn"
const EFFECTS := "res://animania_mod/notestyle/amtake_effects_frames.tres"
## amtake-base.json: noteSplash.scale y noteSplash.data.rotationVariance.
const JSON_SCALE := 0.9
const JSON_ROTATION_VARIANCE := 180.0
## Del boot de NoteSplash: ALPHA en 0x8092c58, FRAMERATE_DEFAULT y FRAMERATE_VARIANCE.
const BIN_ALPHA := 0.6
const BIN_FPS := 24.0
const BIN_FPS_VARIANCE := 2.0

var _bad: int = 0


func _init() -> void:
	# Por `root.ready` y no aqui mismo: en un script de SceneTree, `_init` corre antes de
	# que la raiz este en el arbol, asi que un `add_child` de ahi NO dispara el `_ready` del
	# hijo hasta el frame siguiente. Sin esto el arnes miraba un nodo que todavia no habia
	# creado nada y culpaba al codigo.
	root.ready.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var lane: Node = (load(LANE) as PackedScene).instantiate()
	root.add_child(lane)
	await process_frame
	var fx: Node2D = lane.get_node("Effects")
	var consts: Dictionary = fx.get_script().get_script_constant_map()

	_check(is_equal_approx(consts["SPLASH_ALPHA"], BIN_ALPHA),
		"alfa %s, el binario dice %s" % [consts["SPLASH_ALPHA"], BIN_ALPHA])
	_check(is_equal_approx(consts["SPLASH_SCALE"], JSON_SCALE),
		"escala %s, el notestyle dice %s" % [consts["SPLASH_SCALE"], JSON_SCALE])
	_check(is_equal_approx(consts["ROTATION_VARIANCE"], JSON_ROTATION_VARIANCE),
		"giro %s, el notestyle dice %s" % [consts["ROTATION_VARIANCE"],
			JSON_ROTATION_VARIANCE])
	_check(is_equal_approx(consts["SPLASH_FPS"], BIN_FPS)
		and is_equal_approx(consts["SPLASH_FPS_VARIANCE"], BIN_FPS_VARIANCE),
		"fps %s+-%s, el binario dice %s+-%s" % [consts["SPLASH_FPS"],
			consts["SPLASH_FPS_VARIANCE"], BIN_FPS, BIN_FPS_VARIANCE])

	# El sprite de verdad, no solo la constante.
	var splash: AnimatedSprite2D = null
	for child: Node in fx.get_children():
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).z_index == 0:
			splash = child as AnimatedSprite2D
			break
	if splash == null:
		print("OUT FALLO: el nodo de efectos no ha creado el sprite del salpicon")
		_bad += 1
	else:
		_check(is_equal_approx(splash.modulate.a, BIN_ALPHA),
			"el sprite nace con alfa %.2f" % splash.modulate.a)
		_check(splash.scale.is_equal_approx(Vector2.ONE * JSON_SCALE),
			"el sprite nace a escala %s" % str(splash.scale))

	var effects: SpriteFrames = load(EFFECTS)
	for direction: String in ["left", "down", "up", "right"]:
		for variant: int in [1, 2]:
			var name := "splash_%s_%d" % [direction, variant]
			var ok: bool = effects.has_animation(name) \
				and effects.get_frame_count(name) == 4
			_check(ok, "%s con 4 fotogramas" % name)

	print("OUT fallos=%d" % _bad)
	quit()


func _check(ok: bool, detail: String) -> void:
	if not ok:
		_bad += 1
	print("OUT %-58s %s" % [detail, "OK" if ok else "FALLO"])
