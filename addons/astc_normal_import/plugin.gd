@tool
extends EditorPlugin

const NormalMapImporter := preload("res://addons/astc_normal_import/normal_map_importer.gd")

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = NormalMapImporter.new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
