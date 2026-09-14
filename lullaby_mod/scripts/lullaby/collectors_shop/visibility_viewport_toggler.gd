extends VisibleOnScreenNotifier3D

## Apaga un SubViewport cuando no se ve - y cuando todavia no se puede usar.
##
## EL FALLO QUE TENIA, que es por lo que esto esta reescrito: `is_accessible` a
## false hacia que las DOS mitades salieran por la puerta de atras.
##
##     func enable_viewport() -> void:
##         _is_visible = true
##         if !is_accessible:
##             return                                  # no enciende
##         sub_viewport.set_update_mode(UPDATE_ALWAYS)
##
##     func disable_viewport() -> void:
##         _is_visible = false
##         if !is_accessible:
##             return                                  # y TAMPOCO apaga
##         sub_viewport.set_update_mode(UPDATE_DISABLED)
##
## Con la bandera en false el gate no tocaba el viewport NUNCA, asi que el
## viewport se quedaba en lo que dijera la escena. Y la escena no dice nada: ni
## `SidemenuSubViewport` ni `KollectadexSubViewport` declaran
## `render_target_update_mode`, con lo que se quedan en el defecto de Godot, que
## es UPDATE_ALWAYS.
##
## Los dos gates de la tienda - `CartridgeBagViewportDisabler` y
## `KollectadexViewportDisabler` - se autoran con `is_accessible = false`. O
## sea que sus SubViewports se dibujan ENTEROS en cada fotograma desde que carga
## la escena, los mire el jugador o no, y nada puede apagarlos hasta que una
## animacion de desbloqueo levante la bandera. `SidemenuSubViewport` son 480x960
## con 3D.
##
## El log del dispositivo lo enseñaba sin que se notara lo que enseñaba: con la
## consola apagada, `sub=2/7` y
## `sub_top=Viewports/SidemenuSubViewport(240x480,3d)`. Dos de siete
## subviewports vivos, en una escena cuyo fotograma son 12,5-13,4ms de GPU.
##
## Ahora decide un solo sitio - `_apply()` - y la condicion es la que el nombre
## de la clase promete: se dibuja si se ve Y se puede usar. Que todavia no se
## pueda usar es MAS motivo para apagarlo, no menos.
##
## LA PRIMERA VEZ NO APAGA DEL TODO, y es a proposito. Un SubViewport en
## UPDATE_DISABLED conserva su ultima textura, pero si no ha dibujado nunca no
## tiene ninguna y al acercarse se veria un panel negro el primer fotograma. Asi
## que la primera aplicacion usa UPDATE_ONCE, que dibuja un fotograma y se apaga
## solo: hay textura valida desde el principio, y el coste es un fotograma por
## sesion en vez de sesenta por segundo.

@export var is_accessible: bool = true:
	set(value):
		if is_accessible == value:
			return

		is_accessible = value
		_apply()

@export var sub_viewport: SubViewport

var _is_visible: bool

## Si el viewport ha dibujado alguna vez. Ver la nota de UPDATE_ONCE arriba.
var _primed: bool = false

func _ready() -> void :
	screen_entered.connect(enable_viewport)
	screen_exited.connect(disable_viewport)

	# El estado inicial tambien se aplica. Antes no se aplicaba ninguno, que es
	# como el defecto de la escena acababa mandando.
	_apply()

## Nombres conservados: la escena los tiene cableados y una animacion de
## desbloqueo puede llamarlos por nombre. Renombrarlos romperia eso en silencio.
func enable_viewport() -> void :
	_is_visible = true
	_apply()

func disable_viewport() -> void :
	_is_visible = false
	_apply()

func _apply() -> void :
	# El setter de `is_accessible` corre al cargar la escena, antes de `_ready()`
	# y antes de que `sub_viewport` este resuelto.
	if sub_viewport == null or not is_instance_valid(sub_viewport):
		return

	if is_accessible and _is_visible:
		_primed = true
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return

	if not _primed:
		_primed = true
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
