@abstract extends RefCounted
class_name SpriteImporter

## Name of the format. Will be used as the name of the tab.
func get_format_name() -> StringName:
	return ""

## Get importer data class and should always be of base ImporterSpriteData. For example, Sparrow atlases would use SparrowImporterSpriteData.
func get_importer_data_class() -> String:
	return "" # <- Has to be a child child of ImporterSpriteData

## Returns a bool depending if the atlas path is automatically determined or a custom path can be used.
func needs_atlas_path() -> bool:
	return true

## Returns the valid extensions for textures.
func get_texture_extensions() -> PackedStringArray:
	return [".png", ".webp", ".tga", ".bmp", ".jpg", ".jpeg", ".svg"]

## Returns the extension for the atlas, usually .xml or .json.
func get_atlas_extension() -> String:
	return ""

## Whether or not every sprite in a given directory should be searched for sprites.
func should_check_dir() -> bool:
	return true
