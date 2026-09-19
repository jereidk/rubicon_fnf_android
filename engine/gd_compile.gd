extends RefCounted

## Compila un .gd desde disco o desde un .pck montado, sin pasar por
## ResourceLoader. Necesario porque ResourceLoader.load() sobre un .gd
## dentro de un .pck devuelve un GDScript "hueco" (base RefCounted) en
## Android, y luego .new() no da un Node.
##
## Se usa desde:
##   - mod_loader.gd: para instalar los autoloads que un mod declara.
##     Con from_path_with_res_path(path_fisico, res_path) para que el
##     analyzer de GDScript resuelva los tipos del autoload (ver el
##     comentario de esa funcion).
##
## mod_selector.gd NO lo usa: tiene su propia _compile_gd_from_bytes()
## que hace lo mismo pero sin wrapper, porque necesita mas control
## (distingue .gd de .tscn en el main_scene).
static func from_path(path: String) -> GDScript:
	return from_path_with_res_path(path, "")


## Igual que from_path pero con un resource_path explicito. Necesario
## cuando el script se compila desde un path fisico (fuera de res://)
## pero el engine lo conoce por su path res://. Caso tipico: autoloads
## de mods, donde el archivo esta en /storage/... pero el analyzer lo
## busca como res://holyquintet_mod/scripts/hq_saves.gd.
##
## Por que importa take_over_path ANTES de reload: el analyzer de
## GDScript, cuando compila un script que hace `HQSaves.foo()`, busca
## el parser de hq_saves.gd con GDScriptCache::get_parser(). Esa funcion
## consulta primero shallow_gdscript_cache[path]. Si el script no esta
## ahi, intenta leer el source con FileAccess::open(path) - que en
## Android falla por razones sutiles de remap. Con take_over_path(path)
## antes del reload, Godot mete el script en el shallow cache (ver
## modules/gdscript/gdscript.cpp:781-783) y el analyzer lo encuentra.
##
## Si res_path esta vacio, se comporta como from_path (sin
## take_over_path). Retrocompatible con callers que ya usaban from_path.
static func from_path_with_res_path(path: String, res_path: String = "") -> GDScript:
	if not FileAccess.file_exists(path):
		return null
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return null
	var gd := GDScript.new()
	gd.source_code = src
	# take_over_path ANTES del reload: Godot solo pobla el cache si el
	# script tiene resource_path al momento del reload.
	if not res_path.is_empty():
		gd.take_over_path(res_path)
	if gd.reload() != OK:
		return null
	return gd
