class_name ShopConsolePower
extends TriggerArea3D

@export var hint: Control
@export var console_area: SubmenuArea
@export var bag_focus: FocusArea3D
@export var animation: AnimationPlayer

static var on: bool = false:
	set(v):
		if on != v:
			on = v
			SaveData.set_flag(&"console_on", on)
			SaveData.save()

@export var shop: CollectorShop
@export var console: Console
@export var indicator: Node3D
@export var tv_light: OmniLight3D

@onready var click_sound: AudioStreamPlayer3D = $ClickSound

var modulate_target: Color


func _ready() -> void :
	on = SaveData.get_flag(&"console_on")

	animation.play("button_on") if on else animation.play("button_off")

	bag_focus.can_interact = SaveData.get_flag(&"console_boot_seen")

	apply_console_state()


## Lo de `_ready()` que necesita la consola, aparte y repetible.
##
## `console` es un @export que console_deferred_loader.gd rellena cuando la
## consola termina de cargar, y eso pasa DESPUES de este `_ready()`. En la build
## 10249-e93c8ca2 esto estaba en linea dentro de `_ready()`, y el log del moto
## g53 mide lo que costo:
##
##     [40.64s] ERROR Invalid assignment of property or key 'modulate' with
##              value of type 'Color' on a base object of type 'Nil'.
##              power_console.gd:34 ShopConsolePower._ready
##
## Un error asi aborta la funcion, asi que las cuatro lineas que venian despues
## - la luz de la TV, el indicador, y `_update_on()` con la musica dentro - no
## se ejecutaron nunca. Una sola linea de log y la mitad del televisor sin
## inicializar.
##
## Sale UNA vez y no una por fotograma porque la tienda arranca con el arbol
## pausado por sus secuencias: `_process()` no corre, y el loader (que se pone
## en PROCESS_MODE_ALWAYS justo por esto) monta la consola durante la pausa.
##
## El loader llama a esto en cuanto asigna `console`. Idempotente a proposito:
## se llama dos veces siempre que la consola SI estuviera ya puesta.
func apply_console_state() -> void :
	if console == null or not is_instance_valid(console):
		return

	if on:
		console.modulate = Color.WHITE
		tv_light.light_energy = 0
	else:
		console.modulate = Color.BLACK
		tv_light.light_energy = 0.241

	indicator.visible = on
	_update_on()


func _process(delta: float) -> void :
	if console == null or not is_instance_valid(console):
		return
	console.modulate = console.modulate.lerp(modulate_target, delta * 16.0)


func trigger() -> void :
	if not can_interact:
		return

	click_sound.play()
	on = not on
	_update_on()

	if on:
		boot_console()


func boot_console() -> void :
	if not SaveData.get_flag(&"console_area_seen"):
		SaveData.set_flag(&"console_area_seen", true)
		SaveData.save()

	console_area.trigger()
	console_area.register_trigger()
	console.modulate = Color.WHITE
	modulate_target = Color.WHITE
	on = true
	_update_on()

	shop.state = CollectorShop.ShopStates.BUSY
	Console.boot_enabled = true
	console.booting = true
	console.boot(true)
	console.startup_sound.volume_linear = 1.0
	console.other_sounds.volume_linear = 1.0

	await console.boot_finished

	if not SaveData.get_flag(&"console_boot_seen"):
		if is_instance_valid(hint):
			var hint_tween: Tween = get_tree().create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			hint_tween.tween_property(hint, "modulate:a", 0.65, 0.5)
			hint_tween.tween_property(hint, "modulate:a", 0, 1.0).set_delay(2.5)

		bag_focus.can_interact = true
		SaveData.set_flag(&"console_boot_seen", true)
		SaveData.save()


func _update_on() -> void :
	animation.play("button_on") if on else animation.play("button_off")
	if on:
		modulate_target = Color.WHITE
		tv_light.light_energy = 0.241
	else:
		modulate_target = Color.BLACK
		tv_light.light_energy = 0.0

	indicator.visible = on

	# Igual que arriba: `console` llega en diferido, y `_update_on()` tambien se
	# llama desde `trigger()`, que no pasa por apply_console_state().
	if console != null and is_instance_valid(console) and console.music:
		console.music.playing = on
