extends Button

@export var console: Control
@export var box: Sprite2D

## Which mechanic this button practises - LullabyTraining.Mechanic. Left at
## NONE the button still only clicks, which is what all three did before.
@export_enum("None", "Pendulum", "Pulse", "Typing") var mechanic: int = 0

var tween

func _ready() -> void :
	self.pressed.connect(_on_button_pressed)
	self.focus_entered.connect(_on_focus_entered)
	self.focus_exited.connect(_on_focus_exited)


func _on_button_pressed():
	console.play_sound.emit("sfx_soulroom_select_alt")

	if mechanic == LullabyTraining.Mechanic.NONE:
		return

	# The request has to outlive the scene change, so it goes in a static and
	# LullabyTrainingHost picks it up on the other side.
	LullabyTraining.requested = mechanic as LullabyTraining.Mechanic
	SceneChanger.change_to(LullabyTraining.TEST_SONG, &"hypno")

func _on_focus_entered():
	console.play_sound.emit("sfx_soulroom_click")
	if tween:
		tween.kill()
	tween = create_tween()
	await tween.tween_property(box, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC).finished
	tween.kill()

func _on_focus_exited():
	if tween:
		tween.kill()
	tween = create_tween()
	await tween.tween_property(box, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).finished
	tween.kill()
