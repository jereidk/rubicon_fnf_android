# Renders story mode at the moments it actually passes through: every week,
# every difficulty, the title tween mid-flight, the week confirm, and the
# amtake/animania picker.
#
# The picker hangs off the MAIN MENU, not off the story menu - MainMenuScreen's
# doSelect is what allocates it - so the last shots swap the scene under test.
# Everything before them drives ONE instance of the story menu through the states
# in order, because that is how a player reaches them: rebuilding per shot would
# hide anything that only goes wrong on the SECOND change_level.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --fixed-fps 60 --path . \
#       res://tools/animania/harness/story_stages_shot.tscn
#
# --fixed-fps IS REQUIRED for the transition shots. Rendering here is llvmpipe,
# where a frame of this menu takes the better part of a second, and a Tween runs
# on the real clock: "four frames after change_level" was three seconds in, so
# the 0.3s title tween had been over for ages and the shot was indistinguishable
# from the settled one. With a fixed delta four frames is 0.066s and the titles
# are caught mid-travel.
extends Node2D

const STORY := "res://animania_mod/menus/story/story_menu.tscn"
const MAIN := "res://animania_mod/menus/main/main_menu.tscn"
## Long enough for reposition_titles' tween and the background lerp to settle.
const SETTLED := 45

var _menu: Node
var _at: int = 0
var _frames: int = 0
var _pending: String = ""
var _plan: Array = []


func _ready() -> void:
	_open_story()
	# selected_level starts on week1 (index 1): tutorial, week1, week5, sorted by
	# the level file's name.
	_plan = [
		["01_semana_tutorial", func() -> void: _week(0), SETTLED],
		["02_semana_week1", func() -> void: _week(1), SETTLED],
		["03_semana_week5", func() -> void: _week(2), SETTLED],
		# Mid-tween: reposition_titles moves every title at once, and this is the
		# only shot that shows whether they travel together.
		["04_transicion_4f", func() -> void: _week(1), 4],
		["05_transicion_12f", func() -> void: _week(2), 12],
		["06_dif_easy", func() -> void: _diff(1, "easy"), SETTLED],
		["07_dif_normal", func() -> void: _diff(1, "normal"), SETTLED],
		["08_dif_hard", func() -> void: _diff(1, "hard"), SETTLED],
		# select_level plays the confirm on the cast and then waits a second
		# before leaving, so this has to be shot inside that second and the menu
		# torn down before it is up - otherwise the loading screen takes over the
		# harness mid-run.
		["09_confirm_6f", func() -> void: _menu.call(&"select_level"), 6],
		# The picker, on the main menu where it belongs. Two shots, one per side,
		# and 80 frames because the buttons slide in over a full second.
		["10_selector_amtake", func() -> void: _open_picker(), 80],
		["11_selector_animania", func() -> void: _pick(1), 20],
	]
	_begin()


func _open_story() -> void:
	_drop()
	_menu = load(STORY).instantiate()
	add_child(_menu)


func _open_picker() -> void:
	_drop()
	_menu = load(MAIN).instantiate()
	add_child(_menu)
	_menu.call(&"_open_story_select")


func _drop() -> void:
	if _menu == null:
		return
	remove_child(_menu)
	_menu.free()
	_menu = null


func _week(index: int) -> void:
	var at: int = int(_menu.get(&"selected_level"))
	if at == index:
		return
	_menu.call(&"change_level", index - at, false)


func _diff(week: int, id: String) -> void:
	_week(week)
	# change_difficulty walks the list, so step toward the one wanted rather than
	# assigning it: assigning would skip build_difficulty_sprite.
	for _i: int in 8:
		if String(_menu.get(&"current_difficulty_id")) == id:
			return
		_menu.call(&"change_difficulty", 1)


## Moves the picker's selection, so the second of the two buttons gets a shot.
func _pick(index: int) -> void:
	var sub: Node = _menu.get(&"_story_select") as Node
	if sub != null:
		sub.call(&"_select_button", index)


func _begin() -> void:
	_frames = 0
	(_plan[_at][1] as Callable).call()


func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_at += 1
		if _at >= _plan.size():
			_drop()
			get_tree().quit()
			return
		_begin()
		return

	_frames += 1
	if _frames < int(_plan[_at][2]):
		return
	_pending = "user://story_%s.png" % String(_plan[_at][0])
