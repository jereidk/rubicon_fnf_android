
extends Node
class_name ChimeraLowerHealthModule

@export var health_module: RubiconHealthModule
@export var color_rect: ColorRect

func _ready() -> void :
	if is_instance_valid(health_module):
		health_module.health_changed.connect(_on_health_changed)
		# Y se pone al dia UNA vez, sin esperar a que la vida cambie.
		#
		# `health_changed` solo se emite cuando cambia algo, y en Chimera se
		# empieza con la vida llena, asi que este metodo no corria hasta la
		# primera nota fallada. Hasta entonces el rect se quedaba como esta
		# authoreado: `visible` sin poner -o sea true-, `self_modulate.a = 0` y
		# anclado a pantalla completa. Es decir, dibujandose entero y
		# transparente.
		#
		# Godot no descarta un CanvasItem por tener alpha 0, lo rasteriza y lo
		# mezcla igual. El log del dispositivo lo tiene en la lista de relleno
		# de toda la entrada a Chimera:
		#
		#     over=5.1x  relleno: ... UILayer/LowerHealthRect@1.00x a=0.00 ...
		#
		# 1.15 Mpx por fotograma en un g53 para no ensenar nada.
		_on_health_changed()

func _on_health_changed() -> void :
	if is_instance_valid(color_rect):
		color_rect.visible = health_module.health < health_module.max_health / 2
		if color_rect.visible:
			color_rect.self_modulate.a = remap(health_module.health, health_module.min_health, health_module.max_health / 2, 1, 0)
