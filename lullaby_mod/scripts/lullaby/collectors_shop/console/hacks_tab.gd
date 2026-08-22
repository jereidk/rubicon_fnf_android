class_name HacksTab
extends ConsoleTab

## Console "Hacks" tab - a Nightmarevision-style cheat code entry. Typing a
## known code and pressing Enter unlocks the matching song directly,
## mirroring exactly what prp_briefcase.gd's try_buy_cart() does to mark a
## cartridge owned (SaveData.set_flag("<key>_unlocked", true) + save()) -
## just without going through the actual purchase flow. Codes are
## case-insensitive.

const CODES: Dictionary[String, StringName] = {
	"IAMDEAD": &"monochrome",
	"SERENAHEX": &"chimera",
	"SHOWCASE": &"showcase_mode",
	"SPEEDHACK": &"speed_hack",
}

## Not a real code - unlocks nothing, sets no flag, so it can be entered as
## many times as someone wants to keep hearing it. Checked before CODES so it
## never falls into the "Invalid code." path. GODMODE, not FART: the bit is
## typing the most mythical cheat code in gaming and getting this instead.
const PRANK_CODE := "GODMODE"
const PRANK_LINES: Array[String] = [
	"GODMODE activated. You are now invincible to embarrassment. Wait, no.",
	"Ultimate power granted. It smells like ultimate power, actually.",
	"Root access: denied. Fart access: granted.",
	"You now have unlimited everything, except dignity.",
]

@export var code_input: LineEdit
@export var feedback_label: Label
@export var console: Console

func _ready() -> void:
	code_input.text_submitted.connect(_on_code_submitted)

func _on_code_submitted(text: String) -> void:
	var code: String = text.strip_edges().to_upper()
	code_input.text = ""

	if code == PRANK_CODE:
		feedback_label.text = PRANK_LINES.pick_random()
		if console:
			console.play_sound.emit("sfx_wet_disguisting_fart")
		return

	if not CODES.has(code):
		feedback_label.text = "Invalid code."
		if console:
			console.play_sound.emit("sfx_soulroom_deny")
		return

	var key: StringName = CODES[code]
	var flag: StringName = StringName("%s_unlocked" % key)
	if SaveData.get_flag(flag):
		feedback_label.text = "\"%s\" is already unlocked." % key.capitalize()
		return

	SaveData.set_flag(flag, true)
	SaveData.save()
	feedback_label.text = "Code accepted - \"%s\" unlocked!" % key.capitalize()
	if console:
		console.play_sound.emit("sfx_soulroom_select_alt")
