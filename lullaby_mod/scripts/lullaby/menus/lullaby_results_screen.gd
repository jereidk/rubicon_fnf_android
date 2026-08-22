extends Control

const FLAGS_FOR_CREDITS: Array[StringName] = [&"safety_lullaby_beaten", &"monochrome_beaten", &"chimera_beaten"]

@export var disable_when_active: Array[Node]
@export var song_grader: LullabySongGrader

@export var target_timeline: AnimationPlayer

@export var results_label: Label
@export var animation_player: AnimationPlayer

@export var soultoken_count: Label

@export var song_name: String = "safety_lullaby"

var active: bool = false

## The 3D render behind the results art: its own world, its own
## WorldEnvironment, a Camera3D and a DirectionalLight3D with shadows on.
##
## This screen is instanced in all three songs and shipped hidden, and the
## viewport had no update mode of its own, so it sat in every song scene as
## the largest live SubViewport in the tree - a shadow-casting 3D render for
## a screen nobody sees until the song ends. Authored DISABLED now and turned
## on here, which works because it hangs off this Control directly: a
## SubViewportContainer would overwrite the mode from its own visibility on
## every notification and an authored value would be inert.
@export var render_viewport: SubViewport


## Switches the 3D render on or off.
##
## The first version of this drove the mode off is_visible_in_tree(), and
## the device log says it never turned anything off: the viewport reads live
## in 87 of 106 Monochrome lines, and from the first census after load in all
## three songs, at 0.6-0.89ms of GPU each frame. `visible` is simply not the
## question being asked here -
##
##   - Chimera and Safety Lullaby never author `visible` on this instance at
##     all, so it is true for the whole song. The screen draws nothing the
##     player can see (its own animations bring ScalingFella, the label and
##     FadingColor up from zero), but the flag says visible and the gate
##     dutifully switched the render on and left it there.
##   - Monochrome is the only one that authors `visible = false`, and it is
##     also the only one whose song animation drives
##     `ResultsScreen/LullabyResultsScreen:visible` as a track - which is why
##     that one flips mid-song and the other two never do.
##
## So the mode follows what actually presents the screen instead: nothing
## renders until _on_song_finished() starts the `show` animation, which is
## the only place in the project that plays it. Visibility is still honoured
## in the one safe direction - going invisible switches the render off - but
## it can no longer switch anything on.
func _set_viewport_live(live: bool) -> void:
	if render_viewport == null:
		return
	render_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_set_viewport_live(false)


func _ready() -> void :
	if render_viewport == null:
		render_viewport = get_node_or_null(^"SubViewport") as SubViewport
	# Unconditionally off. The viewport holds a spinning soultoken that
	# SoultokenSprite only reveals during `show_tokens`, so there is nothing
	# to render until the song is over - and the DirectionalLight3D inside it
	# is the only shadow caster Monochrome has, which is what the census's
	# shadows=[...] finally named.
	_set_viewport_live(false)

	# And the 2D half of the same problem, which the viewport gate did not
	# cover. over= names ResultsScreen/LullabyResultsScreen/FadingColor as the
	# largest full-screen painter in Chimera in all eight censuses of the last
	# device log, for the whole song. It is a 2880x1620 ColorRect that the
	# player cannot see, because `show` brings it up from zero - but modulate
	# does not stop a CanvasItem from being drawn. Only `visible` does, and
	# Chimera and Safety Lullaby never author it on this instance, so it has
	# been true from the downbeat.
	#
	# Monochrome is the exception and it is safe: it authors visible = false
	# and its song animation drives this node's `visible` as a track, so the
	# authored sequence still owns it there.
	hide()

	if target_timeline:
		target_timeline.animation_finished.connect(_on_song_finished)

	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	if soultoken_count:
		soultoken_count.text = str(SaveData.tokens)


func _unhandled_input(event: InputEvent) -> void :
	if not active or event.is_echo() or not event.is_pressed():
		return

	get_viewport().set_input_as_handled()

	if event.is_action(&"ui_accept"):
		active = false

		if SaveData.just_got_token:
			animation_player.play(&"show_tokens")
		else:
			animation_player.play(&"close")


func _on_animation_finished(anim_name: StringName) -> void :
	match anim_name:
		&"show":
			LullabyGameoverModule.has_died = false
			active = true
		&"show_tokens", &"close":

			var passed_songs: int = 0
			for flag in FLAGS_FOR_CREDITS:
				if SaveData.get_flag(flag):
					passed_songs += 1

			if passed_songs >= 3 and not SaveData.get_flag(&"credits_scroll_seen"):
				SceneChanger.change_to("uid://c56x7ch1lypk3", &"hypno", false)
			else:
				SceneChanger.change_to("uid://bqkjiwokrcvo", &"hypno", true)


func _on_song_finished(_anim_name: StringName) -> void :
	for node in disable_when_active:
		node.process_mode = Node.PROCESS_MODE_DISABLED

		if "active" in node:
			node.active = false

	if not song_grader:
		return

	var grade: LullabySongGrade = song_grader.get_grade()
	var new_grade: bool = true

	if SaveData.song_grades.has(song_name):
		var prev_grade: LullabySongGrade = SaveData.song_grades[song_name]
		if grade.compare_to(prev_grade) != 1:
			new_grade = false

	if new_grade:
		SaveData.song_grades[song_name] = grade

	var beaten_name: = &"%s_beaten" % song_name
	if ( not SaveData.get_flag(beaten_name)) and ( not Settings.lullaby_baby_mode):
		SaveData.tokens += 1
		SaveData.set_flag(beaten_name, true)
		SaveData.just_got_token = true

	SaveData.save()

	if results_label:
		results_label.text = tr("Score: %d\nHighest Combo: %d\nMisses: %d\nAccuracy: %.2f%%\nRank: %s\nClear: %s") % [
			grade.score,
			grade.highest_combo,
			grade.misses,
			grade.accuracy,
			LullabySongGrader.get_rank_as_string(grade.rank),
			LullabySongGrader.get_clear_as_string(grade.clear)
		]

		if new_grade:
			results_label.text += tr("\n\nNEW GRADE!!!")

	if animation_player:
		# On here rather than at the first frame it is needed. `show` runs for
		# seconds before `show_tokens` reveals SoultokenSprite, so the token
		# has the whole opening to render at least once and the texture is
		# never blank on the frame it appears.
		# Both halves come back together, and before `show` rather than with
		# it: the animation raises modulate from zero, so the node has to be
		# visible for that to present anything.
		show()
		_set_viewport_live(true)
		animation_player.play(&"show")


func add_soultoken() -> void :
	if soultoken_count:
		soultoken_count.text = str(SaveData.tokens)
