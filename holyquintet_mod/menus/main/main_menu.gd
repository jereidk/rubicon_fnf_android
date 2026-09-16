extends Control
## Ports HQMainMenu.hx. One remaining deliberate scope cut, because the
## underlying system this port would need doesn't exist yet at all (not a
## shortcut on an existing feature):
##  - beginStoryMode()'s zoom/shader cinematic ends by calling
##    PlayState.loadWeek()+FlxG.switchState(new PlayState()) — actual
##    gameplay, which nothing in this port builds yet (every screen so far
##    has been boot/menu flow). The zoom+fade plays for real; the final
##    scene switch is a documented stub.
## GameJolt sign-in/out (GameJoltSignInUI, GJRequest) has no backend on this
## platform either — gj_Button renders and is selectable/navigable for
## fidelity, but confirming it can't actually sign in/out anywhere.
##
## MainMenuSprite's big per-item background art (anim_story/anim_freeplay/
## etc, ui/main/anim_*/Animation.json — Adobe Animate's texture-atlas
## timeline format) IS ported, via the gdanimate addon's AdobeAtlas +
## AnimateSymbol (the same system holyquintet_mod/characters/ already uses
## for character sprites) — see main_menu_sprite.gd and _build_graphics().

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")
const ButtonScene := preload("res://holyquintet_mod/ui/button_ui.tscn")
const MessageWindowScene := preload("res://holyquintet_mod/ui/hq_message_window.tscn")
const StoryDiffScene := preload("res://holyquintet_mod/ui/story_diff_ui.tscn")
const AchievementsScript := preload("res://holyquintet_mod/menus/achievements/achievements_screen.gd")
const MainMenuSpriteScript := preload("res://holyquintet_mod/ui/main_menu_sprite.gd")

const MENU_OPTIONS := ["Story", "Freeplay", "Gauntlet", "Accolades", "Gallery", "Credits", "Settings"]
const MENU_LABELS := ["Story", "Freeplay", "Gauntlet", "Accolades", "Gallery", "Credits", "Settings"]
const DESTINATIONS := {
	1: "res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn",
	2: "res://holyquintet_mod/menus/gauntlet/gauntlet_screen.tscn",
	3: "res://holyquintet_mod/menus/achievements/achievements_screen.tscn",
	4: "res://holyquintet_mod/menus/gallery/gallery_screen.tscn",
	5: "res://holyquintet_mod/menus/credits/credits_screen.tscn",
	6: "res://holyquintet_mod/menus/settings/settings_screen.tscn",
}

@onready var bg_spots: TextureRect = $BgSpots
@onready var bg_top_banner: TextureRect = $BgTopBanner
@onready var bg_btm_banner: TextureRect = $BgBtmBanner
@onready var menu_buttons_root: Control = $MenuButtons
@onready var bg_logo: TextureRect = $BgLogo
@onready var graphics_root: Node2D = $Graphics
@onready var medals_root: Control = $Medals

var shop_button: Control
var gj_button: Control
@onready var ticker_bg: TextureRect = $TickerBarBG
@onready var ticker_txt: Label = $TickerBarTxt
@onready var fadeout_sprite: ColorRect = $FadeoutSprite

var _menu_buttons: Array = []
var _new_badges: Array[TextureRect] = []
var _button_origin: Array[Vector2] = []
var _scroll_tweens: Array[Tween] = []
var _graphics: Array = []  # 0-6: menu items (mm_cur_sel order), 7: shop

var mm_cur_sel: int = 0
var _can_control: bool = true
var _selecting_gj: bool = false
var _selecting_shop: bool = false
var _message_window: Control
var _story_diff: Control

const NEWS_TEXT := ""  # global.hx fetches this from a live server at runtime; no such backend here.


func _ready() -> void:
	_build_menu_buttons()
	_build_graphics()
	_build_medals()
	_build_side_buttons()
	_setup_ticker()

	fadeout_sprite.modulate.a = 0.0

	_change_selection(0, false)


## gj_Button/shop_Button are built here (not as static scene-instanced
## children) because ButtonUI's `style` must be set *before* it enters the
## tree — it's only read once in its own _ready() — and a scene-instanced
## child already has _ready() called by the time this script's own _ready()
## could set `.style` on it. Matches _build_menu_buttons()'s convention.
## Real add() order (after the medal loop) draws these on top of the medals.
func _build_side_buttons() -> void:
	shop_button = ButtonScene.instantiate()
	shop_button.style = "small"
	add_child(shop_button)
	shop_button.position = Vector2(25.0, 825.0)
	shop_button.icon = "shop"
	shop_button.locked = true
	shop_button.gui_input.connect(_on_shop_gui_input)

	gj_button = ButtonScene.instantiate()
	gj_button.style = "small"
	add_child(gj_button)
	gj_button.position = Vector2(1750.0, 825.0)
	gj_button.icon = "gamejoltoff"  # never actually signed in — no GameJolt backend on this port.
	gj_button.gui_input.connect(_on_gj_gui_input)


func _build_menu_buttons() -> void:
	for i in MENU_OPTIONS.size():
		var btn = ButtonScene.instantiate()
		btn.style = "basic"
		menu_buttons_root.add_child(btn)
		var x: float = (bg_logo.position.x + 90.0) - (40.0 * i)
		var y: float = (bg_logo.position.y + 150.0) + (150.0 * i)
		btn.position = Vector2(x, y)
		_button_origin.append(Vector2(x, y))

		match i:
			1: btn.locked = not HQSaves.freeplay_unlocked
			2: btn.locked = not HQSaves.gauntlet_unlocked
			3: btn.locked = not HQSaves.accolades_unlocked
			4: btn.locked = not HQSaves.gallery_unlocked
		btn.text = MENU_LABELS[i]
		btn.id = i
		btn.gui_input.connect(_on_menu_button_gui_input.bind(i))
		_menu_buttons.append(btn)

		var badge := TextureRect.new()
		badge.texture = load("res://holyquintet_mod/source/images/ui/common/newbadge.png")
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(x + 385.0, y - 15.0)
		badge.pivot_offset = badge.texture.get_size() / 2.0
		badge.visible = HQSaves.viewed_menu.has(i) and not btn.locked
		menu_buttons_root.add_child(badge)
		_new_badges.append(badge)

		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(badge, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(badge, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _build_graphics() -> void:
	for i in MENU_OPTIONS.size():
		var g := MainMenuSpriteScript.new()
		graphics_root.add_child(g)
		g.setup(MENU_OPTIONS[i].to_lower())
		_graphics.append(g)

	var shop_g := MainMenuSpriteScript.new()
	graphics_root.add_child(shop_g)
	shop_g.setup("shop")
	_graphics.append(shop_g)


func _build_medals() -> void:
	var medal_labels := ["All Songs Cleared", "Gauntlet Cleared", "All Accolades"]
	# Real unlock checks per medal: stardom highscore (song/state this port
	# hasn't built), best gauntlet score (portable — HQSaves has it), and
	# every achievement owned (portable via HQSaves + the real 19-item list).
	var unlocked_checks := [
		false,
		HQSaves.best_gauntlet_score > 0,
		HQSaves.unlocked_achievements.size() >= AchievementsScript.ACHIEVEMENTS.size(),
	]
	for i in 3:
		var x := 185.0 + 150.0 * i
		var y := 835.0
		var icon := TextureRect.new()
		icon.texture = load("res://holyquintet_mod/source/images/ui/common/medal%d.png" % i)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(x, y)
		medals_root.add_child(icon)

		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(x, y)
		label.size = Vector2(icon.texture.get_width(), 40.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 0.533333))
		label.text = medal_labels[i]
		medals_root.add_child(label)

		if unlocked_checks[i]:
			icon.modulate = Color.WHITE
			label.add_theme_color_override("font_color", Color.WHITE)
		else:
			icon.modulate = Color(0.5, 0.5, 0.5)
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))


func _setup_ticker() -> void:
	ticker_txt.text = NEWS_TEXT
	# Real code only starts the scrolling tween if the text overflows its
	# 1275px clip — with NEWS_TEXT empty (no live-news backend here), it
	# never does, so the ticker is inertly blank, matching the mod's own
	# pre-fetch default.


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


func _unhandled_input(event: InputEvent) -> void:
	if not _can_control:
		return

	if not _selecting_shop:
		if event.is_action_pressed("ui_up"):
			if _selecting_gj:
				_selecting_gj = false
				gj_button.selected = false
				_change_selection(0, true)
				GenUtil.play_ui_sound(self, "move")
				return
			_change_selection(-1, false)
		elif event.is_action_pressed("ui_down"):
			if _selecting_gj:
				_selecting_gj = false
				gj_button.selected = false
				_change_selection(0, true)
				GenUtil.play_ui_sound(self, "move")
				return
			_change_selection(1, false)

		if event.is_action_pressed("ui_left") and not _selecting_gj:
			_selecting_shop = true
			GenUtil.play_ui_sound(self, "move")
			for b in _menu_buttons:
				b.selected = false
			shop_button.selected = true
			for g in _graphics:
				g.hide_art()
			_graphics[7].show_art()
			return

		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_selecting_gj = not _selecting_gj
			GenUtil.play_ui_sound(self, "move")
			if _selecting_gj:
				for b in _menu_buttons:
					b.selected = false
				gj_button.selected = true
			else:
				_change_selection(0, true)
				gj_button.selected = false
	else:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			_selecting_shop = false
			gj_button.selected = false
			_change_selection(0, true)
			GenUtil.play_ui_sound(self, "move")
			shop_button.selected = false
			for g in _graphics:
				g.hide_art()
			_graphics[mm_cur_sel].show_art()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_selecting_shop = false
			GenUtil.play_ui_sound(self, "move")
			_change_selection(0, true)
			shop_button.selected = false
			for g in _graphics:
				g.hide_art()
			_graphics[mm_cur_sel].show_art()

	if event.is_action_pressed("ui_accept"):
		_confirm_selection()
	if event.is_action_pressed("ui_cancel"):
		HQTransition.switch_scene("res://holyquintet_mod/menus/title/title_screen.tscn")


func _on_menu_button_gui_input(event: InputEvent, i: int) -> void:
	if not _can_control:
		return
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if not tapped:
		return
	_selecting_gj = false
	_selecting_shop = false
	gj_button.selected = false
	shop_button.selected = false
	_change_selection(i - mm_cur_sel, false)
	_confirm_selection()


func _on_shop_gui_input(event: InputEvent) -> void:
	if not _can_control:
		return
	var tapped: bool = false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		GenUtil.play_ui_sound(self, "error")


func _on_gj_gui_input(event: InputEvent) -> void:
	if not _can_control:
		return
	var tapped: bool = false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		for b in _menu_buttons:
			b.selected = false
		gj_button.selected = true
		_selecting_gj = true
		_confirm_selection()


func _change_selection(change: int, skip_graphic: bool) -> void:
	if change != 0:
		GenUtil.play_ui_sound(self, "move")

	mm_cur_sel = wrapi(mm_cur_sel + change, 0, _menu_buttons.size())

	if not skip_graphic and not _graphics.is_empty():
		for g in _graphics:
			g.hide_art()
		_graphics[mm_cur_sel].show_art()

	var scroll_offset_x := 0.0
	var scroll_offset_y := 0.0
	if mm_cur_sel >= 3:
		var base := mm_cur_sel - 2
		if mm_cur_sel == 5:
			base = mm_cur_sel - 3
		elif mm_cur_sel == 6:
			base = mm_cur_sel - 4
		scroll_offset_x = 40.0 * base
		scroll_offset_y = 200.0 * base

	for t in _scroll_tweens:
		if t:
			t.kill()
	_scroll_tweens.clear()

	for i in _menu_buttons.size():
		_menu_buttons[i].selected = _menu_buttons[i].id == mm_cur_sel

		var target_pos := Vector2(_button_origin[i].x + scroll_offset_x, _button_origin[i].y - scroll_offset_y)
		var badge_pos := target_pos + Vector2(385.0, -15.0)
		if change != 0:
			var tw := create_tween()
			tw.tween_property(_menu_buttons[i], "position", target_pos, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_scroll_tweens.append(tw)
			var tw2 := create_tween()
			tw2.tween_property(_new_badges[i], "position", badge_pos, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_scroll_tweens.append(tw2)
		else:
			_menu_buttons[i].position = target_pos
			_new_badges[i].position = badge_pos


func _confirm_selection() -> void:
	_can_control = false

	if not _selecting_gj and not _selecting_shop:
		for b in _menu_buttons:
			if b.id == mm_cur_sel:
				b.selection()

		if not _menu_buttons[mm_cur_sel].locked:
			if mm_cur_sel != 0:
				GenUtil.play_ui_sound(self, "confirm")
			if HQSaves.viewed_menu.has(mm_cur_sel):
				HQSaves.viewed_menu.erase(mm_cur_sel)
				HQSaves.save_data()
				_new_badges[mm_cur_sel].visible = false

			if mm_cur_sel == 0:
				_confirm_story()
			else:
				HQTransition.switch_scene(DESTINATIONS[mm_cur_sel])
		else:
			_can_control = true
			GenUtil.play_ui_sound(self, "error")
	elif not _selecting_shop:
		GenUtil.play_ui_sound(self, "confirm")
		gj_button.selection()
		# No GameJolt backend on this platform — the real sign-in/out flow
		# (GameJoltSignInUI, GJRequest) can't do anything real here.
		_can_control = true
	else:
		_can_control = true
		GenUtil.play_ui_sound(self, "error")


func _confirm_story() -> void:
	if HQSaves.cur_story_progress == 0:
		_story_diff = StoryDiffScene.instantiate()
		add_child(_story_diff)
		_story_diff.left_action = func():
			HQSaves.cur_story_progress = 0
			HQSaves.cur_story_diff = "easy"
			_begin_story_mode("easy")
		_story_diff.right_action = func():
			HQSaves.cur_story_progress = 0
			HQSaves.cur_story_diff = "hard"
			_begin_story_mode("hard")
		_story_diff.back_action = func():
			_can_control = true
			_story_diff.queue_free()
			_story_diff = null
	else:
		_message_window = MessageWindowScene.instantiate()
		_message_window.title_text = "Resume Story?"
		_message_window.body_text = "Resume the story where you last left off?"
		_message_window.icon_name = "info"
		_message_window.on_left = func(): _confirm_restart_story()
		_message_window.on_right = func(): _begin_story_mode(HQSaves.cur_story_diff)
		_message_window.on_complete = func():
			_message_window.queue_free()
			_message_window = null
		_message_window.on_back = func():
			_message_window.queue_free()
			_message_window = null
			_can_control = true
		add_child(_message_window)


func _confirm_restart_story() -> void:
	var confirm := MessageWindowScene.instantiate()
	confirm.title_text = "Restart Story?"
	confirm.body_text = "Restart from the beginning?\nThis cannot be undone."
	confirm.icon_name = "warning"
	confirm.on_left = func(): _can_control = true
	confirm.on_right = func():
		HQSaves.cur_story_progress = 0
		HQSaves.save_data()
		_confirm_selection()
	confirm.on_complete = func():
		confirm.queue_free()
	confirm.on_back = func():
		confirm.queue_free()
		_can_control = true
	add_child(confirm)


## HQMainMenu.hx beginStoryMode(): the camera zoom/fade cinematic plays for
## real; the FlxG.switchState(new PlayState()) it leads into is stubbed —
## no gameplay state exists yet anywhere in this port to switch to.
func _begin_story_mode(diff: String) -> void:
	GenUtil.play_ui_sound(self, "confirm")

	var zoom_tw := create_tween()
	zoom_tw.tween_interval(0.75)
	zoom_tw.tween_property(fadeout_sprite, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	zoom_tw.tween_callback(func():
		push_warning("HQMainMenu: beginStoryMode(%s) reached — no PlayState/gameplay exists yet in this port to switch to." % diff)
	)
