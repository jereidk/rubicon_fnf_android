extends Node

## Builds the mechanic the Training tab asked for into the test level.
##
## Sits in songs/test/test.tscn and does nothing at all on an ordinary run -
## LullabyTraining.take_request() returns NONE unless a Training button set
## it, so the test level still opens as the plain placeholder the main menu
## uses.
##
## Each mechanic goes in the way its own song already instances it, which is
## the whole reason the Test song works as a host: none of the three needed
## to be rewritten, only placed and started.

## Where a mechanic's visuals go. The test level's own HUD Control, so the
## mechanic sits with the judgment popup and health bar rather than over the
## notes.
@export var ui_parent: Control

## Fed to mch_typing, which unlike the other two is not self-contained: it
## exports reference_level and health_module and Monochrome wires both from
## the song. bar_animation is Monochrome's own HUD bar and stays null here -
## typing_challenge.gd is the thing that has to tolerate that.
@export var level: Node
@export var health_module: Node

## Words to practise with. Monochrome's own list is story text; these are
## neutral and short enough to land inside one pass.
const TRAINING_WORDS: Array[String] = [
	"pulse", "steady", "listen", "breathe", "focus", "again",
	"slower", "hold", "ready", "calm",
]

func _ready() -> void:
	var mechanic: LullabyTraining.Mechanic = LullabyTraining.take_request()
	if mechanic == LullabyTraining.Mechanic.NONE:
		return

	var path: String = String(LullabyTraining.SCENES.get(mechanic, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Training: no scene for mechanic %d" % mechanic)
		return

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Training: could not load %s" % path)
		return

	match mechanic:
		LullabyTraining.Mechanic.PENDULUM:
			_build_pendulum(packed)
		LullabyTraining.Mechanic.PULSE:
			_build_pulse(packed)
		LullabyTraining.Mechanic.TYPING:
			_build_typing(packed)

## lullaby_pendulum.gd finds its server by walking UP the parent chain, so
## the server has to be an ancestor of the visual rather than a sibling. The
## server goes into the HUD and the pendulum goes under the server, which is
## a level deeper than Safety Lullaby nests it but is what the lookup wants.
##
## Safety Lullaby drives `started` from a song animation track. There is no
## such track here, so training just switches it on and leaves it on.
func _build_pendulum(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var server: LullabyPendulumServer = LullabyPendulumServer.new()
	server.name = "TrainingPendulumServer"
	host.add_child(server)

	var pendulum: Node = packed.instantiate()
	server.add_child(pendulum)

	server.started = true

## heartbeat_controller.gd already exposes initialize()/stop() as tool
## buttons for playtesting in the editor, which is exactly a training
## session. mch_heartbeat.tscn carries the controller inside it (Chimera
## reaches it at Heart/HeartbeatController), so this only has to find it.
func _build_pulse(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var heart: Node = packed.instantiate()
	var heart_item := heart as CanvasItem
	if heart_item != null:
		# Chimera ships this instance hidden and reveals it from a sequence;
		# there is no sequence here to do it.
		heart_item.visible = true
	host.add_child(heart)

	var controller: Node = _first_with_method(heart, &"initialize")
	if controller == null:
		push_error("Training: mch_heartbeat has no node with initialize()")
		return
	controller.call(&"initialize")

## The one that is not drop-in. Monochrome wires reference_level,
## bar_animation and health_module from the song; two of those exist here and
## the third does not, so it is left unset rather than pointed at something
## that is not a bar.
func _build_typing(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var typing: Node = packed.instantiate()
	host.add_child(typing)

	if level != null and "reference_level" in typing:
		typing.set(&"reference_level", level)
	if health_module != null and "health_module" in typing:
		typing.set(&"health_module", health_module)

	if "word_list" in typing:
		typing.set(&"word_list", TRAINING_WORDS)
	if "choose_from_list" in typing:
		typing.set(&"choose_from_list", true)

	# active then prompt_user, the order the song's own scene animation uses
	# (scene t16 leads t19 by a couple of seconds); doing it the other way
	# round asks for input before the challenge exists.
	if "active" in typing:
		typing.set(&"active", true)
	if "prompt_user" in typing:
		typing.set(&"prompt_user", true)

func _hud() -> Control:
	if ui_parent != null and is_instance_valid(ui_parent):
		return ui_parent
	push_error("Training: ui_parent is not set on the host")
	return null

func _first_with_method(root: Node, method: StringName) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_method(method):
			return node
		for child in node.get_children():
			stack.append(child)
	return null
