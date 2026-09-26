@tool
extends EditorPlugin

## Empty editor plugin. GDAnimate registers its node via `class_name
## AnimateSymbol` in animate_symbol.gd, which Godot picks up automatically
## when the project is scanned. There is no runtime or editor hook to run
## here.
##
## The plugin.cfg still exists so the addon appears in
## Project Settings > Plugins, and so the editor shows it as installed.
## Without a plugin.cfg, Godot treats the addon as a bare directory and
## does not list it in the plugins tab.


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
