extends SceneTree

## Times the two ways of reusing a note, against the number of siblings the
## handler is holding.
##
## Parking a despawned note instead of removing it halved the spike rate on
## device but pushed the steady frame time from 16.7ms to 18-21ms at matched
## points in the song. Both cannot be judged from the same counter, so this
## separates them: taking a note in and out of the tree is a fixed cost per
## note, while everything spawn_note() does AFTER it has a node - naming it
## and sorting it - scales with how many children the handler has, and
## parking is what makes that number large.
##
## Uses the real note scene, so the per-node costs are the real ones.
##
## Run with:
##   godot --headless --path . --script tools/bench_note_reuse.gd

## The real note scene cannot be instantiated outside a fully imported
## project - it pulls in textures - so the subject is rebuilt here to the
## same shape: 21 nodes, 5 AnimationPlayers and 3 AnimationTrees, which is
## what the diagnostics census measures a funkin mania note to be.
##
## The animations matter as much as the node count. An AnimationMixer marks
## its track cache dirty on NOTIFICATION_ENTER_TREE and rebuilds it by
## resolving a NodePath per track, so a player with no tracks would make
## re-entering the tree look free when it is not.
const TRACKS_PER_PLAYER := 8
const REPEATS := 200
const SIBLING_COUNTS := [12, 24, 48, 96]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	var sample: Node = _make_note()
	print("nota sintetica: %d nodos, %d AnimationPlayer, %d AnimationTree, %d tracks cada uno"
		% [_count_nodes(sample), _count_type(sample, "AnimationPlayer"),
			_count_type(sample, "AnimationTree"), TRACKS_PER_PLAYER])
	sample.free()
	print("%d repeticiones por medida\n" % REPEATS)
	print("%9s %14s %14s %14s %14s" % [
		"hermanos", "quitar+poner", "ocultar+most", "move_child", "renombrar"])

	for count: int in SIBLING_COUNTS:
		var host := Control.new()
		root.add_child(host)

		for i in count:
			var node: Node = _make_note()
			node.name = "Filler %d" % i
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
			host.add_child(node)

		var subject: Node = _make_note()
		host.add_child(subject)
		await process_frame

		var tree_cycle: float = _time(func() -> void:
			host.remove_child(subject)
			host.add_child(subject))

		var park_cycle: float = _time(func() -> void:
			subject.visible = false
			subject.process_mode = Node.PROCESS_MODE_DISABLED
			subject.process_mode = Node.PROCESS_MODE_INHERIT
			subject.visible = true)

		var sort: float = _time(func() -> void:
			host.move_child(subject, 0)
			host.move_child(subject, host.get_child_count() - 1))

		var rename: int = 0
		var rename_time: float = _time(func() -> void:
			rename += 1
			subject.name = "Note %d" % rename)

		print("%9d %12.3fus %12.3fus %12.3fus %12.3fus" % [
			count, tree_cycle, park_cycle, sort, rename])

		host.queue_free()
		await process_frame

	print("")
	print("quitar+poner es lo que el aparcado evita.")
	print("ocultar+mostrar es lo que cuesta en su lugar.")
	print("")

	# The operation being cheaper is only half the question. Parked notes
	# stay in the tree, so the other half is what a frame costs with them
	# sitting there - which no per-operation timing can show.
	print("coste POR FRAME de tener notas aparcadas en el arbol")
	print("%9s %14s %14s" % ["aparcadas", "nodos extra", "ms por frame"])
	for count: int in [0, 24, 48, 96]:
		print("%9d %14d %12.3fms" % [count, count * 21, await _frame_cost(count)])

	quit()

## Average wall time per frame with `parked` hidden, process-disabled notes
## parented under the root, with the frame limiter off so the number is work
## and not vsync.
func _frame_cost(parked: int) -> float:
	var host := Control.new()
	root.add_child(host)
	for i in parked:
		var node: Node = _make_note()
		node.name = "Parked %d" % i
		node.visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
		host.add_child(node)

	var previous: int = Engine.max_fps
	Engine.max_fps = 0
	for i in 60:
		await process_frame

	var began: int = Time.get_ticks_usec()
	const FRAMES := 300
	for i in FRAMES:
		await process_frame
	var per_frame: float = float(Time.get_ticks_usec() - began) / FRAMES / 1000.0

	Engine.max_fps = previous
	host.queue_free()
	await process_frame
	return per_frame

## Microseconds per iteration, with a warm-up pass so the first call's
## allocation does not land in the measurement.
func _time(body: Callable) -> float:
	for i in 20:
		body.call()
	var began: int = Time.get_ticks_usec()
	for i in REPEATS:
		body.call()
	return float(Time.get_ticks_usec() - began) / float(REPEATS)

## A stand-in for resources/levels/ui/funkin/mania/Note.tscn, matching its
## node tree exactly: Container/TrailMask with four trails and their tails,
## a Sprite/Graphic, and the three self-driving AnimationTrees.
func _make_note() -> Control:
	var note := Control.new()
	note.name = "Note"

	var container := Control.new()
	container.name = "Container"
	note.add_child(container)

	var mask := Control.new()
	mask.name = "TrailMask"
	container.add_child(mask)

	for direction: String in ["L", "D", "U", "R"]:
		var trail := TextureRect.new()
		trail.name = "Trail" + direction
		mask.add_child(trail)
		var tail := TextureRect.new()
		tail.name = "Tail"
		trail.add_child(tail)

	_add_player(mask, "AnimationPlayer", mask)

	var sprite := Control.new()
	sprite.name = "Sprite"
	container.add_child(sprite)
	var graphic := AnimatedSprite2D.new()
	graphic.name = "Graphic"
	sprite.add_child(graphic)
	_add_player(graphic, "AnimationPlayer", graphic)

	for pair: Array in [["DirectionTree", "DirectionPlayer"],
			["MissedTree", "MissedPlayer"], ["HeldTree", "HeldPlayer"]]:
		var tree := AnimationTree.new()
		tree.name = pair[0]
		note.add_child(tree)
		var player: AnimationPlayer = _add_player(tree, pair[1], tree)
		tree.anim_player = tree.get_path_to(player)

	return note

## Every track points at a node the player can actually resolve, since it is
## that resolution, once per track, that re-entering the tree pays for.
func _add_player(parent: Node, name: String, target: Node) -> AnimationPlayer:
	var player := AnimationPlayer.new()
	player.name = name
	parent.add_child(player)

	var animation := Animation.new()
	animation.length = 1.0
	for i in TRACKS_PER_PLAYER:
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, "%s:modulate" % player.get_path_to(target))
		animation.track_insert_key(track, 0.0, Color.WHITE)
		animation.track_insert_key(track, 1.0, Color.TRANSPARENT)

	var library := AnimationLibrary.new()
	library.add_animation(&"play", animation)
	player.add_animation_library(&"", library)
	return player

func _count_nodes(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total

func _count_type(node: Node, type: String) -> int:
	var total: int = 1 if node.is_class(type) else 0
	for child in node.get_children():
		total += _count_type(child, type)
	return total
