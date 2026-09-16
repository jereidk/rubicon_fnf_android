extends Control
## Ports HQMainMenu.hx. One remaining deliberate scope cut, because the
## underlying system this port would need doesn't exist yet at all (not a
## shortcut on an existing feature):
##  - beginStoryMode()'s full cinematic plays for real (sound, music
##    fadeout, camera spin+zoom, the Bloom/Transverse/adjustColor shader
##    trio, fade to black — see _begin_story_mode() and shaders/
##    story_cinematic.gdshader). Only its ending,
##    PlayState.loadWeek()+FlxG.switchState(new PlayState()), is a
##    documented stub, since no actual gameplay exists yet anywhere in this
##    port (every screen so far has been boot/menu flow).
## GameJolt sign-in/out (GameJoltSignInUI, GJRequest) has no backend on this
## platform either — gj_Button renders and is selectable/navigable for
## fidelity, but confirming it can't actually sign in/out anywhere.
##
## MainMenuSprite's big per-item background art (anim_story/anim_freeplay/
## etc, ui/main/anim_*/Animation.json — Adobe Animate's texture-atlas
## timeline format) IS ported, via the gdanimate addon's AdobeAtlas +
## AnimateSymbol (the same system holyquintet_mod/characters/ already uses
## for character sprites) — see main_menu_sprite.gd and _build_graphics().
##
## bg_Back (main_menu.tscn) intentionally has NO CanvasItemMaterial anymore.
## Real code sets bg_Back.blend = BlendMode.MULTIPLY (a darkening vignette
## over bg_Spr/bg_Spots), and Godot does expose CanvasItemMaterial.
## BLEND_MODE_MUL — but on this project's "GL Compatibility" rendering
## method it does not work at all: verified directly (tools/holyquintet/
## multiply_blend_debug*.gd) that BLEND_MODE_MUL zeroes RGB *and* alpha to
## (0,0,0,0), even for a fully-opaque, texture-free ColorRect with no
## transparency anywhere — not a quirk of back.png's own alpha gradient.
## Since back.png's darkening tint is already dark/desaturated (~(64,59,73)
## at its most opaque, fading to fully transparent), drawing it with plain
## alpha blending (the default, no material) reproduces the intended vignette
## closely enough without depending on a blend mode that's non-functional
## here. holyquintet_mod/menus/pause/pause_blend_mul.tres sets the same
## BLEND_MODE_MUL and is currently unused — it will hit this identical wall
## whenever something does start using it.

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

## Pivot/SceneGroup: real FlxG.camera zoom/rotate (beginStoryMode) affects
## *everything* drawn in the state, not just one sprite. Pivot sits at
## screen center so rotating/scaling it (see _begin_story_mode()) matches a
## real camera zooming/spinning around the screen's center; SceneGroup is
## offset back to (0,0) so its children keep their normal absolute
## positions at rest. (beginStoryMode()'s three camera shaders are applied
## separately, at runtime, by reparenting Pivot into a SubViewport for that
## one cinematic — see _apply_story_cinematic_shader() for why a CanvasGroup
## here doesn't work.) Children of SceneGroup that used anchors_preset=15
## (full-rect stretch against the nearest Control ancestor) had to become an
## explicit position=(0,0)/size=(1920,1080) instead: SceneGroup is a Node2D,
## not a Control, so percentage-based anchors silently resolve against
## nothing and collapse those nodes to size (0,0) — confirmed directly
## (tools/holyquintet/canvasgroup_anchor_test.gd) before this restructure,
## not assumed.
@onready var pivot: Node2D = $Pivot
@onready var scene_group: Node2D = $Pivot/SceneGroup
@onready var bg_spots: TextureRect = $Pivot/SceneGroup/BgSpots
@onready var bg_top_banner: TextureRect = $Pivot/SceneGroup/BgTopBanner
@onready var bg_btm_banner: TextureRect = $Pivot/SceneGroup/BgBtmBanner
@onready var menu_buttons_root: Control = $Pivot/SceneGroup/MenuButtons
@onready var bg_logo: TextureRect = $Pivot/SceneGroup/BgLogo
@onready var ticker_bg: TextureRect = $Pivot/SceneGroup/TickerBarBG
@onready var ticker_clip: Control = $Pivot/SceneGroup/TickerClip
@onready var ticker_txt: Label = $Pivot/SceneGroup/TickerClip/TickerBarTxt
@onready var fadeout_sprite: ColorRect = $Pivot/SceneGroup/FadeoutSprite

var graphics_root: Node2D
var medal_icons_root: Control
var medal_labels_root: Control
var shop_button: Control
var gj_button: Control
var outdated_txt: Label

var _menu_buttons: Array = []
var _new_badges: Array[TextureRect] = []
var _button_origin: Array[Vector2] = []
var _scroll_tweens: Array[Tween] = []
var _graphics: Array = []  # 0-6: menu items (mm_cur_sel order), 7: shop
var _ticker_tween: Tween

var mm_cur_sel: int = 0
var _can_control: bool = true
var _selecting_gj: bool = false
var _selecting_shop: bool = false
var _message_window: Control
var _story_diff: Control

## global.hx fetches this live: HttpUtil.requestText() on the mod author's
## Google Doc, synchronously (blocking) on native. Godot does the same fetch
## (see _setup_ticker()/_on_news_fetched()) but via HTTPRequest so it can't
## block/ANR the main thread on Android — same end result, different
## mechanism for a platform reason, not a fidelity cut.
const NEWS_DOC_URL := "https://docs.google.com/document/d/1x60PXXBA4VXk9n0UNhKbrsTCDu4qKyPE73KSs9zDzTg/edit?usp=sharing"
## global.hx's own hardcoded thisVersionNumber, compared against the doc's
## version marker to show outdatedTxt — see _setup_outdated_text() and
## _on_news_fetched(). Bump this by hand if this port itself falls behind a
## newer released version of the mod.
const THIS_VERSION_NUMBER := "1.0.7"


## Node draw order below is built to exactly match the real create()'s
## add()/insert() sequence, not just "looks right" — the big adobe-animate
## art is large enough to reach past the bottom banner, and the real game
## clips it there (art draws BEHIND bg_BtmBanner's checkered border), which
## a naive "put art on top of everything" order gets backwards. Real order,
## derived from where each insert(members.indexOf(X), ...) lands relative to
## the plain add()s around it:
##   BgSpr, BgSpots, BgBack, MenuButtons(+badges), BgLogo, BgTopBanner,
##   Graphics, MedalIcons, BgBtmBanner, MedalLabels, GjButton, ShopButton,
##   FadeoutSprite, TickerBarBG, TickerBarTxt.
## MenuButtons/BgLogo/BgTopBanner/BgBtmBanner/FadeoutSprite/TickerBar* are
## static children in main_menu.tscn already in that relative order;
## Graphics/MedalIcons/MedalLabels/GjButton/ShopButton are built here and
## slotted into place with move_child() since ButtonUI and MainMenuSprite
## both need setup before entering the tree (see _build_side_buttons()).
func _ready() -> void:
	# Real: CoolUtil.playMenuSong(false) — idempotent, only (re)starts menu.ogg
	# if it isn't already playing (e.g. after Gauntlet/Gallery/Settings called
	# stop_music() below, or a first-ever entry with no music at all yet; a
	# no-op if Title's own playMusic('menu') call already has it going).
	HQTransition.play_menu_music()

	_build_menu_buttons()
	_build_graphics()
	_build_medal_icons()
	_build_medal_labels()
	_build_side_buttons()
	_setup_ticker()
	_setup_outdated_text()

	fadeout_sprite.modulate.a = 0.0

	_change_selection(0, false)


## gj_Button/shop_Button are built here (not as static scene-instanced
## children) because ButtonUI's `style` must be set *before* it enters the
## tree — it's only read once in its own _ready() — and a scene-instanced
## child already has _ready() called by the time this script's own _ready()
## could set `.style` on it. Matches _build_menu_buttons()'s convention.
## Real order is gj_Button then shop_Button, both drawn on top of the medal
## labels but under fadeoutSprite/the ticker.
func _build_side_buttons() -> void:
	gj_button = ButtonScene.instantiate()
	gj_button.style = "small"
	scene_group.add_child(gj_button)
	scene_group.move_child(gj_button, fadeout_sprite.get_index())
	gj_button.position = Vector2(1750.0, 825.0)
	gj_button.icon = "gamejoltoff"  # never actually signed in — no GameJolt backend on this port.
	gj_button.gui_input.connect(_on_gj_gui_input)

	shop_button = ButtonScene.instantiate()
	shop_button.style = "small"
	scene_group.add_child(shop_button)
	scene_group.move_child(shop_button, fadeout_sprite.get_index())
	shop_button.position = Vector2(25.0, 825.0)
	shop_button.icon = "shop"
	shop_button.locked = true
	shop_button.gui_input.connect(_on_shop_gui_input)


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
	graphics_root = Node2D.new()
	scene_group.add_child(graphics_root)
	scene_group.move_child(graphics_root, bg_btm_banner.get_index())

	for i in MENU_OPTIONS.size():
		var g := MainMenuSpriteScript.new()
		graphics_root.add_child(g)
		g.setup(MENU_OPTIONS[i].to_lower())
		_graphics.append(g)

	var shop_g := MainMenuSpriteScript.new()
	graphics_root.add_child(shop_g)
	shop_g.setup("shop")
	_graphics.append(shop_g)


## Real newMedal icons are insert()ed at the same anchor as the graphics
## (right before bg_BtmBanner, after them) — so the icons sit in front of
## whichever item's art is currently showing, still behind the bottom
## banner. The text labels are separate: real code adds them with a plain
## add(), which always appends past everything that exists yet, landing
## them *after* bg_BtmBanner instead — see _build_medal_labels().
func _build_medal_icons() -> void:
	medal_icons_root = Control.new()
	medal_icons_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_group.add_child(medal_icons_root)
	scene_group.move_child(medal_icons_root, bg_btm_banner.get_index())

	var unlocked_checks := _medal_unlocked_checks()
	for i in 3:
		var icon := TextureRect.new()
		icon.texture = load("res://holyquintet_mod/source/images/ui/common/medal%d.png" % i)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(185.0 + 150.0 * i, 835.0)
		medal_icons_root.add_child(icon)
		# Real: newMedal.color=BLACK, alpha=0.5 when locked (a dim, translucent
		# silhouette) vs color=WHITE, alpha=1.0 unlocked — not a plain gray
		# tint, which left these looking barely dimmed instead of a near-dark
		# silhouette on a fresh save.
		icon.modulate = Color.WHITE if unlocked_checks[i] else Color(0, 0, 0, 0.5)


## Real code: medalText.text = i18n.tr('Main/Medals/AllSongsCleared') (and
## GauntletCleared/AllAccolades). CORRECTION: an earlier pass here concluded
## these keys were missing from the mod's translations and blanked this text
## out — that was checked against holyquintet_mod/source/data/langs/en_US/
## (and es_US/) translations.json, which turned out to be the wrong asset
## entirely (chart note-timing data, not JSON translations — a bad file
## landed at that path at some point; now replaced with the real extracted
## translations.json, which has all three keys with exactly these strings).
func _build_medal_labels() -> void:
	medal_labels_root = Control.new()
	medal_labels_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_group.add_child(medal_labels_root)
	scene_group.move_child(medal_labels_root, bg_btm_banner.get_index() + 1)

	var medal_text := ["All Songs Cleared", "Gauntlet Cleared", "All Accolades"]
	var unlocked_checks := _medal_unlocked_checks()
	for i in 3:
		var icon_w: float = load("res://holyquintet_mod/source/images/ui/common/medal%d.png" % i).get_width()
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(185.0 + 150.0 * i, 835.0)
		label.size = Vector2(icon_w, 40.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 0.533333))
		label.text = medal_text[i]
		label.add_theme_color_override("font_color", Color.WHITE if unlocked_checks[i] else Color(0.5, 0.5, 0.5))
		medal_labels_root.add_child(label)


## Real unlock checks per medal: stardom highscore (song/state this port
## hasn't built), best gauntlet score (portable — HQSaves has it), and
## every achievement owned (portable via HQSaves + the real 19-item list).
func _medal_unlocked_checks() -> Array:
	return [
		false,
		HQSaves.best_gauntlet_score > 0,
		HQSaves.unlocked_achievements.size() >= AchievementsScript.ACHIEVEMENTS.size(),
	]


## Real: FlxText(250,250,0,i18n.tr('Main/Outdated')), 32pt red OUTLINE text,
## screenCenter(FlxAxes.X) (so only the x-position is centered across the
## full 1920 width; y stays literally 250), hidden unless onOutdatedBuild —
## which _on_news_fetched() sets once the doc's version is known.
func _setup_outdated_text() -> void:
	outdated_txt = Label.new()
	outdated_txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outdated_txt.position = Vector2(0.0, 250.0)
	outdated_txt.size = Vector2(1920.0, 80.0)
	outdated_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outdated_txt.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	outdated_txt.add_theme_font_size_override("font_size", 32)
	outdated_txt.add_theme_color_override("font_color", Color.RED)
	outdated_txt.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 1.0))
	outdated_txt.add_theme_constant_override("outline_size", 5)
	outdated_txt.text = "The current version you are running on is outdated.\nPlease download an updated version of the mod!"
	outdated_txt.visible = false
	scene_group.add_child(outdated_txt)


## Real create(): tickerBarTxt starts with whatever global.newsText already
## is (usually '' until the fetch below lands, since it's per-session and
## this is the first HQMainMenu visit) — the doc read happens in
## global.hx's preStateSwitch(), not here, but the *result* only ever
## shows up on this screen, so fetching it from here is the equivalent hook.
##
## Real behavior with no internet: blank, always — HttpUtil.hasInternet()
## fails, newsText='' and stays that way for the whole session. Per user
## request this port does better: show the last successfully-fetched text
## (cached in HQSaves) immediately as an optimistic placeholder, then
## replace it with the live result if the fetch succeeds — so a real fetch
## failure/timeout/offline device just keeps showing the cached text
## instead of going blank, and only a truly first-ever run (nothing cached
## yet) looks like the real mod's blank-until-fetched state.
func _setup_ticker() -> void:
	ticker_txt.text = HQSaves.cached_news_text
	ticker_txt.position.x = 0.0
	if not ticker_txt.text.is_empty():
		await get_tree().process_frame
		_start_ticker_scroll()

	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 8.0  # don't hang the fetch forever on a dead/slow connection
	req.request_completed.connect(_on_news_fetched)
	# Real HttpUtil sets a User-Agent header; the doc's unauthenticated HTML
	# response embeds the document text in its og:description meta tag
	# regardless, but matching the header is free and closer to the source.
	var err := req.request(NEWS_DOC_URL, PackedStringArray(["User-Agent: Mozilla/5.0"]))
	if err != OK:
		push_warning("HQMainMenu: news ticker HTTPRequest.request() failed to start (err=%d)" % err)


## Real: hqData = liveData.split('[HQData]')[1].trim(); versionNumber =
## hqData.split('{}')[0].trim(); newsText = hqData.split('{}')[1].trim();
## The raw page is full HTML, not a plain-text export, but the doc's own
## content is embedded verbatim in the <meta property="og:description">
## tag regardless — confirmed by fetching the real URL — so the same
## split-by-marker parsing works unmodified against the HTML body.
##
## Any failure here (bad result/status, unexpected format, offline) just
## returns and leaves whatever _setup_ticker() already put on screen — the
## cached text if there was one, blank otherwise. That's the "smart
## fallback": nothing to specially handle on the failure path, because the
## optimistic cached text was already showing before this ever ran.
func _on_news_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return

	var html := body.get_string_from_utf8()
	var halves := html.split("[HQData]")
	if halves.size() < 2:
		return
	var hq_data := halves[1].strip_edges()

	var kv := hq_data.split("{}")
	if kv.size() < 2:
		return
	var news := kv[1].strip_edges()
	if news.is_empty():
		return

	HQSaves.cached_news_version = kv[0].strip_edges()
	HQSaves.cached_news_text = news
	HQSaves.save_data()

	# Real: thisVersionNumber==versionNumber -> false; else if hasInternet()
	# -> true; else false. This function only ever runs after a *successful*
	# fetch (the guard above already returned on failure/no-internet), so
	# the "no internet" branch can't apply here — outdated is exactly
	# "the doc's version doesn't match ours".
	outdated_txt.visible = HQSaves.cached_news_version != THIS_VERSION_NUMBER

	if news == ticker_txt.text:
		return  # already showing this (the cached text matched what's live) — don't restart the scroll mid-cycle

	ticker_txt.text = news
	await get_tree().process_frame  # let the Label compute its new text size
	_start_ticker_scroll()


## Real (create()): if the text overflows the 1275px clip, scroll it left
## over (2.5 + width/500)s after a 1.5s delay, then fade out/reset/fade in
## and restart — forever. clipRect.x compensates for the sprite's own x
## shift there so the *visible window* stays put on screen while the text
## scrolls under it; here the fixed window is TickerClip (clip_contents,
## static rect) and TickerBarTxt is the child that actually moves, which is
## the direct Control equivalent without needing a separate clip offset.
func _start_ticker_scroll() -> void:
	var text_w: float = ticker_txt.get_theme_font("font").get_string_size(
		ticker_txt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ticker_txt.get_theme_font_size("font_size")
	).x
	if text_w <= 1275.0:
		return
	if _ticker_tween:
		_ticker_tween.kill()
	_run_ticker_scroll_cycle(text_w)


func _run_ticker_scroll_cycle(text_w: float) -> void:
	var duration: float = 2.5 + text_w / 500.0
	ticker_txt.position.x = 0.0
	ticker_txt.modulate.a = 1.0

	_ticker_tween = create_tween()
	_ticker_tween.tween_interval(1.5)
	_ticker_tween.tween_property(ticker_txt, "position:x", -(text_w - 1275.0), duration).set_trans(Tween.TRANS_LINEAR)
	_ticker_tween.tween_interval(2.0)
	_ticker_tween.tween_property(ticker_txt, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ticker_tween.tween_callback(func(): ticker_txt.position.x = 0.0)
	_ticker_tween.tween_property(ticker_txt, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ticker_tween.tween_callback(_run_ticker_scroll_cycle.bind(text_w))


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

			# Real: Gauntlet/Gallery/Settings each bring their own music, so
			# the menu theme is cut here rather than left playing under them.
			if mm_cur_sel == 2 or mm_cur_sel == 4 or mm_cur_sel == 6:
				HQTransition.stop_music()

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
## Real: FlxG.sound.play('ui/ui_storystart') — NOT playUISound('confirm'), a
## distinct one-off cue only used here — then FlxG.sound.music?.fadeOut(1.5,
## 0.0), then the camera itself spins (angle 0->25 over 2.0s expoIn) and
## zooms in two stages (a quick 1.05->1.0 settle over 0.5s expoOut, then
## 1.0->5.0 over 1.5s expoIn) while fadeoutSprite fades to black in parallel
## (1.0s cubeIn, 0.75s startDelay). An earlier pass here only ported the
## fade, not the sound, music cut, or the zoom/spin — this Control has no
## separate camera to move, so the root's own rotation/scale around its
## center (pivot_offset = screen center) stands in for FlxG.camera, the same
## technique title_screen.gd's "World" node uses for its own zoom intro.
## Options.gameplayShaders gates the shader trio in real code; this port has
## no settings/Options system at all yet, so it defaults on (matching how
## the other Options.* checks already ported here behave absent one).
const GAMEPLAY_SHADERS_ENABLED := true

func _begin_story_mode(diff: String) -> void:
	var sfx := AudioStreamPlayer.new()
	sfx.stream = load("res://holyquintet_mod/source/sounds/ui/ui_storystart.ogg")
	get_tree().root.add_child(sfx)
	sfx.finished.connect(sfx.queue_free)
	sfx.play()

	HQTransition.fade_out_music(1.5)

	if GAMEPLAY_SHADERS_ENABLED:
		_apply_story_cinematic_shader()

	var spin_tw := create_tween()
	spin_tw.tween_property(pivot, "rotation", deg_to_rad(25.0), 2.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	var zoom_tw := create_tween()
	zoom_tw.tween_property(pivot, "scale", Vector2(1.0, 1.0), 0.5).from(Vector2(1.05, 1.05)) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	zoom_tw.tween_property(pivot, "scale", Vector2(5.0, 5.0), 1.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	zoom_tw.tween_callback(func():
		push_warning("HQMainMenu: beginStoryMode(%s) reached — no PlayState/gameplay exists yet in this port to switch to." % diff)
	)

	var fade_tw := create_tween()
	fade_tw.tween_interval(0.75)
	fade_tw.tween_property(fadeout_sprite, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Real Bloom/Transverse/adjustColor stack onto FlxG.camera, affecting
## everything drawn in the state at once. A CanvasItem shader's TEXTURE only
## ever means "this node's own assigned texture" — fine for a TextureRect,
## but Pivot/SceneGroup's actual content is a live tree of many separate
## nodes, not one texture. CanvasGroup composites its children into exactly
## the buffer a shader would need, but on this project's GL Compatibility
## renderer a CanvasGroup's own material can't see that buffer either —
## confirmed directly: even a no-op passthrough shader on a CanvasGroup
## renders solid white (tools/holyquintet/canvasgroup_shader_test.gd), the
## same class of limitation already hit for BLEND_MODE_MUL. A SubViewport
## doesn't have that problem in any render method: it's a real, independent
## render target with a real texture, so reparenting Pivot into one and
## displaying that texture through a plain shaded TextureRect works
## everywhere. Reparenting (not duplicating) is safe here specifically
## because nothing under Pivot needs further input by this point —
## _confirm_selection() already set _can_control = false before this ever
## runs, and this is a one-way trip into a stubbed scene switch, never back
## to an interactive main menu.
func _apply_story_cinematic_shader() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child(viewport)

	var old_parent := pivot.get_parent()
	old_parent.remove_child(pivot)
	viewport.add_child(pivot)

	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://holyquintet_mod/menus/main/shaders/story_cinematic.gdshader")
	mat.set_shader_parameter("bloom_amt", -0.25)
	mat.set_shader_parameter("transverse_falloff", 10.0)
	mat.set_shader_parameter("saturation", 0.0)
	mat.set_shader_parameter("contrast", 0.0)
	display.material = mat

	var bloom_tw := create_tween()
	bloom_tw.tween_method(func(v): mat.set_shader_parameter("bloom_amt", v), -0.25, 0.0, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var transverse_tw := create_tween()
	transverse_tw.tween_method(func(v): mat.set_shader_parameter("transverse_falloff", v), 10.0, 0.5, 2.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var grade_tw := create_tween()
	grade_tw.tween_method(func(v):
		mat.set_shader_parameter("saturation", v)
		mat.set_shader_parameter("contrast", v * 2.0)
	, 0.0, 200.0, 2.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
