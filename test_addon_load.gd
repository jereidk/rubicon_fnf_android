extends SceneTree

const ADDON_DIR := "/storage/emulated/0/.WashosEngine/addons/gdanimate"
const PCK_PATH := "user://test_gdanimate.pck"

const SCRIPTS := [
	"adobe/adobe_color_matrix.gd",
	"adobe/adobe_drawable.gd",
	"adobe/adobe_symbol.gd",
	"adobe/adobe_symbol_instance.gd",
	"adobe/adobe_button_instance.gd",
	"adobe/adobe_filter.gd",
	"adobe/adobe_layer_frame.gd",
	"adobe/adobe_layer.gd",
	"adobe/adobe_sprite_element.gd",
	"adobe/adobe_atlas_sprite.gd",
	"animate_draw_info.gd",
	"animate_atlas.gd",
	"animate_symbol.gd",
	"adobe/adobe_atlas.gd",
	"adobe/adobe_atlas_cached.gd",
	"adobe/adobe_animate_controller.gd",
]

func _init() -> void:
	print("=== TEST ADDON LOAD ===")
	if not DirAccess.dir_exists_absolute(ADDON_DIR):
		print("FAIL: no existe ", ADDON_DIR)
		quit(1)
		return

	var files := _walk(ADDON_DIR)
	print("Empaquetando ", PCK_PATH, " (", files.size(), " archivos)")
	var packer := PCKPacker.new()
	if packer.pck_start(PCK_PATH) != OK:
		print("FAIL: pck_start")
		quit(1)
		return
	var packed := 0
	var skip_ext := ["png","jpg","jpeg","webp","svg","ttf","otf","ogv","ktx","astc","glb","gltf","gdshader","ogg","mp3","wav"]
	for rel in files:
		if String(rel).get_extension().to_lower() in skip_ext:
			continue
		var err: int = packer.add_file("res://addons/gdanimate/" + String(rel), ADDON_DIR + "/" + String(rel))
		if err == OK:
			packed += 1
	if packer.flush(true) != OK:
		print("FAIL: flush")
		quit(1)
		return
	print("  ", packed, " archivos al pck")

	var ok: bool = ProjectSettings.load_resource_pack(PCK_PATH, true)
	print("load_resource_pack = ", ok)
	if not ok:
		quit(1)
		return

	for rel in SCRIPTS:
		var path := "res://addons/gdanimate/" + String(rel)
		var exists := ResourceLoader.exists(path)
		var rt := ""
		var t0 := Time.get_ticks_msec()
		var scr = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REUSE)
		var dt := Time.get_ticks_msec() - t0
		if scr != null:
			print("OK   ", rel, " | name=", scr.get_global_name(), " base=", scr.get_instance_base_type(), " methods=", scr.get_script_method_list().size(), " (", dt, "ms)")
		else:
			print("FAIL ", rel, " | exists=", exists, " rt='", rt, "' (", dt, "ms)")

	print("=== FIN ===")
	quit(0)

func _walk(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [""]
	while not stack.is_empty():
		var sub: String = stack.pop_back()
		var full := root if sub.is_empty() else root + "/" + sub
		var d := DirAccess.open(full)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".import") or f.ends_with(".uid") or f.ends_with(".bak"):
				continue
			out.append(f if sub.is_empty() else sub + "/" + f)
		for sd in d.get_directories():
			stack.append(sd if sub.is_empty() else sub + "/" + sd)
	return out

# (despues de los 16 OK, probar que un preload dynamic funciona)
