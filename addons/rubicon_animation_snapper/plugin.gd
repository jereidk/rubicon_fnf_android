@tool
extends EditorPlugin

var anim_tab_ref:Control
var anim_editor_step:EditorSpinSlider

func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	if !Engine.is_editor_hint():
		return
	
	var control:Control = Control.new()
	anim_tab_ref = child_from_class(add_control_to_bottom_panel(control, "").get_parent().get_parent().get_parent().get_parent(), "AnimationPlayerEditor")
	remove_control_from_bottom_panel(control)
	
	var anim_track_editor = child_from_class(anim_tab_ref, "AnimationTrackEditor")
	anim_editor_step = child_from_class(child_from_class(anim_track_editor, "HFlowContainer"), "EditorSpinSlider")
	
	anim_editor_step.set_value(0.2)

# unefficient but this engine doesnt give me ANY help when fucking with AnimationPlayerEditor
# this is all i got
# please godot i need this
# ( its also only an editor plugin so it wont slow down any game :) )
func child_from_class(target:Node, _class:String, index:int = 0) -> Node:
	if !ClassDB.class_exists(_class):
		printerr("Class " + _class + " does not exist in ClassDB")
		return null
	
	var node:Node
	var _index:int = 0
	for child in target.get_children():
		if _index < index:
			_index += 1
			continue
		
		if child.get_class() == _class:
			node = child
			break
	return node

# gets all the children in target and looks if each one has a child of _class
# if it does, it returns it
func child_in_child(target:Node, _class:String) -> Node:
	if !ClassDB.class_exists(_class):
		printerr("Class " + _class + " does not exist in ClassDB")
		return null
	
	var node:Node
	for chud in target.get_children():
		var child = child_from_class(chud, _class)
		if child == null:
			continue
		node = child
		break
	return node

func _exit_tree() -> void:
	pass
