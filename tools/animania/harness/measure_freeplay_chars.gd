# Mide la caja dibujada de los dos personajes de freeplay en su espacio local.
# Un atlas de Adobe no trae tamano: gdanimate lo dibuja de un arbol de simbolos, asi que
# la unica forma de saber donde cae su esquina es pintarlo y contar pixeles opacos.
extends Node2D

const PAD := Vector2(1400, 1400)
const WHO := ["freeplay_bf", "freeplay_gf"]

var _pending: Array = []
var _frames := 0
var _vp: SubViewport = null
var _name := ""


func _ready() -> void:
	_pending = WHO.duplicate()
	_next()


func _next() -> void:
	if _vp != null:
		_vp.queue_free()
		_vp = null
	if _pending.is_empty():
		get_tree().quit()
		return
	_name = _pending.pop_front()
	_vp = SubViewport.new()
	_vp.size = Vector2i(PAD * 2)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var sym := AnimateSymbol.new()
	sym.atlases = [load("res://animania_mod/menus/freeplay/%s_atlas.tres" % _name)] as Array[AnimateAtlas]
	sym.position = PAD
	_vp.add_child(sym)
	var player := AnimationPlayer.new()
	player.add_animation_library(&"", load("res://animania_mod/menus/freeplay/%s_library.tres" % _name))
	_vp.add_child(player)
	player.root_node = player.get_path_to(sym)
	# build_adobe_character.gd nombra las animaciones "<basename>_<nombre>", no "<nombre>".
	# Pedir &"idle" a secas no falla con ruido: AnimateSymbol pinta igualmente su simbolo
	# por defecto, asi que gf salia medido y bf salia "nada dibujado", y parecia un
	# problema del atlas de bf cuando era el nombre.
	var clip := StringName("%s_idle" % _name)
	player.play(clip)
	# Un fotograma 0 puede salir vacio, asi que se mide a mitad de la animacion.
	player.seek(player.get_animation(clip).length * 0.5, true)
	_frames = 0


func _process(_d: float) -> void:
	if _vp == null:
		return
	_frames += 1
	if _frames < 4:
		return
	var img: Image = _vp.get_texture().get_image()
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a > 0.02:
				lo.x = mini(lo.x, x); lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x); hi.y = maxi(hi.y, y)
	if hi.x < 0:
		print("OUT %s: nada dibujado" % _name)
	else:
		print("OUT %s: esquina local (%.1f, %.1f)  tamano %dx%d" % [_name,
			lo.x - PAD.x, lo.y - PAD.y, hi.x - lo.x + 1, hi.y - lo.y + 1])
	_next()
