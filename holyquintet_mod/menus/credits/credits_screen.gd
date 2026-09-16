extends Control
## Ports HQCredits.hx (see credit_info_row.gd for the per-row widget it
## uses, porting ui/CreditInfoUI.hx). Real z-order (create(), all plain
## add(), except portrait): bg_Spr (tinted gray), bg_Spots (tinted gray,
## bg_Back is NOT tinted), 25 CreditInfoUI rows, additonalText,
## bg_TopBanner, portrait (inserted at bg_BtmBanner's own slot — ends up
## between the two banners, not after both), bg_BtmBanner.
##
## Real scrolling: each row's own spawn (x,y) = (100+25*i, 465+180*i); on
## every selection change, each row tweens (0.5s, expoOut) to
## originalX[i] - 25*curSel, originalY[i] + 180*curSel — which simplifies
## to (100 + 25*(i-curSel), 465 + 180*(i-curSel)): the selected row always
## settles at the same fixed anchor (100,465), and every other row
## cascades diagonally down-right the further its index is from the
## selection. additonalText (the Special Thanks/copyright block) rides
## the same scroll math using its own fixed anchor (725,4925) instead of
## a per-row original position, since it isn't one of the 25 rows.
##
## portrait: create()'s own initial kixel/scale-1.3/alpha-0 setup is dead
## code in the real class — updatePortrait() (called by the
## changeSelection(0) at the very end of create()) immediately reloads
## the graphic, rescales to 0.65 and repositions from scratch before
## anything is ever drawn, so that initial state is never actually seen.
## Not replicated here for that reason; this port goes straight to the
## equivalent of updatePortrait()'s own result on _ready().
##
## Mobile-only addition, not in the real game: tapping a row (see
## credit_info_row.gd) jumps the selection to it, and this screen
## intercepts NOTIFICATION_WM_GO_BACK_REQUEST (see main_menu.gd's own
## header for why Android's back button/gesture needs this at all — real
## Flixel/HScript has no such concept).

const RowScript := preload("res://holyquintet_mod/ui/credit_info_row.gd")
const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

const CREDITS := [
	{"img_name": "kixel", "name": "Kixel", "role": "Lead Director, Lead Art & Animation Director,\nConcept Artist, Story Writer", "tworow": true},
	{"img_name": "sector", "name": "Sector", "role": "Director, Lead Program Director, Artist, Cleanup Artist,\nAnimator", "tworow": true},
	{"img_name": "spore", "name": "Sp0re", "role": "Co-Director, Lead Music Director,\nLead Story Writer, Chromatic Maker", "tworow": true},
	{"img_name": "chumbot", "name": "chum-bot", "role": "Co-Director, Musician, Story Writer", "tworow": false},
	{"img_name": "pablito", "name": "GamerPablito", "role": "Programmer, Translator (ES)", "tworow": false},
	{"img_name": "revdev", "name": "RevDev", "role": "Lead Witch Aesthetic Artist, BG Artist", "tworow": false},
	{"img_name": "torr", "name": "Torresmmo", "role": "Artist and Animator", "tworow": false},
	{"img_name": "teri", "name": "Teri", "role": "Artist and BG Artist", "tworow": false},
	{"img_name": "moth", "name": "endtimeillusionist", "role": "Artist", "tworow": false},
	{"img_name": "faro", "name": "Far0", "role": "Artist", "tworow": false},
	{"img_name": "retrodetro", "name": "RetroDetro", "role": "BG Artist, Animatic Animator, Animator", "tworow": false},
	{"img_name": "cuffee", "name": "cuffeekawaii", "role": "Artist", "tworow": false},
	{"img_name": "akoy", "name": "akoy!", "role": "Musician", "tworow": false},
	{"img_name": "mag", "name": "Mag", "role": "Musician", "tworow": false},
	{"img_name": "sinn", "name": "Sinn", "role": "Musician", "tworow": false},
	{"img_name": "oreo", "name": "Sleepy_Oreo", "role": "Musician", "tworow": false},
	{"img_name": "jordo", "name": "JordoPrice", "role": "Musician", "tworow": false},
	{"img_name": "clover", "name": "cloverderus", "role": "Musician", "tworow": false},
	{"img_name": "penkaru", "name": "Penkaru", "role": "Musician", "tworow": false},
	{"img_name": "fade", "name": "Fade_R", "role": "Charter", "tworow": false},
	{"img_name": "flootena", "name": "Flootena", "role": "Charter", "tworow": false},
	{"img_name": "maskly", "name": "BlackMaskly", "role": "Charter", "tworow": false},
	{"img_name": "tau", "name": "TAU", "role": "Editor", "tworow": false},
	{"img_name": "blitz", "name": "Blitz", "role": "Voice Actress", "tworow": false},
	{"img_name": "cyancat", "name": "Cyancat", "role": "Translator (JP)", "tworow": false},
]

const SPECIAL_THANKS_TEXT := "SPECIAL THANKS\n\nBlantados, Ame, TaeYai, 2DSleeping, Codename Engine, EggOverlord, TheRoyalTony, ChampionKnightEX, Zarky, Inkujira, AGgames, Matt_Does, siron_FNF, shinogami_hajime, Superskullz115, Syrup, Moro-Maniac, Nex_isDumb, heihua., deepseek, OrLavi\n\n\nCOPYRIGHT\n\nThis is a fan-made project and is NOT officially affiliated with Funkin' Crew, Magica Quartet, Aniplex & SHAFT.\nAll rights reserved.\nA Magical Friday Night: Vs Holy Quintet by Team HQ"

var cur_sel := 0
var can_control := true
var rows: Array = []
var row_tweens: Array = []
var text_tween: Tween
var portrait_tween: Tween

@onready var bg_spots: TextureRect = $BgSpots
@onready var rows_root: Control = $RowsRoot
@onready var additional_text: Label = $AdditionalText
@onready var bg_top_banner: TextureRect = $BgTopBanner
@onready var bg_btm_banner: TextureRect = $BgBtmBanner
@onready var portrait: TextureRect = $Portrait
@onready var fade_rect: ColorRect = $FadeRect


func _ready() -> void:
	for i in CREDITS.size():
		var row: Control = RowScript.new()
		row.setup(CREDITS[i], i)
		row.position = Vector2(100.0 + 25.0 * i, 465.0 + 180.0 * i)
		rows_root.add_child(row)
		row.activated.connect(_on_row_activated)
		rows.append(row)
		row_tweens.append(null)

	additional_text.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	additional_text.add_theme_font_size_override("font_size", 24)
	additional_text.add_theme_constant_override("outline_size", 7)
	additional_text.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 0x88 / 255.0))
	additional_text.text = SPECIAL_THANKS_TEXT
	additional_text.position = Vector2(675.0, 4750.0)

	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)

	HQSaves.unlock_achievement("ThanksForPlaying")

	_change_selection(0)


func _process(delta: float) -> void:
	var spots_tex_w: float = bg_spots.texture.get_width()
	var spots_tex_h: float = bg_spots.texture.get_height()
	bg_spots.position.x -= 15.0 * delta
	bg_spots.position.y -= 25.0 * delta
	if bg_spots.position.x <= -spots_tex_w * 2.0:
		bg_spots.position.x += spots_tex_w
	if bg_spots.position.y <= -spots_tex_h * 2.0:
		bg_spots.position.y += spots_tex_h

	var banner_tex_w: float = bg_top_banner.texture.get_width()
	bg_top_banner.position.x += 5.0 * delta
	if bg_top_banner.position.x >= -30.0 + banner_tex_w:
		bg_top_banner.position.x -= banner_tex_w
	bg_btm_banner.position.x -= 5.0 * delta
	if bg_btm_banner.position.x <= -30.0 - banner_tex_w:
		bg_btm_banner.position.x += banner_tex_w


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)


func _unhandled_input(event: InputEvent) -> void:
	if not can_control:
		return
	if event.is_action_pressed("ui_up"):
		_change_selection(-1)
	elif event.is_action_pressed("ui_down"):
		_change_selection(1)
	elif event.is_action_pressed("ui_cancel"):
		_go_back()


func _on_row_activated(row_index: int) -> void:
	if not can_control:
		return
	_change_selection(row_index - cur_sel)


func _change_selection(change: int) -> void:
	if change != 0:
		GenUtil.play_ui_sound(self, "move")
	cur_sel = wrapi(cur_sel + change, 0, rows.size())

	_update_portrait()

	for i in rows.size():
		rows[i].selected = i == cur_sel
		var target := Vector2(100.0 + 25.0 * (i - cur_sel), 465.0 + 180.0 * (i - cur_sel))
		if row_tweens[i]:
			row_tweens[i].kill()
		var tw := create_tween()
		tw.tween_property(rows[i], "position", target, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		row_tweens[i] = tw

	if text_tween:
		text_tween.kill()
	text_tween = create_tween()
	text_tween.tween_property(
		additional_text, "position",
		Vector2(725.0 - 25.0 * cur_sel, 4925.0 - 180.0 * cur_sel),
		0.5
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _update_portrait() -> void:
	if portrait_tween:
		portrait_tween.kill()
	portrait.modulate.a = 0.0

	var tex: Texture2D = load("res://holyquintet_mod/source/images/ui/credits/portraits/%s.png" % CREDITS[cur_sel]["img_name"])
	portrait.texture = tex
	portrait.size = Vector2(tex.get_width(), tex.get_height())
	portrait.scale = Vector2(0.65, 0.65)

	var scaled_w: float = tex.get_width() * 0.65
	var scaled_h: float = tex.get_height() * 0.65
	var target_x: float = (1920.0 - scaled_w / 2.0) * 0.7
	var target_y: float = bg_btm_banner.position.y - scaled_h
	portrait.position = Vector2(target_x + 50.0, target_y)

	portrait_tween = create_tween()
	portrait_tween.set_parallel(true)
	portrait_tween.tween_property(portrait, "position:x", target_x, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	portrait_tween.tween_property(portrait, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _go_back() -> void:
	GenUtil.play_ui_sound(self, "back")
	can_control = false
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
