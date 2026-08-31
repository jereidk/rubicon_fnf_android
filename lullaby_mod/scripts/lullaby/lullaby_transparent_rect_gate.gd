@tool
extends ColorRect

## Hides a full-screen fade ColorRect while it is fully transparent.
##
## Hermano de `lullaby_effect_rect_gate.gd`, y por la misma razon: Godot NO
## descarta un CanvasItem por ser transparente. Un ColorRect a pantalla completa
## con `color.a = 0` se rasteriza y se mezcla igual, cuesta un relleno entero por
## fotograma, y no produce un solo pixel.
##
## La tienda tiene uno. `UI/BlackScreenThingy` es un ColorRect con
## `anchors_preset = 15` y `color = Color(1, 1, 1, 0)`, y el censo del log
## 10226-4fe0a6db lo nombra como el que mas aporta al sobredibujado en las cinco
## muestras que hay de la tienda:
##
##     over=2.2x(n=11 top=UI/BlackScreenThingy@1.0x)
##     relleno=[UI/BlackScreenThingy@1.00x a=0.00, ...]
##
## Es el mismo defecto que `UILayer/NTSC@1.00x a=0.00` y
## `UILayer/RainParent/Rain@1.00x a=0.00` en Chimera, cuyo arreglo bajo el
## sobredibujado de esa entrada de 5.1x a 2.1x.
##
## Se apaga con `visible`, y no colapsando la geometria como hace
## `settings.gd._hide_if_it_draws_nothing()`. La diferencia no es de estilo: alli
## el `visible` lo animaban cuatro pistas y escribirlo peleaba con ellas, asi que
## habia que mutar el rect sin tocar esa propiedad. Aqui las tres pistas que
## tocan este nodo animan `:color`, y ninguna toca `:visible` - o sea que la
## propiedad no tiene otro dueño. Esa premisa la fija el guard, porque si algun
## dia una pista empieza a animar `visible` este enfoque deja de ser correcto y
## nada mas se enteraria.
##
## Sondeando y no reaccionando, igual que el gate de efectos: el color lo mueve
## una pista de animacion y no hay señal para eso. Leer un float por fotograma no
## se mide al lado de lo que ahorra.

func _process(_delta: float) -> void:
	# `> 0.0` y no `is_zero_approx()`: un fundido que arranca en 0.001 tiene que
	# encender el nodo ya, no quedarse invisible hasta superar un epsilon.
	var wanted: bool = color.a > 0.0
	if visible != wanted:
		visible = wanted
