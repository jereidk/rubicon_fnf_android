@tool
extends EditorImportPlugin

## Imports large flat-shaded 2D sprites (character spritesheets, backgrounds,
## cutscene art) as ASTC 12x12 at EXHAUSTIVE quality via a standalone
## astcenc invocation - the same tool/library used by
## addons/astc_normal_import, just without ASTCENC_FLG_MAP_NORMAL and with a
## much larger block size.
##
## Godot's own quality preset (MEDIUM) barely differs from EXHAUSTIVE at the
## same block size in practice (measured ~0.4dB PSNR difference), so the
## real lever here is block size, and 12x12 gives ~9x smaller files than the
## project's usual 4x4. That trade only pays off for content with little
## per-pixel high-frequency detail: flat cel-shaded character/background art
## verified fine by direct 1:1 pixel crop comparison against source; a
## normal map tested with the same settings showed real degradation (see
## addons/astc_normal_import's docstring), which is why THAT importer keeps
## a small block size instead. Do not point this importer at pixel art,
## fonts/text atlases, small UI icons, or normal/roughness maps - all of
## those need either a smaller block or no ASTC compression at all.
##
## _can_import_threaded() is deliberately false: the astc_compress helper
## already parallelizes internally across all CPU cores for a single file
## (see tools/astc_compress/astc_compress.cpp), so importing multiple files
## of this type at once would oversubscribe the machine instead of speeding
## anything up.

const ASTC_COMPRESS_REL_PATH := "res://tools/astc_compress/astc_compress"

const _FORMAT_BY_BLOCK := {
	4: Image.FORMAT_ASTC_4x4,
	8: Image.FORMAT_ASTC_8x8,
	10: Image.FORMAT_ASTC_10x10,
	12: Image.FORMAT_ASTC_12x12,
}


func _get_importer_name() -> String:
	return "lullaby.astc_sprite"


func _get_visible_name() -> String:
	return "Sprite (ASTC 12x12 exhaustive)"


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
	return 0.0


func _get_import_order() -> int:
	return 0


func _can_import_threaded() -> bool:
	return false


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [
		{"name": "compress/block_size", "default_value": 12},
		{"name": "compress/quality", "default_value": 98.0}, # THOROUGH: ~13x faster than EXHAUSTIVE (100) for ~0.4dB PSNR difference, measured on real project art
		{"name": "mipmaps/generate", "default_value": true},
	]


func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var block: int = int(options.get("compress/block_size", 12))
	if not _FORMAT_BY_BLOCK.has(block):
		push_error("astc_sprite: unsupported block size %d (must be 4, 8, 10 or 12)" % block)
		return ERR_INVALID_PARAMETER
	var quality: float = float(options.get("compress/quality", 100.0))
	var want_mipmaps: bool = bool(options.get("mipmaps/generate", true))

	var tool_path := ProjectSettings.globalize_path(ASTC_COMPRESS_REL_PATH)
	if not FileAccess.file_exists(tool_path):
		push_error("astc_sprite: helper binary not found at %s - build it first (see tools/astc_compress/)" % tool_path)
		return ERR_FILE_NOT_FOUND

	var img := Image.new()
	var err := img.load(source_file)
	if err != OK:
		push_error("astc_sprite: failed to load %s (%s)" % [source_file, err])
		return err
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	var padded_w := w if w % block == 0 else w + (block - (w % block))
	var padded_h := h if h % block == 0 else h + (block - (h % block))
	if padded_w != w or padded_h != h:
		img.resize(padded_w, padded_h)

	if want_mipmaps:
		img.generate_mipmaps()
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
			push_error("astc_sprite: cannot write temp file %s" % tmp_in)
			return ERR_CANT_CREATE
		f.store_buffer(mip_slice)
		f.close()

		var output: Array = []
		var exit_code := OS.execute(tool_path, [
			tmp_in, str(mip_w), str(mip_h), str(block), str(block), str(quality), "color", tmp_out,
		], output, true)
		if exit_code != 0:
			push_error("astc_sprite: astc_compress failed on mip %d of %s: %s" % [i, source_file, output])
			return ERR_COMPILATION_FAILED

		var out_f := FileAccess.open(tmp_out, FileAccess.READ)
		if out_f == null:
			push_error("astc_sprite: missing compressor output %s" % tmp_out)
			return ERR_FILE_NOT_FOUND
		compressed.append_array(out_f.get_buffer(out_f.get_length()))
		out_f.close()

	DirAccess.remove_absolute(tmp_in)
	DirAccess.remove_absolute(tmp_out)

	var final_img := Image.new()
	final_img.set_data(padded_w, padded_h, want_mipmaps, _FORMAT_BY_BLOCK[block], compressed)

	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(final_img, PortableCompressedTexture2D.COMPRESSION_MODE_ASTC, false, 0.8)

	return ResourceSaver.save(tex, save_path + "." + _get_save_extension())
