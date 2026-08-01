extends TriggerArea3D

const ConfirmExitDialogScene: PackedScene = preload("res://lullaby_mod/scripts/lullaby/collectors_shop/confirm_exit_dialog.tscn")

@export var shop: CollectorShop
@export var camera_positions: AnimationPlayer
@export var cine_bars: AnimationPlayer
@export var dialogue: CollectorDialogue

@export var override_quit: bool = true:
	set(value):
		override_quit = value
		get_tree().auto_accept_quit = !override_quit
		return value

func _ready() -> void :
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void :
	if !override_quit: return

	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _closing_game:
			get_tree().quit()
		else:
			_closing_game = true
			trigger()

func _exit_tree() -> void :
	get_tree().auto_accept_quit = true

var _closing_game = false
var _leaving: bool = false

func trigger() -> void :
	if not can_interact:
		return

	# The OS-level close-request path (_notification above) already has its
	# own "press twice" safety net (a second WM_CLOSE_REQUEST here quits
	# immediately) - only the player walking up and interacting with the
	# exit in-scene needs the confirmation prompt, so a stray tap doesn't
	# immediately kick off leaving with no way back.
	if _closing_game:
		_do_exit()
		return

	shop.state = shop.ShopStates.BUSY
	shop.stop_voiceline()

	var dialog: ConfirmExitDialog = ConfirmExitDialogScene.instantiate()
	add_child(dialog)
	dialog.confirmed.connect(_do_exit)
	dialog.cancelled.connect(func(): shop.state = shop.ShopStates.FREE_LOOK)

func _do_exit() -> void :
	if not _closing_game:
		camera_positions.play(&"byebye")

		cine_bars.stop()
		cine_bars.play(&"IN")

		dialogue.play_move_up()

	shop.play_voiceline_group("byebye")

	_leaving = true


func _on_collector_shop_voice_entry_finished() -> void :
	if _leaving:
		if _closing_game:
			get_tree().quit()
		else:
			GameIntro.skip_intro = true
			SceneChanger.change_to("uid://bj63tbt25fbyg", &"hypno")
