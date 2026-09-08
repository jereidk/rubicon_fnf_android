class_name SongTimeBar
extends ColorRect
## La barra de progreso de la cancion: `initTimeBar` y `updateTimeBar` de PlayState.
##
## Al puerto le faltaba entera, y no es un adorno: es lo unico en pantalla que dice cuanto
## queda de cancion.
##
## initTimeBar, lineas 1934-1943 (0x1b52be0), leido asi:
##
##   1934  new FunkinSprite(0, <downScroll ? 713 : 0>)   // `mov $0x2c9,%esi` en la rama
##   1936  makeSolidColor(1, 7, 0xFF808080)              // edx=1, ecx=7, y el color en rcx
##   1937  scrollFactor.set(...)                         // dos FlxBasePoint seguidos
##   1939  alpha = 0.8                                   // el 0.8 de 0x59fa588 por la
##                                                       // ranura 0x3a8 del vtable, que es
##                                                       // set_alpha -la misma que usan las
##                                                       // flechas del menu de semanas-
##   1940  zIndex = 999999                               // `movl $0xf423f,0x28(%rax)`
##   1942  cameras = null                                // el campo 0x260 a null
##   1943  visible = Save.instance.options.appearance.showTimeBar
##
## updateTimeBar, lineas 2586-2589 (0x1b52390), es una sola cuenta:
##
##   timeBar.scale.x = FlxG.width * (Conductor.instance.songPosition / songLengthMs)
##
## O sea: un rectangulo de UN pixel de ancho estirado hasta el ancho de la pantalla segun
## lo que lleve la cancion. De ahi que se vea como una barra que crece.
##
## Que NO va copiado y por que:
##
## `?` El `showTimeBar` es una opcion del guardado y este puerto no tiene guardado, asi que
## la barra va siempre puesta. Cuando haya guardado, este es el interruptor.
##
## `?` El downScroll: el mod la baja a y=713 -que con sus 7 de alto acaba justo en 720- si
## el jugador juega con las notas hacia abajo. Aqui se lee la misma preferencia si existe;
## si no, arriba.
##
## `?` La CAMARA. El mod le pone `cameras = null`, que en flixel es "la de por defecto", y
## un zIndex de 999999. No es camHUD, o sea que en phone-call NO se apagaria con el HUD
## durante el minuto de intro. Aqui va en su propia capa por encima del HUD para que se
## comporte igual. No lo he seguido hasta el final: la ranura 0x260 la doy por `cameras`
## por como se usa, no porque haya visto el nombre.

## 7 px de alto en el espacio del mod.
const REF_HEIGHT := 7.0
## La y con las notas hacia abajo. Con los 7 de alto, acaba en 720 clavado.
const REF_Y_DOWNSCROLL := 713.0
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

@export var clock: RubiconLevelClock
## El instrumental, para saber cuanto dura la cancion. Es lo que el mod llama songLengthMs.
@export var instrumental: AudioStreamPlayer

var _length: float = 0.0


func _ready() -> void:
	color = Color8(0x80, 0x80, 0x80)
	modulate.a = 0.8
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(0.0, REF_HEIGHT * FUNKIN_TO_RUBICON)
	position = Vector2(0.0, REF_Y_DOWNSCROLL * FUNKIN_TO_RUBICON if _downscroll() else 0.0)
	_length = _song_length()


## Cuanto dura la cancion, en segundos. El instrumental lo sabe exacto; si no lo hay, la
## animacion del reloj, que el builder genera con el largo de la cancion. Se mide una vez:
## el stream no cambia a mitad de cancion y preguntarselo por fotograma es tonteria.
func _song_length() -> float:
	if instrumental != null and instrumental.stream != null:
		var seconds: float = instrumental.stream.get_length()
		if seconds > 0.0:
			return seconds
	if clock != null and clock.animation_player != null:
		return clock.animation_player.current_animation_length
	return 0.0


func _downscroll() -> bool:
	# La misma preferencia que leen las opciones, si esta. Sin ella, arriba.
	if ProjectSettings.has_setting("animania/downscroll"):
		return bool(ProjectSettings.get_setting("animania/downscroll"))
	return false


func _process(_delta: float) -> void:
	if clock == null:
		return
	if _length <= 0.0:
		_length = _song_length()
		if _length <= 0.0:
			return
	var ratio: float = clampf(clock.time_milliseconds / 1000.0 / _length, 0.0, 1.0)
	size.x = 1920.0 * ratio
