@tool
extends AdobeSymbolInstance
class_name AdobeButtonInstance

## cne-flixel-animate/src/animate/internal/elements/ButtonInstance.hx
##
## ButtonInstance hereda de SymbolInstance y agrega tres cosas:
##   - Un estado propio (UP/OVER/DOWN) que determina QUE frame del sub-simbolo
##     se dibuja. getFrameIndex() devuelve min(curButtonState, frameCount-1),
##     o sea el frame 0 para UP, 1 para OVER, 2 para DOWN (si existen).
##   - Un hitbox: rect del frame HIT del sub-simbolo, transformado al espacio
##     del padre (ButtonInstance.hx:49-57 getBounds()).
##   - Una senal onClick que dispara en el frame en que el mouse/touch
##     transiciona de no-presionado a presionado dentro del hitbox.
##
## El estado se actualiza en cada draw() (ButtonInstance.hx:66-73), no en
## _process - asi el hitbox siempre refleja la posicion del ultimo frame
## dibujado. En el port replicamos esa logica en AnimateSymbol._unhandled_input
## y en AdobeAtlas.draw_symbol (que es donde se actualiza el hitbox en screen
## space).

enum ButtonState {
	UP = 0,
	OVER = 1,
	DOWN = 2,
	HIT = 3,
}

## Estado actual del boton. UP por default, cambia a OVER cuando el cursor
## esta adentro pero no presionado, y a DOWN cuando esta adentro y presionado.
## Coincide con ButtonInstance.hx:29 curButtonState (default UP en el ctor).
@export_storage var cur_state: int = ButtonState.UP

## cne-flixel-animate/.../ButtonInstance.hx:35-38: onClick es un FlxSignal
## sin argumentos. En Godot uso un Signal nativo del mismo tipo.
signal clicked

## Hitbox en screen space del ultimo frame dibujado. Se actualiza en
## AdobeAtlas.draw_symbol (que ya tiene el screen_transform completo del
## boton aplicado). Vacio (Rect2 con size 0) si todavia no se dibujo.
## Se usa en AnimateSymbol._unhandled_input para hit-test contra mouse/touch.
var last_hitbox: Rect2 = Rect2()

## Flag para no disparar onClick multiples veces en el mismo press.
## El source usa FlxG.mouse.justPressed que ya es edge-triggered; Godot no
## tiene un equivalente directo para input global, asi que lo emulamos.
var _was_pressed_last_frame: bool = false


## ButtonInstance.hx:76-79 getFrameIndex():
##     return FlxMath.minInt(curButtonState, this.libraryItem.timeline.frameCount - 1);
## Devuelve el indice del frame a mostrar en funcion del estado actual,
## clampeado al ultimo frame real del sub-simbolo (un boton con solo 2 frames
## no puede mostrar el frame 3 = HIT).
func button_frame_index(symbol_length: int) -> int:
	return mini(cur_state, maxi(symbol_length - 1, 0))
