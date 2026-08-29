class_name ConsoleHomeButton
extends Control


@export var disabled: bool = false

@export var home_container: HomeContainer
@export var tab_target: Control
@export var icon_model: Node3D
@export var icon_mesh: Node3D
@export var icon_animation_player: AnimationPlayer
@export var idle_animation: StringName
@export var select_animation: StringName
@export var console: Console
@export var material_idle: StandardMaterial3D
@export var material_select: StandardMaterial3D

var focused: bool = false
var tween: Tween


func _ready() -> void :
	focus_entered.connect(_focus_entered)
	focus_exited.connect(_focus_exited)
	home_container.disable_icons.connect(_disable_icons)
	home_container.enable_icons.connect(_enable_icons)

## Pone un material en la malla del icono, y NUNCA lo quita.
##
## `surface_set_material()` escribe en el recurso Mesh, que es compartido, asi
## que pasarle null no deja el icono "sin cambios": lo deja SIN MATERIAL. Y su
## SubViewport tiene own_world_3d con ninguna luz y ningun WorldEnvironment -a
## proposito, porque todo lo que se dibuja ahi es unshaded- de modo que el
## material por defecto de Godot, que si se sombrea, sale NEGRO.
##
## Era exactamente el bug: los cinco material_select de la escena estaban
## escritos ANTES de `script =`, y una propiedad de script puesta antes de que
## el script exista no se aplica ni avisa - se queda en null. Comprobado contra
## este motor. Asi que enfocar un boton borraba el material de su icono y el
## icono se quedaba negro al moverse por el menu; el de Hacks se salvaba solo
## porque sus dos lineas si estaban despues.
##
## El orden ya esta corregido en la escena. Esto es la otra mitad: aunque
## vuelva a faltar un material, lo peor que puede pasar es que el icono no
## cambie de aspecto, no que desaparezca.
func _paint(material: StandardMaterial3D) -> void:
	if material == null:
		push_warning("%s: material sin asignar, el icono se deja como esta" % name)
		return
	if icon_mesh is MeshInstance3D and icon_mesh.mesh != null:
		icon_mesh.mesh.surface_set_material(0, material)


func _focus_entered() -> void :
	home_container.bubble_target = position + pivot_offset

	_paint(material_select)
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(icon_mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC)
	focused = true

func _focus_exited() -> void :
	console.play_sound.emit("sfx_soulroom_click")

	_paint(material_idle)
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(icon_mesh, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_CUBIC)
	focused = false

func _input(event: InputEvent) -> void :
	if console.booting:
		return

	if event.is_action_released(&"ui_accept") and focused:
		_confirm()

func _gui_input(event: InputEvent) -> void :
	if console.booting:
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	grab_focus()
	focused = true
	_confirm()

func _confirm() -> void :
	if disabled:
		console.play_sound.emit("sfx_soulroom_deny")
		return
	focused = false
	icon_animation_player.play(select_animation)
	home_container.disable_icons.emit()
	console.play_sound.emit("sfx_soulroom_select_alt")
	icon_animation_player.animation_finished.connect( func(_anim: StringName):
		home_container.tab_container.change_tab(tab_target.get_index())
	, CONNECT_ONE_SHOT)

func _disable_icons():
	if has_focus():
		return
	focus_mode = Control.FOCUS_NONE


func _enable_icons():
	focus_mode = Control.FOCUS_ALL
