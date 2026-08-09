extends SettingsButton

signal toggle_checkbox

@export var is_activated: bool
@export var property: StringName
@export var unlock_flag: StringName
@onready var checkbox = get_child(0)

func _ready() -> void :
	super._ready()
	if not unlock_flag.is_empty():
		visible = SaveData.get_flag(unlock_flag)
	is_activated = Settings.get(property)
	checkbox.position.x = size.x + 60
	checkbox.check.visible = is_activated

func _on_button_pressed():
	console.play_sound.emit("sfx_soulroom_select_alt")
	is_activated = not is_activated
	toggle_checkbox.emit()
	# Only Baby Mode's own row. This is the base class for EVERY toggle in
	# the console, so the unguarded version played the Collector's "baby
	# mode on" line whenever any checkbox anywhere was switched on -
	# Downscroll, Ghost Tapping, Shadows, Ambient Occlusion, all of them.
	if is_activated and property == &"lullaby_baby_mode":
		console.shop.play_voiceline_group("babyon", true)

	Settings.set(property, is_activated)
	Settings.apply_settings()
