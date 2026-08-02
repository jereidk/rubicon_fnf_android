@tool
extends EditorPlugin

const SpriteImporter := preload("res://addons/astc_sprite_import/sprite_importer.gd")

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = SpriteImporter.new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
