extends SceneTree

## Reescribe las rutas de hueso de `misc/jumpscare_short`, que apuntan al rig de
## Blender y no al esqueleto importado.
##
## El sintoma, tal como se reporto: al hacer Hex su jumpscare, su modelo se queda
## congelado, la camara no se mueve y no aparece la cabeza.
##
## La causa: el importador GLTF de Godot sustituye los puntos de los nombres de
## hueso de Blender por guiones bajos. `BackDress.L.001` entra al proyecto como
## `BackDress_L_001`. Las diecinueve animaciones de Hex usan los nombres
## convertidos - menos esta, que conservo los de Blender. De sus 115 pistas, 107
## apuntan a huesos que no existen, asi que no mueven nada y lo hacen EN
## SILENCIO: una pista de hueso que no resuelve no da error, ni al cargar ni al
## reproducir.
##
## Por eso no se veia leyendo la escena. Todo lo que se puede comprobar por texto
## salia bien: la animacion existe, esta en la libreria, la libreria resuelve por
## uid, las pistas de los clips que la disparan resuelven, y las texturas estan.
## Lo que fallaba estaba un nivel mas abajo - el nombre del hueso DENTRO de la
## ruta - y eso solo se ve reproduciendo la animacion y mirando si el esqueleto
## se mueve:
##
##     misc/jumpscare_short   115 pistas   cambios de pose por tramo: [2, 5, 5, 6]
##     misc/closeup           128 pistas   cambios de pose por tramo: [83, 83, 83, 79]
##     misc/reveal            103 pistas   cambios de pose por tramo: [44, 44, 44, 44]
##
## La conversion es exacta y no se adivina nada: para cada hueso que no existe se
## comprueba que el nombre con guiones SI este en el esqueleto, y solo entonces
## se cambia. De las 107 rotas, las 107 tienen pareja. Si alguna no la tuviera,
## esto se para sin escribir.
##
## Run with:
##   godot --headless --path . --script tools/fix_hex_jumpscare_bones.gd
##   godot --headless --path . --script tools/fix_hex_jumpscare_bones.gd -- --dry-run

const HEX := "res://lullaby_mod/assets/funkin/chimera/models/hex/hex.tscn"
const LIBRARY := "res://lullaby_mod/resources/animations/hex/hex_misc_anim_library.res"
const ANIM := &"jumpscare_short"

## El uid que la libreria traia. Se conserva escrito porque el intento de
## preservarlo NO funciono y conviene que conste.
##
## ResourceSaver escribe el uid que ResourceFormatSaverBinary saca de
## `get_resource_id_for_path()`, y esa funcion consulta el cache de uid del
## proyecto antes que nada. Poner el mapeo con ResourceUID.add_id() justo antes
## de guardar llega tarde: el fichero salio con `uid://hy20gd3ren0rr` las dos
## veces que se probo - el mismo valor, o sea que no es aleatorio, viene del
## cache que la primera pasada ya habia escrito.
##
## Como el unico que referenciaba esta libreria era hex.tscn -comprobado por
## texto y tambien decodificando todos los .res del arbol-, se actualizo ahi el
## uid en vez de pelearse con el cache. Si esta herramienta se vuelve a correr y
## el uid cambia otra vez, hay que actualizar hex.tscn igual.
const OLD_UID := "uid://ccbuccrfnilgm"


func _initialize() -> void:
	var dry: bool = OS.get_cmdline_user_args().has("--dry-run")

	# El esqueleto real, para no inventarse el destino de ninguna pista.
	var hex: Node = (load(HEX) as PackedScene).instantiate()
	root.add_child(hex)
	var skel: Skeleton3D = _find_skeleton(hex)
	if skel == null:
		printerr("no encuentro el Skeleton3D de Hex")
		quit(1)
		return

	var bones: Dictionary = {}
	for i: int in skel.get_bone_count():
		bones[skel.get_bone_name(i)] = true
	print("OUT esqueleto con %d huesos" % bones.size())

	var library: AnimationLibrary = load(LIBRARY)
	if library == null or not library.has_animation(ANIM):
		printerr("la libreria no trae %s" % ANIM)
		quit(1)
		return

	var anim: Animation = library.get_animation(ANIM)
	var fixed: int = 0
	var stuck: PackedStringArray = []

	for i: int in anim.get_track_count():
		var path: String = String(anim.track_get_path(i))
		if not path.contains(":"):
			continue
		var node: String = path.get_slice(":", 0)
		var bone: String = path.get_slice(":", 1)
		if bones.has(bone):
			continue

		var candidate: String = bone.replace(".", "_")
		if not bones.has(candidate):
			stuck.append(bone)
			continue
		if not dry:
			anim.track_set_path(i, NodePath("%s:%s" % [node, candidate]))
		fixed += 1

	print("OUT %d pistas reapuntadas, %d sin pareja" % [fixed, stuck.size()])
	if not stuck.is_empty():
		printerr("sin pareja: %s" % ", ".join(stuck.slice(0, 10)))
		printerr("no se escribe nada: la conversion tiene que ser completa")
		quit(1)
		return

	if dry:
		print("OUT (dry-run, no se escribe)")
		quit(0)
		return

	# El uid, ANTES de guardar y no como adorno.
	#
	# ResourceSaver escribe en la cabecera el uid que ResourceUID tenga para esa
	# ruta, y si no tiene ninguno GENERA UNO NUEVO. Sin esto el fichero salio con
	# `uid://hy20gd3ren0rr` mientras hex.tscn seguia pidiendo
	# `uid://ccbuccrfnilgm`: Godot cae entonces a la ruta de texto, que aqui es
	# correcta, pero deja el aviso "invalid UID" y una referencia que solo
	# aguanta mientras nadie mueva el fichero.
	var keep: int = ResourceUID.text_to_id(OLD_UID)
	if ResourceUID.has_id(keep):
		ResourceUID.set_id(keep, LIBRARY)
	else:
		ResourceUID.add_id(keep, LIBRARY)

	# FLAG_COMPRESS porque asi estaba: el fichero es `RSCC` y no hay razon para
	# devolverlo al triple de tamaño.
	var err: int = ResourceSaver.save(library, LIBRARY, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		printerr("no se pudo guardar: %d" % err)
		quit(1)
		return
	print("OUT guardado %s" % LIBRARY)
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
