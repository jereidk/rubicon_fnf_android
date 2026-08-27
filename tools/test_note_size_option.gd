extends SceneTree

## La fila "Note Size", y por que hace falta habiendo ya un `player_note_scale`
## en cada disposicion.
##
## Reportado por un jugador: "las flechas v-slice son pequeñas". No es cuestion
## de gusto, la geometria lo dice. Una nota es una region de 52x84 del atlas
## (`nte_default_hypno.tres`) dibujada a la escala 1.25 que autora la propia
## lane, o sea unos 65x105 sobre el lienzo de 1920x1080, y los carriles van a
## un paso de 160px (`sng_chimera.tscn` los pone en -240/-80/+80/+240):
##
##   Classic   nota 65px sobre paso 160px    41% del carril
##   VSlice    nota 81px sobre paso 277px    29% del carril
##
## VSlice separa los carriles x1.73 y agranda las notas solo x1.25, asi que es
## la propia disposicion la que las hace parecer mas pequeñas. Y hay sitio de
## sobra: a x2.0 VSlice llega al 58% del paso y Classic al 81%, o sea que el
## tope de la fila no llega a solapar en ninguna de las dos.
##
## El ajuste **multiplica** lo que pida la disposicion en vez de sustituirlo,
## que es lo que deja intacto el strumline deliberadamente pequeño del
## oponente de VSlice (0.62) en lugar de aplanar los dos al mismo numero.
##
## Correr con:
##   godot --headless --path . --script tools/test_note_size_option.gd

const SETTINGS := "res://menus/settings.gd"
const APPLIER := "res://lullaby_mod/scripts/lullaby/settings/lullaby_note_layout_applier.gd"
const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"
const CSV := "res://lullaby_mod/resources/localization/ui_strings.csv"
const VSLICE := "res://lullaby_mod/resources/note_layouts/ntl_vslice.tres"
const CLASSIC := "res://lullaby_mod/resources/note_layouts/ntl_classic.tres"

const ROW_LABEL := "Note Size: x"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_setting_checks()
	_applier_checks()
	_console_checks()
	_geometry_checks()

	print("note size option: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _setting_checks() -> void:
	var src: String = _read(SETTINGS)
	_check(src != "", "settings.gd se lee")

	# El prefijo no es cosmetico: save()/load_from() solo persisten
	# lullaby_/graphics_/audio_/game_/display_, asi que un nombre sin prefijo
	# se olvidaria en cada arranque.
	_check(_has_statement(src, "var lullaby_note_size: float = 1.0"),
		"el ajuste existe, a x1.0 por defecto y con prefijo lullaby_")

	# Y no debe entrar en la escalera de calidad: es una preferencia del
	# jugador, no un peldaño de rendimiento, o la fila de preset diria
	# "Custom" en cuanto alguien agrandase sus flechas.
	var preset: String = _read("res://lullaby_mod/scripts/lullaby/settings/lullaby_quality_preset.gd")
	_check(not preset.contains("note_size"),
		"y NO es campo del preset de calidad, o cambiarlo diria 'Custom'")


func _applier_checks() -> void:
	var src: String = _read(APPLIER)
	_check(src != "", "el applier se lee")

	# Multiplica, no sustituye. Las dos lineas, porque el oponente es
	# justamente el que se perderia si alguien "simplifica" esto a un valor
	# unico: VSlice lo autora a 0.62 a proposito.
	_check(_has_statement(src, "layout.player_note_scale * size"),
		"el tamaño multiplica lo que pide la disposicion (jugador)")
	_check(_has_statement(src, "layout.opponent_note_scale * size"),
		"...y tambien el del oponente, que VSlice achica a proposito")
	_check(_has_statement(src, "Settings.lullaby_note_size"),
		"y sale del ajuste, no de una constante")

	# Un cero deja las flechas invisibles y sin forma de recuperarlas desde
	# una consola que tambien esta dibujada con notas.
	_check(_has_statement(src, "maxf(0.1, Settings.lullaby_note_size)"),
		"con suelo, o un 0 guardado dejaria las notas invisibles")

	# Y tiene que re-aplicarse al tocar la fila, no solo al cargar la escena.
	_check(_has_statement(src, "Settings.applied.connect(_apply_to_current_scene)"),
		"se re-aplica al cambiar el ajuste, no solo al cargar")


func _console_checks() -> void:
	var scene: String = _read(CONSOLE)
	_check(scene != "", "console.tscn se lee")

	var at: int = scene.find('[node name="NoteSize"')
	_check(at != -1, "la fila NoteSize existe en la consola")
	if at == -1:
		return
	var stop: int = scene.find("\n[node ", at + 10)
	if stop == -1:
		stop = scene.length()
	var row: String = scene.substr(at, stop - at)

	_check(row.contains('property = &"lullaby_note_size"'),
		"apunta al ajuste")
	_check(row.contains('text = "%s"' % ROW_LABEL),
		"y se llama como la clave de traduccion")
	_check(row.contains("value_min = 0.75") and row.contains("value_max = 2.0"),
		"con un rango que no solapa carriles (0.75 - 2.0)")
	_check(row.contains("increment_amount = 0.25"),
		"y pasos de 0.25, como la fila de zona tactil de al lado")

	# Los vecinos de foco, en las dos direcciones. Una fila insertada en
	# medio de una columna sin recablear deja un agujero por el que el mando
	# se salta la fila entera.
	_check(row.contains('focus_neighbor_top = NodePath("../NoteLayout")'),
		"su vecino de arriba es NoteLayout")
	_check(row.contains('focus_neighbor_bottom = NodePath("../MobileKeyboardType")'),
		"y el de abajo MobileKeyboardType")
	_check(_neighbour(scene, "NoteLayout", "focus_neighbor_bottom") == "../NoteSize",
		"NoteLayout baja a NoteSize")
	_check(_neighbour(scene, "MobileKeyboardType", "focus_neighbor_top") == "../NoteSize",
		"y MobileKeyboardType sube a NoteSize")

	# Traducida en los dos idiomas que este proyecto envia.
	var csv: String = _read(CSV)
	var line: String = ""
	for candidate: String in csv.split("\n"):
		if candidate.begins_with(ROW_LABEL + ","):
			line = candidate
			break
	_check(line != "", "la etiqueta esta en el CSV")
	_check(line.split(",").size() >= 3 and not line.split(",")[1].strip_edges().is_empty(),
		"con traduccion al español")
	_check(line.split(",").size() >= 3 and not line.split(",")[2].strip_edges().is_empty(),
		"y al portugues")


## El motivo, re-derivado de los datos en vez de repetido de un comentario. Si
## alguien reespacia los carriles o cambia el atlas de notas, el numero que
## justifica esta fila cambia con ellos y el guard lo dice.
func _geometry_checks() -> void:
	var lane_pitch: float = _lane_pitch()
	_check(lane_pitch > 0.0, "el paso entre carriles se lee de la cancion (%.0fpx)" % lane_pitch)

	var note_width: float = _note_width()
	_check(note_width > 0.0, "el ancho de la nota se lee del atlas (%.0fpx)" % note_width)
	if lane_pitch <= 0.0 or note_width <= 0.0:
		return

	var classic: Resource = load(CLASSIC)
	var vslice: Resource = load(VSLICE)
	_check(classic != null and vslice != null, "las dos disposiciones cargan")
	if classic == null or vslice == null:
		return

	# A x1 las flechas ocupan menos de la mitad de su carril en las dos, que
	# es la queja del jugador expresada como numero.
	var classic_fill: float = (note_width * classic.player_note_scale) / lane_pitch
	var vslice_fill: float = (note_width * vslice.player_note_scale) \
		/ (lane_pitch * vslice.player_spacing_scale)
	_check(classic_fill < 0.5,
		"a x1 Classic llena el %.0f%% del carril" % (classic_fill * 100.0))
	_check(vslice_fill < classic_fill,
		"y VSlice llena MENOS (%.0f%%), que es por que se ven pequeñas" % (vslice_fill * 100.0))

	# Y el tope de la fila sigue sin solapar en ninguna de las dos.
	var top: float = 2.0
	_check(classic_fill * top < 1.0,
		"al tope x%.2f Classic sigue en el %.0f%%, sin solapar" % [top, classic_fill * top * 100.0])
	_check(vslice_fill * top < 1.0,
		"y VSlice en el %.0f%%" % (vslice_fill * top * 100.0))


## Paso entre carriles, de los offsets que la cancion autora en Lane0/Lane1.
func _lane_pitch() -> float:
	var song: String = _read("res://lullaby_mod/songs/chimera/sng_chimera.tscn")
	var zero: float = _lane_offset(song, "Lane0")
	var one: float = _lane_offset(song, "Lane1")
	if is_nan(zero) or is_nan(one):
		return -1.0
	return absf(one - zero)


func _lane_offset(song: String, lane: String) -> float:
	var at: int = song.find('[node name="%s" parent="UILayer/GameUI/Player"' % lane)
	if at == -1:
		return NAN
	var key: int = song.find("offset_left = ", at)
	if key == -1:
		return NAN
	key += "offset_left = ".length()
	var end: int = song.find("\n", key)
	return song.substr(key, end - key).to_float()


## Ancho de la nota: la primera region del atlas por la escala que la lane
## autora sobre su AnimatedSprite2D.
func _note_width() -> float:
	var atlas: String = _read("res://lullaby_mod/assets/funkin/global/notes/nte_default_hypno.tres")
	var at: int = atlas.find("region = Rect2(")
	if at == -1:
		return -1.0
	at += "region = Rect2(".length()
	var end: int = atlas.find(")", at)
	var parts: PackedStringArray = atlas.substr(at, end - at).split(",")
	if parts.size() < 3:
		return -1.0

	var lane: String = _read("res://lullaby_mod/resources/funkin/ui/hypno/lne_default_hypno.tscn")
	var scale_at: int = lane.find("scale = Vector2(")
	if scale_at == -1:
		return -1.0
	scale_at += "scale = Vector2(".length()
	var scale_end: int = lane.find(",", scale_at)
	return parts[2].strip_edges().to_float() * lane.substr(scale_at, scale_end - scale_at).to_float()


func _neighbour(scene: String, node: String, side: String) -> String:
	var at: int = scene.find('[node name="%s"' % node)
	if at == -1:
		return ""
	var stop: int = scene.find("\n[node ", at + 10)
	if stop == -1:
		stop = scene.length()
	var row: String = scene.substr(at, stop - at)
	var key: int = row.find('%s = NodePath("' % side)
	if key == -1:
		return ""
	key += ('%s = NodePath("' % side).length()
	return row.substr(key, row.find('"', key) - key)


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
