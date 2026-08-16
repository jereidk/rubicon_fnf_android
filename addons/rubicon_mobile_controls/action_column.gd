extends Node
class_name RubiconActionColumn

## Keeps the contextual buttons packed and centred as they come and go.
##
## The shop's four buttons read as one column and are authored as one, at
## -410, -200, +10 and +220, each 190 tall with a 20 gap - which is exactly a
## centred column of four. But they live in two different parents: F, Enter
## and Back inside the instanced MenuTouchControls, and Power authored beside
## it in the shop. Each is pinned to its own absolute slot, so hiding one
## leaves a 190 pixel hole and moves nothing. With the cartridge bag
## unavailable the player sees Enter and Back sitting low against empty space,
## and PowerButton - which already hides itself correctly through
## visible_source - leaves the same hole at the bottom.
##
## A VBoxContainer is the obvious answer and cannot be used: it would have to
## own all four, three of them are inside an instanced addon scene, and
## wrapping only those three would shift them relative to Power and break the
## alignment that does work when all four show.
##
## So the slots are recomputed instead of the nodes reparented. Every button
## here is anchored to its parent's centre-right, and both parents share that
## centre - which is why the authored numbers line up across two scenes in the
## first place - so writing offset_top and offset_bottom is enough to place
## them, wherever they happen to live in the tree.
##
## Nothing moves while all four are visible: the layout this computes for four
## buttons is the one they are authored at.

## Extra places to look, for a column split across parents. Normally empty:
## in the shop all four buttons share one parent already - PowerButton is an
## addition to the editable MenuTouchControls instance, not a sibling of it,
## which took finding because the instance is renamed to TouchControls there.
@export var roots: Array[NodePath] = []

## Slot height and the gap between slots, matching what the scene authors.
@export var slot_height: float = 190.0
@export var slot_gap: float = 20.0

## Buttons in column order, taken from where the scene put them.
var _buttons: Array[Control] = []

func _ready() -> void:
	_collect()
	for button in _buttons:
		# visibility_changed fires for the node's own flag, which is what
		# visible_source writes, and that is the only thing that reorders this.
		button.visibility_changed.connect(_reflow)
	_reflow()

## Ordered by the offset the scene authored, so the column keeps the order a
## designer laid out rather than tree order, which is arbitrary across two
## parents.
func _collect() -> void:
	_buttons.clear()
	var found: Array[Control] = []
	var search: Array[Node] = [get_parent()]
	for path in roots:
		var node: Node = get_node_or_null(path)
		if node != null:
			search.append(node)

	for root in search:
		if root == null:
			continue
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.append(child)
			var button := node as Control
			if button != null and button is RubiconActionButton and not found.has(button):
				found.append(button)

	found.sort_custom(func(a: Control, b: Control) -> bool:
		return a.offset_top < b.offset_top)
	_buttons = found

## Packs whatever is visible into a centred run of slots.
func _reflow() -> void:
	var shown: Array[Control] = []
	for button in _buttons:
		if is_instance_valid(button) and button.visible:
			shown.append(button)
	if shown.is_empty():
		return

	var total: float = shown.size() * slot_height + maxf(0.0, shown.size() - 1) * slot_gap
	var top: float = -total * 0.5
	for button in shown:
		button.offset_top = top
		button.offset_bottom = top + slot_height
		top += slot_height + slot_gap
