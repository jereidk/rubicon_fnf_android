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
##
## Investigated and NOT a bug: freeplay's film-reel (Layer_3/Layer_4,
## FREEPLAY_REEL_F/_B) looks sharp here but blurred in a real reference
## screenshot the user had. Checked both possible real sources of that blur
## and found neither: the reel's own bitmap in spritemap1.png has hard,
## non-gradient edges (no baked-in blur), and Animation.json has zero
## filter definitions anywhere (grepped the whole file) — so the real game
## doesn't draw it blurred either. What IS real: the reel's own M3D
## translation data shows a fast one-time entrance slide (~1089px in 19
## frames, ~0.24s at 80fps) during 'start', settling into a slow gentle
## bob for the rest of the loop — if the reference was a video/gif frame
## grabbed mid-slide, real motion blur from that capture would show up
## there and never here, since a Godot screenshot is a true instantaneous
## frame with nothing to blur. Left sharp per explicit request rather than
## faking a motion-blur shader for something the real engine doesn't
## render blurred either.

## freeplay/gauntlet/accolades/gallery's "position" below is NOT the literal
## real setPosition() value (that's still (-2325,-250)/(-1250,-1100)/
## (-1300,370)/(850,750) in HQMainMenu.hx) — using the real value renders
## these four ~150-700 units too far right and ~180-260 too far down,
## bleeding into the menu button column (confirmed against real screenshots
## of all 7 items; story, credits, settings, shop match the real value
## exactly with no correction needed — freeplay looked close enough at a
## glance to be waved through once, but a precise grid-aligned comparison
## against the real screenshot showed it was off too, same as the other
## three). Root cause not found: position/scale, the stage_transform offset
## (see setup()), and the AN.STI's TRP field (which gdanimate ignores
## uniformly for every item, working ones included) were all ruled out —
## likely some other per-file quirk in how these four
## Animation.json's root symbol was authored. Values below are empirically
## calibrated by measuring the pixel offset between this port's render and
## real reference screenshots (tools/holyquintet/all_items_positions.gd +
## *_grid.png comparisons), not derived from the source.
const ITEM_DATA := {
	"story": {"folder": "anim_story", "symbol": "Story_Animation", "position": Vector2(1300, 1000), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"freeplay": {"folder": "anim_freeplay", "symbol": "Freeplay_Animation", "position": Vector2(-3028, -500), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"gauntlet": {"folder": "anim_gauntlet", "symbol": "Gauntlet_Animation", "position": Vector2(-1496, -1355), "scale": Vector2(1.1, 1.1), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"credits": {"folder": "anim_credits", "symbol": "Credits_Animation", "position": Vector2(675, 675), "scale": Vector2(1.15, 1.15), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"accolades": {"folder": "anim_accolades", "symbol": "Accolades_Animation", "position": Vector2(-1809, 137), "scale": Vector2(1.2, 1.2), "start": Vector2i(0, 59), "loop": Vector2i(60, 179)},
	"gallery": {"folder": "anim_gallery", "symbol": "Gallery_Animation", "position": Vector2(665, 546), "scale": Vector2(1.35, 1.35), "start": Vector2i(0, 90), "loop": Vector2i(91, 210)},
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

	# The Animate file's own AN.STI ("stage instance") often carries a large
	# translation (its own registration-point offset — e.g. anim_story's is
	# (-798.35, -464.65); anim_freeplay's is (3190.95, 1025.35), which is
	# exactly why its setPosition() above is such a large negative number:
	# the two are designed to cancel out to a sane on-screen spot). The addon
	# parses this into atlas.stage_transform, but only ever *applies* it when
	# AnimateSymbol.symbol fails to match a real entry in atlas.symbols — and
	# every one of these root/stage symbols is ALSO registered under its own
	# name in that same dict, so draw_on() always takes the "direct symbol"
	# path and silently skips stage_transform. Reproducing it by hand here
	# (as AnimateSymbol's own translation-only `offset`) is what actually
	# lines these up with the real game instead of drawing them all bunched
	# near this node's raw position.
	offset = atlas.stage_transform.origin

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
