extends SceneTree

## Ocho SpriteFrames del mod dejan de trocear el PNG del arbol legado y trocean
## el que tienen al lado, que es identico byte a byte.
##
## De donde sale esto
## ------------------
## El .error del dispositivo abre con ocho avisos de esta forma:
##
##     'res://lullaby_mod/assets/menus/console/options/portrait/settings_icons.res':
##     In external resource #0, invalid UID: 'uid://ca0j4knw2tj61'
##     - using text path instead:
##     'res://assets/collector/shop/console ui/Options/settings_icons.png'
##
## Son SpriteFrames cuyos AtlasTexture apuntan por uid a una textura que ya no
## existe con ese uid. Godot cae a la ruta textual, que sigue valiendo, asi que
## nada se rompe - pero la ruta textual va al arbol `res://assets/`, el de antes
## de mover el mod, y ALLI la textura esta importada con OTRO importador.
##
## Barriendo todo lullaby_mod son 17 .res, no 8: el log solo mostro los que se
## cargaron ese dia. De los 17, ocho tienen un PNG hermano al lado del .res que
## es identico byte a byte. Los otros nueve no se pueden repuntar - su textura
## solo existe en el arbol legado - y ahi el uid rancio se queda, que no cuesta
## mas que el aviso.
##
## Los ocho, y por que cada uno:
##
##   ConsoleStartup  OptionsBox  settings_icons  lil_ector  training_icons
##       legado texture/mode=4 (Basis Universal) -> vecina lullaby.astc_sprite.
##       Basis se TRANSCODIFICA en la CPU al cargar, que es el coste que domina
##       en este proyecto: la tienda mide 1,6x el peso de Safety Lullaby en
##       escritorio y trece veces el reloj en el telefono, o sea trabajo por
##       recurso y no por byte. Estas cinco suman 17,3 Mpx que salen de ahi, y
##       no cuestan un byte de APK porque el .res ASTC de la vecina ya existe y
##       ya se exporta (el preset exporta `all_resources`).
##
##   candle_fire
##       Al reves que las anteriores: la legada YA era astc_sprite (0,154 MB) y
##       la vecina era texture/mode=0 (0,346 MB), asi que repuntarla tal cual la
##       habria hecho el doble de grande. Se cambio el importador de la vecina a
##       astc_sprite y sale 0,154 MB, el mismo trato que la legada. Seguro
##       porque la vecina no la referenciaba nadie: cero usos en el proyecto.
##
##   Checkmark  SelectBox
##       Basis contra texture/mode=0, y aqui la SIN PERDIDA es mas pequena en
##       disco - 0,005 contra 0,008 MB y 0,001 contra 0,003 - porque son
##       imagenes diminutas de pocos colores y Basis no compensa su sobrecarga.
##       Menos disco, sin transcodificar y sin riesgo visual. Lo que cuesta es
##       VRAM: sin comprimir son RGBA crudos, 640 KB entre las dos contra unos
##       80 KB. Sobre los 59-70 MB que el log mide es un 1%, y se prefiere eso a
##       meter ASTC de 2 bpp en la marca de verificacion que el jugador tiene
##       delante todo el rato.
##
## Efecto medido sobre el arbol legado: de 32 ficheros y 87,4 MB alcanzables
## pasa a 24 y 85,7 MB.
##
## Por que es seguro
## -----------------
## Los AtlasTexture guardan su `region` en pixeles EXACTOS del original, asi que
## cambiar de atlas solo vale si el nuevo tiene los mismos pixeles. Por eso la
## condicion es identidad byte a byte del PNG y no "parecido" ni "mismo tamano",
## y por eso se vuelve a comprobar aqui dentro antes de escribir nada, ademas de
## las dimensiones del recurso importado y de que ninguna region se mueva. Es el
## mismo desastre silencioso que documenta
## tools/test_resize_never_breaks_atlases.gd: una region ligeramente mal no da
## error, sale un sprite descuadrado y nadie sabe por que.
##
## Run with:
##   godot --headless --path . --script tools/repoint_atlas_to_sibling.gd
##   ... -- escribir     (sin esto solo informa, no toca nada)

## .res -> PNG vecino que pasa a ser el atlas. La ruta legada que sustituye se
## lee del propio recurso, no se escribe aqui: si manana apunta a otro sitio, el
## que manda es el fichero.
const REPOINT := {
	"res://lullaby_mod/assets/menus/console/intro/ConsoleStartup.res":
		"res://lullaby_mod/assets/menus/console/intro/ConsoleStartup.png",
	"res://lullaby_mod/assets/menus/console/options/portrait/OptionsBox.res":
		"res://lullaby_mod/assets/menus/console/options/portrait/OptionsBox.png",
	"res://lullaby_mod/assets/menus/console/options/portrait/settings_icons.res":
		"res://lullaby_mod/assets/menus/console/options/portrait/settings_icons.png",
	"res://lullaby_mod/assets/menus/console/training/lil_ector.res":
		"res://lullaby_mod/assets/menus/console/training/lil_ector.png",
	"res://lullaby_mod/assets/menus/console/training/training_icons.res":
		"res://lullaby_mod/assets/menus/console/training/training_icons.png",

	# Los tres que la primera pasada dejo fuera, resueltos cada uno por su lado
	# despues de mirar los tamanos importados de verdad en vez de suponerlos:
	#
	#   candle_fire  la legada YA era astc_sprite (0,154 MB) y la vecina era
	#                texture/mode=0 (0,346 MB), asi que repuntar la habria hecho
	#                el doble de grande. Se cambio el importador de la vecina a
	#                astc_sprite y ahora sale 0,154 MB, byte por byte el mismo
	#                trato que la legada. Seguro porque la vecina no la
	#                referenciaba nadie: cero usos en todo el proyecto.
	#
	#   Checkmark    las dos son Basis contra texture/mode=0, y aqui la SIN
	#   SelectBox    PERDIDA es mas pequena en disco - 0,005 contra 0,008 MB y
	#                0,001 contra 0,003 - porque son imagenes diminutas de pocos
	#                colores y Basis no compensa su propia sobrecarga. O sea:
	#                menos disco, sin transcodificar, y sin ningun riesgo visual
	#                porque no hay perdida. Lo que cuesta es VRAM, que sin
	#                comprimir son RGBA crudos: 512x256 y 256x128 dan 640 KB
	#                contra unos 80 KB. Sobre los 59-70 MB que el log mide es un
	#                1%, y se prefiere eso a meter ASTC 2 bpp en la marca de
	#                verificacion que el jugador tiene delante todo el rato.
	"res://lullaby_mod/assets/collector/shop/candle_fire.res":
		"res://lullaby_mod/assets/collector/shop/candle_fire.png",
	"res://lullaby_mod/assets/menus/console/options/Checkmark.res":
		"res://lullaby_mod/assets/menus/console/options/Checkmark.png",
	"res://lullaby_mod/assets/menus/console/options/SelectBox.res":
		"res://lullaby_mod/assets/menus/console/options/SelectBox.png",
}

var _write: bool = false
var _failures: int = 0
var _pending: int = 0


## Sin `escribir` esto es un GUARD, no solo un informe: sale distinto de cero si
## queda algun repunte por hacer. Asi CI lo puede correr tal cual y cae el dia que
## alguien regenere uno de estos .res desde el arbol legado y lo devuelva a
## Basis sin que nada mas se entere.
func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "escribir":
			_write = true
	if not _write:
		print("MODO GUARD - nada se escribe. Anade `-- escribir` para aplicar.\n")

	for res_path: String in REPOINT:
		_do(res_path, REPOINT[res_path])

	if _failures > 0:
		print("\n%d FALLOS" % _failures)
	elif _write:
		print("\nhecho")
	elif _pending > 0:
		printerr("\n%d .res siguen troceando el arbol legado teniendo vecina identica"
			% _pending)
	else:
		print("\ntodo OK - ninguno trocea el arbol legado teniendo vecina al lado")
	quit(1 if (_failures > 0 or (not _write and _pending > 0)) else 0)


func _do(res_path: String, new_atlas_path: String) -> void:
	var sf: SpriteFrames = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as SpriteFrames
	if sf == null:
		_fail("%s no carga como SpriteFrames" % res_path)
		return

	var new_atlas: Texture2D = ResourceLoader.load(new_atlas_path) as Texture2D
	if new_atlas == null:
		_fail("%s no carga" % new_atlas_path)
		return

	# Lo que hay ahora, y cuantos.
	var old_paths: Dictionary = {}
	var frames: Array = []          # [anim, indice, AtlasTexture]
	for anim: StringName in sf.get_animation_names():
		for i: int in range(sf.get_frame_count(anim)):
			var t: Texture2D = sf.get_frame_texture(anim, i)
			if t is AtlasTexture:
				var at := t as AtlasTexture
				if at.atlas != null:
					old_paths[at.atlas.resource_path] = true
				frames.append([anim, i, at])

	if frames.is_empty():
		_fail("%s no tiene AtlasTexture" % res_path)
		return
	if old_paths.size() != 1:
		_fail("%s trocea %d atlas distintos, no uno: %s"
			% [res_path, old_paths.size(), str(old_paths.keys())])
		return

	var old_path: String = old_paths.keys()[0]
	if old_path == new_atlas_path:
		print("  ya apunta bien: %s" % res_path.get_file())
		return

	# La condicion de seguridad, comprobada aqui y no dada por supuesta: los dos
	# PNG tienen que ser el MISMO fichero, porque las regiones van en pixeles
	# exactos del original.
	var a: PackedByteArray = FileAccess.get_file_as_bytes(old_path)
	var b: PackedByteArray = FileAccess.get_file_as_bytes(new_atlas_path)
	if a.is_empty() or b.is_empty():
		_fail("no pude leer los PNG de %s" % res_path.get_file())
		return
	if a != b:
		_fail("%s: los dos PNG NO son identicos (%d vs %d bytes) - no se toca"
			% [res_path.get_file(), a.size(), b.size()])
		return

	# Y las dimensiones del recurso ya importado, que es lo que las regiones
	# indexan de verdad. Identicos los bytes esto no puede fallar, pero si
	# fallara seria justo el desastre silencioso que se quiere evitar.
	var old_atlas: Texture2D = (frames[0][2] as AtlasTexture).atlas
	if old_atlas.get_width() != new_atlas.get_width() \
			or old_atlas.get_height() != new_atlas.get_height():
		_fail("%s: %dx%d contra %dx%d" % [res_path.get_file(),
			old_atlas.get_width(), old_atlas.get_height(),
			new_atlas.get_width(), new_atlas.get_height()])
		return

	var regions_before: Array[Rect2] = []
	for f: Array in frames:
		regions_before.append((f[2] as AtlasTexture).region)

	for f: Array in frames:
		(f[2] as AtlasTexture).atlas = new_atlas

	# Las regiones no las toca nadie, pero comprobarlo cuesta cero y es el unico
	# dato que, si se moviera, no daria ningun error.
	for i: int in range(frames.size()):
		if not (frames[i][2] as AtlasTexture).region.is_equal_approx(regions_before[i]):
			_fail("%s: una region se movio al reasignar el atlas" % res_path.get_file())
			return

	_pending += 1
	print("  %-24s %3d AtlasTexture  %dx%d" % [res_path.get_file(), frames.size(),
		new_atlas.get_width(), new_atlas.get_height()])
	print("      de %s" % old_path)
	print("       a %s" % new_atlas_path)

	if not _write:
		return
	var err: int = ResourceSaver.save(sf, res_path)
	if err != OK:
		_fail("no pude guardar %s (%d)" % [res_path, err])


func _fail(what: String) -> void:
	_failures += 1
	printerr("  FALLO %s" % what)
