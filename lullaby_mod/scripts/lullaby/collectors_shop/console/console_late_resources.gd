class_name ConsoleLateResources
extends Node

## The textures, fonts, sprite sheets and materials that only exist below the
## console's TabContainer, held as paths instead of as scene dependencies.
##
## Why: the Collector's Shop cold load is bound by per-file cost - about 53ms a
## file on the device, which is how a room of 363 files becomes the two-minute
## entry users report - and console.tscn drags 118 of those files. Thirty of its
## ext_resources are reached only from inside a tab, and a tab cannot be seen
## until the player navigates to one: the TabContainer is authored at
## modulate.a = 0 and the only thing that raises it is change_tab(). So none of
## them has to be on the critical path of a room the player is waiting for.
## Measured against the room's real dependency graph, moving them here takes 32
## files off it - 8.8% of the load, roughly 1.7s at the device's per-file cost.
##
## What this is NOT is a way to defer the console itself. The room overrides
## twenty nodes inside it from outside, fourteen of them below TabContainer -
## see tools/test_console_wiring.gd - and Godot resolves those against the
## instanced scene at load, so the nodes have to stay exactly where they are.
## Only the resources hanging off them move, which is why this is a table of
## properties rather than a lazily-instanced subtree.
##
## Two things guarantee nothing is ever seen undressed:
##
##   * flush_tab() is called by console_tab_container before a tab is shown, so
##     the tab that is about to become visible is complete first
##   * everything left over is applied one entry per frame in the background,
##     the same shape the Collector's voiceline warming already uses
##
## The per-frame drip is what makes this safe rather than clever: any path that
## reaches a tab without going through change_tab() still finds it dressed
## within 43 frames of the room appearing.

## `NodePath:property` relative to tab_root -> the resource path to load.
##
## Each key is read as a NodePath with a subname, which is the shape Godot
## already has for "this property of that node", so the two halves cannot drift
## into different orders. The subname keeps slashes, which matters:
## `theme_override_fonts/font` and `surface_material_override/0` are single
## property names that happen to contain one.
##
## Typed as String and converted here rather than declared Dictionary[NodePath,
## String], which was the first shape and is a trap. A .tscn writes NodePath
## keys as `&"..."`, that is a StringName, and the conversion fails - measured:
## Godot reports one "Unable to convert key" line and hands back an EMPTY
## dictionary, so a single mistyped key silently disables every entry. A String
## key cannot be got wrong that way.
@export var deferred: Dictionary[String, String] = {}

## AnimatedSprite2D nodes whose `animation` has to be restored after their
## sprite_frames lands, and which of them were authored to autoplay it.
##
## This exists because of one measured behaviour: assigning `animation` while
## `sprite_frames` is null does not fail quietly. Godot pushes a red
## "There is no animation with name 'x'" error, clears the property, and
## remembers the name internally - it does come back when the frames arrive,
## but the error is already in the log, twice per node, on every shop load.
## Someone would eventually chase it. So the scene no longer authors
## `animation`/`autoplay` on these six nodes and this restores them instead,
## which is also the only way autoplay ever starts: NOTIFICATION_READY plays it
## against a null sheet, gets nothing, and never tries again.
@export var sprite_animations: Dictionary[String, StringName] = {}

## The subset of sprite_animations that was authored to play on its own.
@export var sprite_autoplay: Array[String] = []

## The node the keys are relative to - the TabContainer.
@export var tab_root: Node

## Keys not applied yet, in table order.
var _pending: Array[String] = []

## Path -> loaded resource, remembering failures too. A path that does not
## resolve must not be retried once per site: mat_console_select alone has five.
var _cache: Dictionary[String, Resource] = {}


func _ready() -> void:
	_pending = deferred.keys()
	set_process(not _pending.is_empty())


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	_apply(_pending.pop_front())


## Everything still pending for one tab, now.
##
## Takes the tab's node name rather than its index or its header text: the
## container's own tabs_array says "Codes" where the child is named "Hacks", so
## indexing that list would silently flush nothing for one tab.
func flush_tab(tab: StringName) -> void:
	var names := String(tab)
	var keep: Array[String] = []
	for key: String in _pending:
		if key.begins_with(names + "/") or key.begins_with(names + ":"):
			_apply(key)
		else:
			keep.append(key)
	_pending = keep
	set_process(not _pending.is_empty())


## The whole table, now. For anything that wants the console complete - a
## screenshot, a test - rather than for normal play.
func flush_all() -> void:
	while not _pending.is_empty():
		_apply(_pending.pop_front())
	set_process(false)


func _apply(key: String) -> void:
	var path: String = deferred.get(key, "")
	if path.is_empty():
		return

	var where := NodePath(key)
	var node: Node = null
	if tab_root != null:
		node = tab_root.get_node_or_null(NodePath(where.get_concatenated_names()))
	if node == null:
		push_warning("console: nothing at %s for %s" % [key, path])
		return

	var resource: Resource = null
	if _cache.has(path):
		resource = _cache[path]
	else:
		resource = ResourceLoader.load(path)
		_cache[path] = resource
	if resource == null:
		push_warning("console: %s does not load" % path)
		return

	node.set(where.get_concatenated_subnames(), resource)
	_restore_animation(where, node)


## Puts back what the scene stopped authoring. See sprite_animations.
func _restore_animation(key: NodePath, node: Node) -> void:
	if key.get_concatenated_subnames() != &"sprite_frames":
		return
	var owner_path := String(key.get_concatenated_names())
	if not sprite_animations.has(owner_path):
		return
	if not (node is AnimatedSprite2D or node is AnimatedSprite3D):
		return

	var animation: StringName = sprite_animations[owner_path]
	if animation.is_empty():
		return

	node.animation = animation
	if sprite_autoplay.has(owner_path):
		node.play(animation)
