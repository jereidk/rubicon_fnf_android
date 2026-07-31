extends ListButton

@export var resolution_button: ListButton
@export var next_node: Button

func _input(event: InputEvent) -> void :
	var index_before: int = index
	super._input(event)

	# Rubicon addition: this used to only re-sync the Resolution row's
	# enabled look/focus chain when triggered by an actual ui_left/ui_right
	# key, so a tap (which now also changes `index` via super._input)
	# never updated it. Comparing before/after covers every input source.
	if index != index_before:
		if index == 0:
			resolution_button.add_theme_color_override(&"font_color", Color.WHITE)
			focus_neighbor_bottom = resolution_button.get_path()
			next_node.focus_neighbor_top = resolution_button.get_path()
		else:
			resolution_button.add_theme_color_override(&"font_color", Color.DIM_GRAY)
			focus_neighbor_bottom = next_node.get_path()
			next_node.focus_neighbor_top = self.get_path()
