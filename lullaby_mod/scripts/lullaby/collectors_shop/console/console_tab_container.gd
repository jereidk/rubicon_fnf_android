extends TabContainer

@export var bind_label: Label
@export var console_root: Console
@export var header_label: Label
@export var animplayer: AnimationPlayer

## The tabs' textures, fonts and sprite sheets, which are no longer scene
## dependencies. See console_late_resources.gd: they come off the room's cold
## load, and the price is that a tab has to be dressed before it is shown.
@export var late_resources: ConsoleLateResources
var _last_tab_idx: int
var tabs_array = [
	"Home",
	"Credits",
	"Settings",
	"Cartridges",
	"Training",
	"Codes"
]


func _on_tab_changed(tab: int) -> void :
	_dress(tab)
	var new_tab: ConsoleTab = get_child(tab)
	var last_tab: ConsoleTab = get_child(_last_tab_idx)
	last_tab.save_last_focus()
	console_root.in_home = tab == 0

	header_label.text = tabs_array[tab]

	if tab == 0:
		new_tab.enable_icons.emit()
	else:
		animplayer.play("header_in")

	if new_tab.default_focus:
		new_tab.default_focus.grab_focus()

	if new_tab._last_focus:
		new_tab._last_focus.grab_focus()
		return



## Loads whatever `tab` still needs, before it can be looked at.
##
## By the tab's own node name, not by tabs_array or the index: that list is the
## header text, and it says "Codes" where the child is named "Hacks", so keying
## the table off it would leave exactly one tab undressed.
func _dress(tab: int) -> void :
	if late_resources == null:
		return
	var child: Node = get_child(tab)
	if child != null:
		late_resources.flush_tab(child.name)


func change_tab(tab: int) -> void :
	# Before modulate goes up, not after: this is the only thing in the console
	# that makes the TabContainer visible at all - it is authored at alpha 0 -
	# so this line is the moment the deferred resources stop being optional.
	_dress(tab)

	modulate.a = 1
	if current_tab == tab:
		return

	if current_tab != 0:
		animplayer.play("header_out")

	_last_tab_idx = current_tab
	var tween = create_tween()
	await tween.tween_property(self, "modulate:a", 0.0, 0.2).finished
	tween.kill()
	tween = create_tween()
	self.current_tab = tab
	await tween.tween_property(self, "modulate:a", 1.0, 0.2).finished
	tween.kill()
