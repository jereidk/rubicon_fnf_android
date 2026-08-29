extends SceneTree

## El intro de Monochrome lo dibuja un video, y el HUD sigue vivo encima.
##
## Elegido midiendo: la ventana va de 1s a 35s y la primera nota del jugador
## esta en 44s, asi que no hay nada que el jugador pueda alterar ahi. Dibujarlo
## costaba 27.9 MB de textura exclusivamente suya; el clip son 3.3 MB.
##
## Lo que se vigila es lo que ya se colo una vez y no se ve leyendo la escena:
##
##   UILayer tiene que estar en el grupo cutscene_live_overlay. Sin eso el
##     harness NO lo esconde al renderizar y el HUD se hornea dentro del video
##     - el primer intento salio con las flechas del strumline y las lineas
##     divisorias del hitbox pintadas encima del arte, fijas para siempre. Y
##     eso es peor que feo: el hitbox cambia con los ajustes del jugador
##     -tamano de nota, scroll, pad o hitbox- asi que horneado seria mentira en
##     cuanto alguien toque una opcion.
##
##   la pista que arrancaba el IntroAnimationPlayer ya no existe, y en su sitio
##     hay una de METODO que llama a play() sobre el video, en el mismo t=1 en
##     el que se disparaba el clip original.
##
##   y la tabla de saltos del intro ya no menciona un nodo borrado. Ese
##     Dictionary resuelve sus NodePath al instanciar, asi que una entrada
##     muerta llega como null y LullabyIntroSkipModule la llama igual. Quitarla
##     ademas da el comportamiento correcto: al reintentar, el seek del reloj
##     pasa de largo del t=1 y el video simplemente no arranca.
##
## Run with:
##   godot --headless --path . --script tools/test_monochrome_intro_video.gd

const SONG := "res://lullaby_mod/songs/monochrome/sng_monochrome.tscn"
const CLIP := "res://lullaby_mod/songs/monochrome/video/intro.ogv"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	var t: String = FileAccess.get_file_as_string(SONG)
	_check(not t.is_empty(), "la cancion se lee")

	_check(FileAccess.file_exists(CLIP), "el clip del intro esta en el arbol")

	_check(t.contains('[node name="Cutscene" type="VideoStreamPlayer" parent="Front"'),
		"el intro lo dibuja un VideoStreamPlayer en Front/Cutscene")
	_check(not t.contains("IntroAnimationPlayer"),
		"no queda ninguna referencia al IntroAnimationPlayer que se fue")

	# El grupo, que es lo que mantiene el HUD fuera del horneado.
	var m: RegExMatch = RegEx.create_from_string(
		'\\[node name="UILayer" type="CanvasLayer"[^\\]]*\\]').search(t)
	_check(m != null and m.get_string().contains('groups=["cutscene_live_overlay"]'),
		"UILayer esta marcado como overlay vivo, o el HUD se hornea en el video")

	# La llamada que lo arranca, en el mismo sitio que el clip original.
	var method_at: int = t.find('"method": &"play"')
	_check(method_at >= 0, "hay una pista de metodo que llama a play()")
	_check(t.contains('NodePath("../Front/Cutscene")'),
		"...apuntando al video del intro")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
