extends SceneTree

## La cutscene MonoCloseup de Monochrome la dibuja un vídeo, y sigue cableada.
##
## Se eligió midiendo, no a ojo: la ventana va de 266.5s a 294.6s y el chart de
## Monochrome tiene 800 notas del jugador, NINGUNA dentro. Es un interludio de
## 28.8 segundos que nadie puede alterar. La misma medida descartó al
## BloodCutscene de al lado, donde caen 45 notas dentro de sus 12.2s y los
## personajes llevan `singing_should_sing`.
##
## Dibujarla costaba 44.5 MB de textura repartidos en ~35 nodos. El clip son
## 5.8 MB.
##
## Lo que se comprueba aquí es lo que rompería la cutscene sin que nada falle
## al arrancar:
##
##   la raíz sigue llamándose MonoCloseup y siendo AspectRatioContainer. La
##     canción entra en esta escena por NodePath -"../MonoCloseup/Cutscene"- así
##     que renombrarla o cambiarle el tipo corta el disparador DESDE FUERA, y el
##     fallo aparecería en la canción, no aquí;
##
##   el AnimationPlayer `Cutscene` conserva una animación llamada `cutscene`,
##     que es el nombre del clip que la canción dispara;
##
##   esa animación tiene una pista de MÉTODO que llama a play() sobre el
##     VideoPlayer. Es lo único que arranca el vídeo: no hay tiempo de arranque
##     escrito en ninguna parte, porque la pista vive en la misma animación que
##     la canción dispara. Que una clave de método en t=0.0 llegue a ejecutarse
##     se comprobó contra este motor antes de confiar en ello - se ejecuta una
##     vez;
##
##   y el .ogv está donde la escena dice.
##
## Se carga la escena de verdad en vez de leer el .tscn: esta cutscene no
## depende de ningún autoload, así que aquí sí se puede, y comprobar el árbol
## instanciado es más fuerte que comprobar el texto que lo describe.
##
## Run with:
##   godot --headless --path . --script tools/test_closeup_video_wired.gd

const SCENE := "res://lullaby_mod/resources/funkin/songs/monochrome/cutscene/cut_mono_closeup.tscn"
const SONG := "res://lullaby_mod/songs/monochrome/sng_monochrome.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# La canción sigue pidiendo lo mismo que antes.
	var song: String = FileAccess.get_file_as_string(SONG)
	_check(song.contains('NodePath("../MonoCloseup/Cutscene")'),
		"la canción sigue disparando ../MonoCloseup/Cutscene")
	_check(song.contains('"clips": PackedStringArray("cutscene")'),
		"...con el clip llamado 'cutscene'")

	var packed: PackedScene = load(SCENE)
	if not _check(packed != null, "la cutscene carga"):
		_finish()
		return

	var root: Node = packed.instantiate()
	_check(root.name == "MonoCloseup",
		"la raíz sigue siendo MonoCloseup (%s)" % root.name)
	_check(root is AspectRatioContainer,
		"...y sigue siendo AspectRatioContainer (%s)" % root.get_class())

	var player := root.get_node_or_null(^"Cutscene") as AnimationPlayer
	if not _check(player != null, "el AnimationPlayer Cutscene existe"):
		root.free()
		_finish()
		return

	_check(player.has_animation(&"cutscene"),
		"...y conserva la animación 'cutscene'")

	var video := root.get_node_or_null(^"VideoPlayer") as VideoStreamPlayer
	_check(video != null, "hay un VideoStreamPlayer")
	_check(video != null and video.stream != null, "...con su .ogv puesto")

	# La pista de método, que es lo único que arranca el vídeo.
	var anim: Animation = player.get_animation(&"cutscene")
	var found: bool = false
	var visual: int = 0
	for t in anim.get_track_count():
		var kind: int = anim.track_get_type(t)
		if kind == Animation.TYPE_ANIMATION:
			visual += 1
		if kind != Animation.TYPE_METHOD:
			continue
		if str(anim.track_get_path(t)) != "VideoPlayer":
			continue
		for k in anim.track_get_key_count(t):
			if anim.method_track_get_name(t, k) == &"play":
				found = true

	_check(found, "la animación llama a play() sobre el VideoPlayer")
	_check(visual == 0,
		"no queda ninguna pista disparando reproductores que ya no existen (%d)" % visual)

	root.free()
	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
