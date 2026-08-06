extends Node

## Keeps the console's Midscroll row honest while the VSlice note layout is
## selected, where midscroll is not optional.
##
## VSlice's layout is built around the player strumline sitting in the centre,
## which is exactly what midscroll does - lullaby_note_layout_applier.gd
## deliberately hands horizontal placement to midscroll's AnimationTree rather
## than fighting it every frame (see the long comment there). With midscroll
## off, VSlice's widened lane spacing and larger notes land on an off-centre
## strumline and the result reads as broken rather than as a layout.
##
## Settings.is_midscroll_active() therefore reports true under VSlice whatever
## game_centered holds. This node makes the row show that: ticked, dimmed, and
## put straight back if it is unticked. game_centered itself is never written,
## so going back to Classic restores the player's own preference instead of a
## value this had overwritten.
##
## Same watch-Settings.applied pattern as mobile_section_visibility.gd - every
## settings row emits it after apply_settings().

## The Midscroll toggle_button this locks. Its checkbox is its first child
## (toggle_button.gd reads it the same way).
@export var toggle: Button

const LOCKED_ALPHA: float = 0.5

func _ready() -> void:
	Settings.applied.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if toggle == null:
		return

	var locked: bool = Settings.lullaby_note_layout == 1
	var shown: bool = true if locked else Settings.game_centered

	toggle.modulate.a = LOCKED_ALPHA if locked else 1.0

	if toggle.get("is_activated") != shown:
		toggle.set("is_activated", shown)

	# toggle_button.gd's own `checkbox` is an @onready, and a parent's _ready
	# runs after its children's - so on the first pass it is still null and
	# the node has to be reached directly.
	if toggle.get_child_count() > 0:
		var checkbox: Node = toggle.get_child(0)
		if checkbox != null and "check" in checkbox:
			checkbox.check.visible = shown
