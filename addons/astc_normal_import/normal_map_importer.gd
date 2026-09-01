@tool
extends EditorImportPlugin

## Imports normal map PNGs as ASTC textures compressed with
## ASTCENC_FLG_MAP_NORMAL, which Godot's built-in "texture" importer never
## sets (see modules/astcenc/image_compress_astcenc.cpp in Godot's own
## source - it always compresses as generic RGBA regardless of content).
## For a normal map this flag alone is worth ~20dB of PSNR at the exact same
## bitrate, because it optimizes for angular error on the X/Y components
## instead of linear RGBA error on channels that don't carry independent
## information (Z is reconstructable from X/Y).
##
## Delegates the actual block encoding to tools/astc_compress (a standalone
## helper built from the same vendored astcenc library Godot itself uses,
## see tools/astc_compress/astc_compress.cpp) because Image.compress() does
## not expose ASTCENC_FLG_MAP_NORMAL or a quality parameter to scripting.

const ASTC_COMPRESS_REL_PATH := "res://tools/astc_compress/astc_compress"

## Godot 4.7.1's Image::Format only exposes ASTC_4x4 and ASTC_8x8 to
## GDScript - ASTC_10x10/ASTC_12x12 don't exist in this version (they were
## added later). Referencing a nonexistent Image.FORMAT_* constant is a
## GDScript compile error, which silently fails the whole plugin's
## _enter_tree() and leaves the importer unregistered - Godot then falls
## back to whatever default importer handles the extension, with no error
## surfaced anywhere obvious. This dict used to list all four block sizes
## (unused ones included "for completeness") and that alone was enough to
## break compilation and silently disable this importer in every CI run so
## far, despite this importer only ever using block=4 at runtime.
const _FORMAT_BY_BLOCK := {
	4: Image.FORMAT_ASTC_4x4,
	8: Image.FORMAT_ASTC_8x8,
}


func _get_importer_name() -> String:
	return "lullaby.astc_normal_map"


func _get_visible_name() -> String:
	return "Normal Map (ASTC, angular error)"


func _get_recognized_extensions() -> PackedStringArray:
	return ["png"]


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Texture2D"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_priority() -> float:
	# Never outrank the built-in texture importer as a default; this
	# importer is only used for files whose .import explicitly names it.
	return 0.0


func _get_import_order() -> int:
	return 0


func _can_import_threaded() -> bool:
	return true


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [
		{"name": "compress/block_size", "default_value": 4},
		{"name": "compress/quality", "default_value": 100.0},
		{"name": "mipmaps/generate", "default_value": true},
		# El lado largo, acotado. 0 = no tocar. Gemela de la de
		# astc_sprite_import; alli esta el porque y la trampa de los atlas, que
		# aqui no aplica porque esto solo entra en mapas normales de modelos 3D.
		{"name": "resize/max_size", "default_value": 0},
	]


func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var block: int = int(options.get("compress/block_size", 4))
	if not _FORMAT_BY_BLOCK.has(block):
		push_error("astc_normal_map: unsupported block size %d (must be 4 or 8 - this Godot version has no larger ASTC Image::Format)" % block)
		return ERR_INVALID_PARAMETER
	var quality: float = float(options.get("compress/quality", 100.0))
	var want_mipmaps: bool = bool(options.get("mipmaps/generate", true))

	var tool_path := ProjectSettings.globalize_path(ASTC_COMPRESS_REL_PATH)
	if not FileAccess.file_exists(tool_path):
		push_error("astc_normal_map: helper binary not found at %s - build it first (see tools/astc_compress/)" % tool_path)
		return ERR_FILE_NOT_FOUND

	var img := Image.new()
	var err := img.load(source_file)
	if err != OK:
		push_error("astc_normal_map: failed to load %s (%s)" % [source_file, err])
		return err
	img.convert(Image.FORMAT_RGBA8)

	# Antes de generar los mips, para que los mips salgan del tamaño final y no
	# se tire el trabajo del nivel 0.
	var max_size: int = int(options.get("resize/max_size", 0))
	var longest: int = maxi(img.get_width(), img.get_height())
	if max_size > 0 and longest > max_size:
		var factor: float = float(max_size) / float(longest)
		img.resize(
			maxi(1, int(round(float(img.get_width()) * factor))),
			maxi(1, int(round(float(img.get_height()) * factor))),
			Image.INTERPOLATE_LANCZOS)

	var w := img.get_width()
	var h := img.get_height()
	var padded_w := w if w % block == 0 else w + (block - (w % block))
	var padded_h := h if h % block == 0 else h + (block - (h % block))
	if padded_w != w or padded_h != h:
		img.resize(padded_w, padded_h)

	if want_mipmaps:
		img.generate_mipmaps(true) # renormalize=true: correct for normal data
	var mip_count := img.get_mipmap_count() if want_mipmaps else 0

	var raw_data := img.get_data()
	var tmp_dir := ProjectSettings.globalize_path("res://.godot/astc_tmp/")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tag := str(source_file.hash()) + "_" + str(OS.get_process_id()) + "_" + str(Time.get_ticks_usec())
	var tmp_in := tmp_dir + tag + ".rgba"
	var tmp_out := tmp_dir + tag + ".astc"

	var compressed := PackedByteArray()
	for i in range(mip_count + 1):
		var mip_w: int = max(1, padded_w >> i)
		var mip_h: int = max(1, padded_h >> i)
		var start: int = img.get_mipmap_offset(i) if i > 0 else 0
		var end: int = img.get_mipmap_offset(i + 1) if i < mip_count else raw_data.size()
		var mip_slice := raw_data.slice(start, end)

		var f := FileAccess.open(tmp_in, FileAccess.WRITE)
		if f == null:
			push_error("astc_normal_map: cannot write temp file %s" % tmp_in)
			return ERR_CANT_CREATE
		f.store_buffer(mip_slice)
		f.close()

		var output: Array = []
		var exit_code := OS.execute(tool_path, [
			tmp_in, str(mip_w), str(mip_h), str(block), str(block), str(quality), "normal", tmp_out,
		], output, true)
		if exit_code != 0:
			push_error("astc_normal_map: astc_compress failed on mip %d of %s: %s" % [i, source_file, output])
			return ERR_COMPILATION_FAILED

		var out_f := FileAccess.open(tmp_out, FileAccess.READ)
		if out_f == null:
			push_error("astc_normal_map: missing compressor output %s" % tmp_out)
			return ERR_FILE_NOT_FOUND
		compressed.append_array(out_f.get_buffer(out_f.get_length()))
		out_f.close()

	DirAccess.remove_absolute(tmp_in)
	DirAccess.remove_absolute(tmp_out)

	var final_img := Image.new()
	final_img.set_data(padded_w, padded_h, want_mipmaps, _FORMAT_BY_BLOCK[block], compressed)

	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(final_img, PortableCompressedTexture2D.COMPRESSION_MODE_ASTC, true, 0.8)

	return ResourceSaver.save(tex, save_path + "." + _get_save_extension())
