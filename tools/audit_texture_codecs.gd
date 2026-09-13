extends SceneTree

## Que codec usa cada textura del proyecto, y cuanto queda en Basis Universal.
##
## Basis se TRANSCODIFICA en la CPU al cargar, y el coste que domina la carga de
## este proyecto es exactamente ese: trabajo por recurso y no por byte
## (audit_load_time.gd mide la tienda 1,6x el peso de Safety Lullaby en
## escritorio y trece veces el reloj en el telefono). Asi que saber cuanto queda
## en ese camino es la pregunta, y esta herramienta la contesta en una pasada.
##
## POR QUE LOS MB DE DISCO NO SIRVEN COMO MEDIDA. Es el error que esta
## herramienta evita, y se cometio: `OptionsBox.png` pesa 0,03 MB y son
## 2048x2048 = 4,19 Mpx; `stageback.png` pesa 0,01 MB y son 3,58 Mpx. PNG
## comprime lo plano a nada, pero transcodificar cuesta por PIXEL. Por eso la
## columna que manda aqui es Mpx.
##
## LO QUE SE MIDIO SOBRE CONVERTIR EL RESTO A ASTC, para que nadie lo repita a
## ciegas. Se convirtieron 12 texturas a lullaby.astc_sprite, se importaron, y
## el resultado fue el contrario del esperado:
##
##     salida en disco   Basis 6,4 MB  ->  ASTC 15,8 MB   (+9,4 MB de APK)
##
## Basis va supercomprimido en disco y se expande al cargar; ASTC es el formato
## de GPU crudo, 2 bpp fijos. Y el tiempo, medido con un renderizador de verdad
## (xvfb + opengl3, porque en `--headless` el renderizador dummy no sube nada a
## GPU y el transcode ni ocurre - un banco hecho asi no mide nada):
##
##     siete texturas, segunda pasada    Basis 473,0 ms   ASTC 557,6 ms
##     de las cuales special_anims-2     Basis 198,6 ms   ASTC 332,9 ms
##
## O sea que ASTC salio MAS LENTO. La medida no traslada tal cual al telefono -
## aqui el adaptador es llvmpipe, Basis transcodifica a BPTC y el Adreno 619
## tiene ASTC nativo, que es el caso favorable a ASTC - pero es evidencia EN
## CONTRA de la suposicion, no a favor, y el coste de +9,4 MB si es cierto. Con
## eso, convertir no esta justificado sin medirlo en el dispositivo.
##
## Y un detalle que salio de ahi y merece mirarse aparte: el importador ASTC
## produce `PortableCompressedTexture2D` (sprite_importer.gd:244), no
## `CompressedTexture2D`. Esa clase se adapta a la plataforma en tiempo de
## carga, asi que el camino ASTC tampoco es necesariamente gratis.
##
## Lo que SI se hizo, porque no tenia contrapartida: ocho SpriteFrames dejaron de
## trocear el arbol legado y trocean su gemela identica de al lado, que ya estaba
## en ASTC o sin perdida. Ver tools/repoint_atlas_to_sibling.gd. Eso saco 13
## texturas del camino Basis sin sumar un byte.
##
## Run with:
##   godot --headless --path . --script tools/audit_texture_codecs.gd

const ROOTS: Array[String] = ["res://assets", "res://lullaby_mod", "res://resources",
	"res://menus", "res://levels", "res://addons"]


func _initialize() -> void:
	var by_codec: Dictionary = {}     # codec -> [n, bytes_png, megapixels]
	var basis: Array = []

	for root: String in ROOTS:
		_scan(root, by_codec, basis)

	var codecs: Array = by_codec.keys()
	codecs.sort()
	print("%-24s %6s %12s %12s" % ["codec", "n", "MB origen", "Mpx"])
	for c: String in codecs:
		var e: Array = by_codec[c]
		print("%-24s %6d %12.1f %12.1f" % [c, e[0], e[1] / 1e6, e[2] / 1e6])

	basis.sort_custom(func(a, b): return a[0] > b[0])
	var total_px: int = 0
	for e: Array in basis:
		total_px += int(e[0])
	print("\nBasis Universal (transcodifica en CPU al cargar): %d ficheros, %.1f Mpx"
		% [basis.size(), total_px / 1e6])
	for e: Array in basis:
		print("   %8.2f Mpx  %-6s %s" % [int(e[0]) / 1e6, e[1], e[2]])

	print("\nMpx es la columna que importa, no los MB: transcodificar cuesta por")
	print("pixel, y un PNG plano de 2048x2048 puede pesar 0,03 MB en disco.")
	print("")
	print("Esta lista es el INVENTARIO, no lo que se carga: varias de arriba ya no")
	print("las referencia nadie desde que repoint_atlas_to_sibling.gd movio ocho")
	print("SpriteFrames. Quien las alcanza lo dice tools/audit_legacy_assets.gd,")
	print("que pregunta las dependencias al motor en vez de buscar cadenas.")
	quit(0)


func _scan(dir_path: String, by_codec: Dictionary, basis: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan(full, by_codec, basis)
		elif name.ends_with(".import"):
			_one(full, by_codec, basis)
		name = dir.get_next()
	dir.list_dir_end()


func _one(import_path: String, by_codec: Dictionary, basis: Array) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return
	var importer: String = str(cfg.get_value("remap", "importer", ""))
	if importer == "":
		return

	var codec: String = importer
	var is_basis: bool = false
	if importer == "texture":
		var mode: int = int(cfg.get_value("params", "compress/mode", -1))
		codec = "texture/mode=%d%s" % [mode, _mode_name(mode)]
		is_basis = mode == 4
	else:
		codec = importer.replace("lullaby.", "")

	var source: String = import_path.substr(0, import_path.length() - 7)
	var bytes: int = FileAccess.get_file_as_bytes(source).size()
	var px: int = _pixels(source)

	if not by_codec.has(codec):
		by_codec[codec] = [0, 0, 0]
	var e: Array = by_codec[codec]
	e[0] += 1
	e[1] += bytes
	e[2] += px

	if is_basis and px > 0:
		var hq: bool = bool(cfg.get_value("params", "compress/high_quality", false))
		basis.append([px, "UASTC" if hq else "ETC1S", source])


func _mode_name(mode: int) -> String:
	match mode:
		0: return " (sin perdida)"
		1: return " (con perdida)"
		2: return " (VRAM comprimida)"
		3: return " (VRAM sin comprimir)"
		4: return " (Basis Universal)"
	return ""


## Ancho x alto leidos de la cabecera IHDR del PNG, sin cargar la imagen.
##
## Cargarla costaria descomprimirla entera, y de 1500 texturas eso son minutos
## para un dato que estan los primeros 24 bytes del fichero.
func _pixels(path: String) -> int:
	if not path.ends_with(".png"):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 24:
		return 0
	f.seek(16)
	f.big_endian = true
	var w: int = f.get_32()
	var h: int = f.get_32()
	if w <= 0 or h <= 0 or w > 65536 or h > 65536:
		return 0
	return w * h
