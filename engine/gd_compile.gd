extends RefCounted

## Compila un .gd desde disco o desde un .pck montado, sin pasar por
## ResourceLoader. Necesario porque ResourceLoader.load() sobre un .gd
## dentro de un .pck devuelve un GDScript "hueco" (base RefCounted) en
## Android, y luego .new() no da un Node.
##
## Se usa desde:
##   - mod_selector.gd: para cargar el main_scene de un mod
##   - mod_loader.gd:   para instalar los autoloads que un mod declara
static func from_path(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		return null
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return null
	var gd := GDScript.new()
	gd.source_code = src
	if gd.reload() != OK:
		return null
	return gd
