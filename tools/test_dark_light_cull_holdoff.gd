extends SceneTree

## `_cull_dark_lights` espera antes de sacar una luz del render, y por que la
## espera dura tres segundos.
##
## El motivo, medido en el g53 sobre `80dc43f7`: cuando Serena hace la foto,
## Chimera se congela ~2.4s repartidos en dos frames, y el log dice que no es
## ni geometria ni subida de textura.
##
##   148.21s  frame= 735.9ms  spec+31  luz=3 [PhoneGlow,flash,OmniLight3D]
##   150.16s  frame=1661.6ms  spec+ 6  luz=2 [PhoneGlow,OmniLight3D]
##   151.03s                  spec+ 1  luz=1 [OmniLight3D]
##
## `vram_delta=+0.0MB` en los dos frames de parada y `rend=[3d=44/25198/44]`
## identico entre ellos. Lo unico que se mueve es el numero de luces.
##
## Y ese numero es parte de la clave de especializacion de cada superficie en
## Forward Mobile. El banco aislado de CLAUDE.md lo mide: geometria sin luces
## compila 3 pipelines, anadir una omni 3 mas, anadir un spot 3 mas, y **quitar
## la omni otra vez** 3 mas. Satura por numero pero no por estado, asi que cada
## combinacion de "estas superficies a este numero de luces" se paga una vez -
## y la sesion de fotos revela veintiseis mallas mientras el flash cruza el
## cero.
##
## Lo que el arreglo NO puede hacer es dejar de cullear una luz aparcada a
## cero, que es el caso para el que se escribio el pase: `TvLight` esta a cero
## los 78 segundos de `prelude` con `omni_range = 43.9` sobre una casa de diez
## unidades. Por eso es un holdoff y no una exencion.
##
## Correr con:
##   godot --headless --path . --script tools/test_dark_light_cull_holdoff.gd

const APPLIER := "res://lullaby_mod/scripts/lullaby/settings/lullaby_light_budget_applier.gd"
const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = _read(APPLIER)
	_check(src != "", "el applier se lee")

	# 1. El holdoff existe, con su constante y su reloj.
	_check(_has_statement(src, "const DARK_HOLD_SECONDS"),
		"el holdoff tiene constante propia")
	_check(_has_statement(src, "_dark_since[id] = now"),
		"se apunta cuando la luz se puso a cero")
	_check(_has_statement(src, "DARK_HOLD_SECONDS * 1000.0"),
		"el culleo compara contra el holdoff")

	# 2. Timestamps y no delta acumulado. Godot recorta delta, asi que un
	#    acumulador cuenta de menos justo durante los parones que este holdoff
	#    existe para evitar - un frame de 1.6s llega como ~80ms.
	_check(_has_statement(src, "Time.get_ticks_msec()"),
		"el reloj es de pared, no delta acumulado")

	# 3. Y el reloj se olvida en cuanto la luz vuelve, o una luz que parpadea
	#    acabaria culleada por acumulacion tras varios cruces.
	var forget: int = src.find("_dark_since.erase(id)")
	var restore: int = src.find("light.light_cull_mask = _dark_masks[id]")
	_check(forget != -1, "el reloj se olvida al volver la luz")
	_check(forget != -1 and restore != -1 and forget < restore,
		"se olvida antes de restaurar, o sea en todos los caminos de vuelta")

	# 4. Restaurar NO se retiene. El holdoff es de un solo lado a proposito:
	#    una luz que vuelve tarde es un parpadeo visible en una tele que
	#    estroboscopia cada dos frames, y una que vuelve pronto no cuesta nada.
	_check(not _has_statement(src, "_dark_masks.has(id) and now -"),
		"la vuelta no esta retenida por el holdoff")

	# 5. Se limpia al cambiar de escena, o los ids de la anterior se quedan.
	_check(_has_statement(src, "_dark_since.clear()"),
		"se limpia al cambiar de escena")

	# 6. Y los hechos de datos de los que depende el numero: los huecos a cero
	#    de las luces de Chimera tienen que seguir separandose a los dos lados
	#    de la constante. Si algun dia dejan de hacerlo, este guard lo dice en
	#    vez de seguir fijando un tres que ya no separa nada.
	_check_photo_session(_hold_seconds(src))

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## El holdoff se lee del propio applier, no se repite aqui. Un guard que fija
## su propia copia del numero pasa contento mientras el codigo baja el suyo.
func _hold_seconds(src: String) -> float:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("const DARK_HOLD_SECONDS"):
			return trimmed.get_slice(":=", 1).strip_edges().to_float()
	return -1.0


func _check_photo_session(hold: float) -> void:
	var text: String = _read(CHIMERA)
	if text == "":
		_check(false, "sng_chimera.tscn se lee")
		return
	_check(hold > 0.0, "DARK_HOLD_SECONDS se lee del applier (%.1fs)" % hold)

	# El caso que hay que dejar en paz: el flash de la sesion de fotos. Su
	# hueco a cero mas largo entre dos destellos tiene que quedar POR DEBAJO
	# del holdoff, o el pase se lo vuelve a comer.
	var photo: String = _clip(text, "Animation_k22fj")
	_check(photo != "", "104_photographysesh esta en la escena")
	if photo == "":
		return
	for light_name: String in ["flash", "PhoneGlow"]:
		var gap: float = _longest_transient_gap(photo, light_name)
		_check(gap > 0.0, "%s pasa por cero en la sesion de fotos" % light_name)
		_check(gap > 0.0 and gap < hold,
			"el hueco transitorio de %s (%.2fs) cabe en el holdoff de %.1fs" % [
				light_name, gap, hold])

	# Y el caso que hay que seguir culleando: TvLight en prelude, a cero hasta
	# el final del clip, o sea sin hueco transitorio ninguno.
	var prelude: String = _clip(text, "Animation_odjyq")
	if prelude == "":
		prelude = _clip_by_name(text, "101_prelude")
	_check(prelude != "", "101_prelude se localiza")
	if prelude != "":
		_check(_longest_transient_gap(prelude, "TvLight") <= 0.0,
			"TvLight se queda a cero hasta el final de prelude")


func _clip(text: String, id: String) -> String:
	var start: int = text.find('[sub_resource type="Animation" id="%s"]' % id)
	if start == -1:
		return ""
	var stop: int = text.find("\n[sub_resource", start + 10)
	if stop == -1:
		stop = text.length()
	return text.substr(start, stop - start)


func _clip_by_name(text: String, clip_name: String) -> String:
	var at: int = text.find('&"%s": SubResource("' % clip_name)
	if at == -1:
		return ""
	at += ('&"%s": SubResource("' % clip_name).length()
	var end: int = text.find('"', at)
	if end == -1:
		return ""
	return _clip(text, text.substr(at, end - at))


## El hueco a cero mas largo que vuelve a subir dentro del clip. Un tramo a
## cero que llega al final NO cuenta: ese es exactamente el caso que el pase
## debe seguir culleando.
func _longest_transient_gap(clip: String, light_name: String) -> float:
	var needle: String = "%s:light_energy\")" % light_name
	var at: int = clip.find(needle)
	if at == -1:
		return -1.0
	var times: PackedFloat32Array = _floats(clip, at, '"times": PackedFloat32Array(', ")")
	var values: PackedFloat32Array = _floats(clip, at, '"values": [', "]")
	if times.size() != values.size() or times.is_empty():
		return -1.0

	var longest: float = 0.0
	var index: int = 0
	while index < values.size():
		if values[index] > 0.0:
			index += 1
			continue
		var last: int = index
		while last + 1 < values.size() and values[last + 1] <= 0.0:
			last += 1
		if last + 1 < values.size():
			longest = maxf(longest, times[last + 1] - times[index])
		index = last + 1
	return longest


func _floats(clip: String, from: int, opener: String, closer: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var start: int = clip.find(opener, from)
	if start == -1:
		return out
	start += opener.length()
	var end: int = clip.find(closer, start)
	if end == -1:
		return out
	for piece: String in clip.substr(start, end - start).split(","):
		var trimmed: String = piece.strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed.to_float())
	return out


## Una linea comentada no cuenta. Estas funciones se nombran a si mismas en sus
## propios comentarios de documentacion, asi que un `contains` crudo pasa sobre
## el comentario que explica la regla en vez de sobre la regla.
func _has_statement(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK   %s" % label)
		return
	_failures += 1
	print("  FAIL %s" % label)
