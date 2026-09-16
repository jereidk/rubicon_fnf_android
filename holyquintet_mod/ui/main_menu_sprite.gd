extends AnimateSymbol
class_name MainMenuSprite
## Ports HQMainMenu.hx's MainMenuSprite (lines 746-910): the big Adobe-Animate
## background illustration behind each of the 8 main-menu items, via the
## gdanimate addon (AdobeAtlas/AnimateSymbol) already used throughout
## holyquintet_mod/characters/ for character sprites.
##
## Real addAnim('start', symbol, 80, false, false, [0..59]) / addAnim('loop',
## symbol, 60, true, true, [60..179]) register two named sub-animations that
## play specific frame *ranges* of the one root symbol timeline at a custom
## fps that isn't the atlas's own native rate (60 for every one of these
## items — checked against each Animation.json's MD.FRT). AnimateSymbol's
## built-in playing/loop autoplay always steps the WHOLE timeline at
## atlas.get_framerate(), so it can't reproduce a *sub-range* at a *custom*
## fps — frame stepping is driven manually with a Tween instead, matching
## each addAnim(...)'s exact range/fps/loop. showArt()'s playAnim('start',
## true) always restarts from frame 0 of the range; _play_start() does the
## same. The real "stupid fix" in update() (globalCurFrame >= length ->
## playAnim('loop', false)) is replaced by simply chaining the loop phase
## onto the start tween's completion — same outcome, no polling needed.

const ITEM_DATA := {
	"story": {"folder": "anim_story", "symbol": "Story_Animation", "position": Vector2(1300, 1000), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"freeplay": {"folder": "anim_freeplay", "symbol": "Freeplay_Animation", "position": Vector2(-2325, -250), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"gauntlet": {"folder": "anim_gauntlet", "symbol": "Gauntlet_Animation", "position": Vector2(-1250, -1100), "scale": Vector2(1.1, 1.1), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"credits": {"folder": "anim_credits", "symbol": "Credits_Animation", "position": Vector2(675, 675), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"accolades": {"folder": "anim_accolades", "symbol": "Accolades_Animation", "position": Vector2(-1300, 370), "scale": Vector2(1.2, 1.2), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"gallery": {"folder": "anim_gallery", "symbol": "Gallery_Animation", "position": Vector2(850, 750), "scale": Vector2(1.35, 1.35), "start": Vector2i(0, 90), "loop": Vector2i(91, 210)},
	"settings": {"folder": "anim_settings", "symbol": "Settings_Animation", "position": Vector2(850, 700), "scale": Vector2(1.2, 1.2), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"shop": {"folder": "anim_shop", "symbol": "Shop_Animation", "position": Vector2(800, 500), "scale": Vector2(1.0, 1.0), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
}

const START_FPS := 80.0
const LOOP_FPS := 60.0
const ASSET_ROOT := "res://holyquintet_mod/source/images/ui/main/"

var item: String = ""
var _play_tween: Tween


func setup(item_name: String) -> void:
	item = item_name
	var d: Dictionary = ITEM_DATA[item]
	position = d["position"]
	scale = d["scale"]
	# Matches the same top-left (not centered) placement already established
	# and render-verified for character AdobeAtlas usage (chr_madoka_base.tscn)
	# — FunkinSprite.setPosition() is a plain FlxSprite x/y, not a pivot.
	centered = false
	symbol = d["symbol"]

	var atlas := AdobeAtlas.new()
	atlas.folder_path = ASSET_ROOT + d["folder"] + "/"
	atlases = [atlas]

	visible = false


func show_art() -> void:
	visible = true
	_play_start()


func hide_art() -> void:
	visible = false
	if _play_tween:
		_play_tween.kill()


func _play_start() -> void:
	if _play_tween:
		_play_tween.kill()
	var rng: Vector2i = ITEM_DATA[item]["start"]
	var duration: float = float(rng.y - rng.x + 1) / START_FPS
	_play_tween = create_tween()
	_play_tween.tween_property(self, "frame", rng.y, duration).from(rng.x).set_trans(Tween.TRANS_LINEAR)
	_play_tween.tween_callback(_play_loop)


func _play_loop() -> void:
	var rng: Vector2i = ITEM_DATA[item]["loop"]
	var duration: float = float(rng.y - rng.x + 1) / LOOP_FPS
	_play_tween = create_tween()
	_play_tween.set_loops()
	_play_tween.tween_property(self, "frame", rng.y, duration).from(rng.x).set_trans(Tween.TRANS_LINEAR)
