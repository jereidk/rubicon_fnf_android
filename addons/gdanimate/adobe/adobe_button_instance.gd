@tool
extends AdobeSymbolInstance
class_name AdobeButtonInstance

## Port de ButtonInstance - MaybeMaru/flixel-animate@dcaa33c
## src/animate/internal/elements/ButtonInstance.hx.
##
## ButtonInstance hereda de SymbolInstance y agrega tres cosas:
##   - Un estado propio (UP/OVER/DOWN) que determina QUE frame del sub-simbolo
##     se dibuja: getFrameIndex() devuelve min(curButtonState, frameCount - 1)
##     (ButtonInstance.hx:53-56), o sea el frame 0 para UP, 1 para OVER y 2
##     para DOWN, si existen.
##   - Un hitbox, que son los bounds del frame HIT (3) del sub-simbolo - NO
##     los del frame que se esta mostrando (ButtonInstance.hx:45-51).
##   - Una senal onClick que dispara en el flanco de subida del boton del
##     mouse estando adentro del hitbox.

enum ButtonState {
	UP = 0,
	OVER = 1,
	DOWN = 2,
	HIT = 3,
}

## ButtonInstance.hx:28 curButtonState, UP por default en el ctor
## (ButtonInstance.hx:40). Cambia a OVER con el cursor adentro sin apretar, y
## a DOWN adentro y apretado.
@export_storage var cur_state: int = ButtonState.UP

## ButtonInstance.hx:33 `public var onClick:FlxSignal` - sin argumentos.
signal clicked

## Hitbox del ultimo dibujo, en coordenadas LOCALES del AnimateSymbol que lo
## dibujo. Lo calcula AdobeAtlas.draw_symbol() y lo lleva a espacio local
## AdobeAtlas.draw_on(). Rect2 vacio mientras no se haya dibujado.
##
## El source lo guarda en espacio de camara (ButtonInstance.hx:71 `_hitbox`).
## Local es mejor aca porque no se invalida cuando el nodo se mueve, y asi
## sobrevive al camino barato del backbuffer cache, que no vuelve a pasar por
## draw_symbol().
var last_hitbox: Rect2 = Rect2()

## Estado del boton del mouse en el frame anterior, para detectar el flanco de
## subida. El source usa FlxG.mouse.justPressed, que Flixel ya calcula global;
## Godot no expone un equivalente para polling, asi que se emula.
var _was_pressed_last_frame: bool = false


## ButtonInstance.hx:53-56 getFrameIndex():
##     return FlxMath.minInt(curButtonState, this.libraryItem.timeline.frameCount - 1);
## El estado se mapea directo al indice de frame, clampeado al ultimo frame
## real (un boton de 2 frames no puede mostrar el 3).
func button_frame_index(symbol_length: int) -> int:
	return mini(cur_state, maxi(symbol_length - 1, 0))


## Port de ButtonInstance.updateButtonState - ButtonInstance.hx:73-121:
##
##     if (isOverlaped)
##     {
##         this.curButtonState = FlxG.mouse.pressed ? ButtonState.DOWN : ButtonState.OVER;
##         if (FlxG.mouse.justPressed) onClick.dispatch();
##     }
##     else this.curButtonState = ButtonState.UP;
##
## `point` va en el mismo espacio que last_hitbox (local al nodo). Devuelve si
## el estado CAMBIO, para que el llamador sepa si hace falta redibujar.
##
## La comparacion se transcribe con los <= / >= del source
## (ButtonInstance.hx:83), que incluyen el borde, en vez de usar
## Rect2.has_point(), que excluye el lado derecho y el de abajo.
##
## Lo de justPressed importa: el flag se actualiza mire donde mire el cursor,
## asi que entrar al hitbox con el boton YA apretado no dispara el click,
## igual que en el source.
func update_state(point: Vector2, pressed: bool) -> bool:
	var overlaped: bool = (
		point.x >= last_hitbox.position.x and point.x <= last_hitbox.end.x
		and point.y >= last_hitbox.position.y and point.y <= last_hitbox.end.y
	)

	var state: int = ButtonState.UP
	if overlaped:
		state = ButtonState.DOWN if pressed else ButtonState.OVER
		if pressed and not _was_pressed_last_frame:
			clicked.emit()

	_was_pressed_last_frame = pressed

	if cur_state == state:
		return false

	cur_state = state
	return true
