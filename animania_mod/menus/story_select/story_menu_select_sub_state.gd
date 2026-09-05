extends CanvasLayer
## animania::states::StoryMenuSelectSubState, ported.
##
## IT IS NOT A DIFFICULTY PICKER. The port had it showing Easy/Normal/Hard, and
## the difficulty is already chosen on the story menu itself, with its own arrows
## and its own art. What createButtons (0x3d85860) actually builds is exactly TWO
## buttons - "amtake" and "animania" - so the screen asks WHICH VERSION of the
## week to play. That is the same split the props path carries
## (storymenu/props/amtake/week1/...).
##
## MEASURED:
##
##   createButtons 0x3d85860
##     createButton("amtake",   "menus/AnimaniaTake-logo", -FlxG.width * 0.5, ...)
##     createButton("animania", "menus/Animania-logo",      FlxG.width * 1.1,  ...)
##     - the third argument is where the button STARTS, off-screen left and
##       off-screen right.
##
##   createButton 0x3d849a0
##     a sparrow off menus/story_select_buttons with
##       addByPrefix("idle",     name + " basic")
##       addByPrefix("selected", name + " white")
##     playing "idle", then a FunkinAttachedSprite carrying the logo, then
##     createLock and setupButtonInteractions.
##
##   applyInitialAnimations 0x3d81180
##     both buttons tween their x over 1s with expoInOut:
##       amtake   -> 50                              (0x3d812bd, `movl $0x32`)
##       animania -> (FlxG.width - 50) - its width   (0x3d813f7 `sub $0x32`,
##                                                    then get_width at
##                                                    0x3d81490 and a subsd)
##
##   createBackground 0x3d80040
##     FlxTween.tween(bg, {alpha: 0.6}, 0.75, {ease: backOut})
##
##   __boot 0x3d80eb0, the five statics, in address order:
##     BLUR_INTENSITY 12, CAMERA_ZOOM_BEAT 1.0015, LOGO_HOVER_SCALE 0.375,
##     BUTTON_SCALE 0.95, LOGO_SCALE 0.35
##
##   setupBlurEffect 0x3d81870
##     an openfl BlurFilter on the camera behind, blurX and blurY tweened to
##     BLUR_INTENSITY over 0.75s with {startDelay: 0.4, ease: backOut}; and back
##     to 0 over 0.65s in closeSubState (0x3d81d4f).
##
##   configureMusicFilters 0x3d7f2e0
##     MusicFilterController: setFilter("LOWPASS"), GAIN 0.8, GAINHF 0.05,
##     setEffect("REVERB"), DECAY_TIME 7.5, and one more effect var at 0.25;
##     then applyNow(). The same set goes onto EffectSound.
##
## WHAT THE CHOICE MEANS. The second button is not a second campaign this port
## is missing - it is LOCKED, in the mod too. createButton's fourth argument is
## a bool, and createButtons passes `xor %ecx,%ecx` (false) for amtake and
## `mov $0x1,%ecx` (true) for animania (0x3d858ea and 0x3d859c9); createButton
## tests it at 0x3d85480 and only then calls createLock, which hangs a
## menus/menu/button_lock sparrow on the button. So the mod ships with the
## AnimaniaTake half playable and the original Animania half padlocked, and the
## honest port of "what the choice means" is to draw the padlock and refuse.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

const ART := "res://animania_mod/source/images/menus/story_select"
const BUTTON_FRAMES := "%s/story_select_buttons_frames.tres" % ART
## createLock 0x3d84250: menus/menu/button_lock, animation "buttons lock" at 24.
const LOCK_FRAMES := "res://animania_mod/source/images/menus/menu/button_lock_frames.tres"
const LOCK_ANIM := &"buttons lock"
const LOCK_SCALE := 1.1

## The mod's own logos, 756x540 and 832x540. NOT the 4596x2208 animania_logo.png
## that sits beside them - that one is the credits wordmark, and drawing it here
## unscaled is what filled the screen with a single "CREW".
const LOGOS := {
	"amtake": "%s/AnimaniaTake-logo.png" % ART,
	"animania": "%s/Animania-logo.png" % ART,
}

const BLUR_INTENSITY := 12.0
const CAMERA_ZOOM_BEAT := 1.0015
const LOGO_HOVER_SCALE := 0.375
const BUTTON_SCALE := 0.95
const LOGO_SCALE := 0.35

## createButtons' third argument, the off-screen start, in the mod's 1280 space.
const START_X := {"amtake": -640.0, "animania": 1408.0}
## createButtons' fourth argument. Not a port limitation - the mod locks it too.
const LOCKED := {"amtake": false, "animania": true}
## setupBlurEffect / closeSubState.
const BLUR_IN := 0.75
const BLUR_DELAY := 0.4
const BLUR_OUT := 0.65
## configureMusicFilters. GAINHF 0.05 is a linear high-frequency gain in OpenAL's
## EFX low-pass; Godot's filter is a cutoff instead, so THIS number is a
## translation of that attenuation and not a value read off the binary.
const MUSIC_BUS := &"Music"
const FILTER_CUTOFF := 900.0
const FILTER_GAIN_DB := -1.94  ## 20*log10(0.8), the measured GAIN.
const REVERB_DECAY := 7.5
const REVERB_WET := 0.25
## applyInitialAnimations: the margin on both sides, and how long the slide takes.
const MARGIN := 50.0
const SLIDE_TIME := 1.0
## createBackground.
const BG_ALPHA := 0.6
const BG_FADE := 0.75

## Nine taps per axis, weighted 1/2/3/4/5/4/3/2/1, spaced by blurX/blurY pixels.
## Separable would be two passes and a second viewport; at this radius one pass
## reads 81 texels and llvmpipe still keeps up, so it stays one rect.
const BLUR_SHADER := """
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blurX = 0.0;
uniform float blurY = 0.0;

void fragment() {
	vec2 step = vec2(blurX, blurY) * SCREEN_PIXEL_SIZE;
	if (step.x <= 0.0 && step.y <= 0.0) {
		COLOR = texture(screen, SCREEN_UV);
	} else {
		vec4 sum = vec4(0.0);
		float total = 0.0;
		for (int y = -4; y <= 4; y++) {
			for (int x = -4; x <= 4; x++) {
				float w = (5.0 - abs(float(x))) * (5.0 - abs(float(y)));
				sum += texture(screen, SCREEN_UV + vec2(float(x), float(y)) * step) * w;
				total += w;
			}
		}
		COLOR = sum / total;
	}
}
"""

# ─── Fields ───────────────────────────────────────────────────────────────

var _menu_state: Node  ## Parent StoryMenu reference
var buttons: Array[Node2D] = []
## Todo lo que se DIBUJA cuelga de aqui, y no de la propia pantalla.
##
## Esta clase extiende CanvasLayer, y CanvasLayer no hereda de CanvasItem: no tiene
## `modulate`. Los dos fundidos de salida hacian tween sobre `self, "modulate:a"` y en
## escritorio eso no se ve, pero en el movil salta
## "The tweened property modulate:a does not exist in object CanvasLayer" y la pantalla se
## va de golpe en vez de fundirse. La camara y el reproductor de sonido se quedan fuera:
## una no se modula y el otro no se dibuja.
var content: Node2D
var cool_bg: ColorRect
var select_camera: Camera2D
var selected: String = ""
var blur_shader: ShaderMaterial
var _is_selecting: bool = false
var _order: PackedStringArray = ["amtake", "animania"]
var _bus_effects: int = 0
var _bus_volume: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	content = Node2D.new()
	content.name = "Content"
	add_child(content)
	layer = 10
	_setup_blur_effect()
	_create_background()
	_setup_camera()
	_create_buttons()
	_apply_initial_animations()
	_configure_music_filters()


func _unhandled_input(event: InputEvent) -> void:
	if _is_selecting:
		return

	if event is InputEventKey and event.is_pressed():
		match (event as InputEventKey).keycode:
			KEY_ESCAPE, KEY_BACKSPACE:
				close_sub_state()
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				_navigate_button(-1)
			KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
				_navigate_button(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if selected != "":
					select_story(selected)
		return

	# A tap picks the button it lands on and confirms it, the way it does on
	# every other menu in this port.
	if event is InputEventScreenTouch and event.is_pressed():
		_touch((event as InputEventScreenTouch).position)
	elif event is InputEventMouseButton and event.is_pressed() \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_touch((event as InputEventMouseButton).position)


func _touch(at: Vector2) -> void:
	for i: int in buttons.size():
		var rect: Rect2 = buttons[i].get_meta(&"hitbox", Rect2()) as Rect2
		if rect.has_point(at - buttons[i].position):
			if String(buttons[i].get_meta(&"name", "")) == selected:
				select_story(selected)
			else:
				_select_button(i)
			return


# ─── Scene building ───────────────────────────────────────────────────────

func _create_background() -> void:
	cool_bg = ColorRect.new()
	cool_bg.name = "CoolBg"
	cool_bg.size = SCREEN
	cool_bg.color = Color(0.0, 0.0, 0.0, 1.0)
	cool_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cool_bg.modulate.a = 0.0
	content.add_child(cool_bg)
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cool_bg, "modulate:a", BG_ALPHA, BG_FADE)


## setupBlurEffect: the mod hangs an openfl BlurFilter on the camera behind and
## tweens its blurX/blurY up. Godot has no filter stack on a camera, so the same
## thing is done with a full-screen rect that samples the screen texture and
## blurs it - the sub-state is a CanvasLayer, so what it samples IS the story
## menu underneath. The radius, the delay, the duration and the ease are the
## mod's; the kernel is this port's, because a gaussian is a gaussian.
func _setup_blur_effect() -> void:
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	blur_shader = ShaderMaterial.new()
	blur_shader.shader = shader
	blur_shader.set_shader_parameter("blurX", 0.0)
	blur_shader.set_shader_parameter("blurY", 0.0)

	var rect := ColorRect.new()
	rect.name = "Blur"
	rect.size = SCREEN
	rect.color = Color.WHITE
	rect.material = blur_shader
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(rect)

	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(blur_shader, "shader_parameter/blurX",
		BLUR_INTENSITY, BLUR_IN).set_delay(BLUR_DELAY)
	tw.tween_property(blur_shader, "shader_parameter/blurY",
		BLUR_INTENSITY, BLUR_IN).set_delay(BLUR_DELAY)


func _setup_camera() -> void:
	select_camera = Camera2D.new()
	select_camera.name = "StorySelectCamera"
	select_camera.position = SCREEN * 0.5
	add_child(select_camera)


func _create_buttons() -> void:
	var frames: SpriteFrames = load(BUTTON_FRAMES) as SpriteFrames
	for name: String in _order:
		var btn: Node2D = _create_button(name, frames)
		if btn == null:
			continue
		buttons.append(btn)
		content.add_child(btn)
	if not buttons.is_empty():
		_select_button(0)


## One button: the sparrow art with the logo riding on top of it, both anchored
## at the button's top-left so the pair moves as one when the slide runs.
func _create_button(name: String, frames: SpriteFrames) -> Node2D:
	var container := Node2D.new()
	container.name = name.to_pascal_case()
	container.set_meta(&"name", name)
	container.set_meta(&"locked", bool(LOCKED.get(name, false)))

	var art := AnimatedSprite2D.new()
	art.name = "Art"
	art.centered = false
	art.sprite_frames = frames
	art.scale = Vector2.ONE * BUTTON_SCALE * FUNKIN_TO_RUBICON
	if frames != null and frames.has_animation(StringName("%s basic" % name)):
		art.play(StringName("%s basic" % name))
	container.add_child(art)
	container.set_meta(&"art", art)

	var size: Vector2 = Vector2.ZERO
	if frames != null and frames.has_animation(StringName("%s basic" % name)):
		var tex: Texture2D = frames.get_frame_texture(StringName("%s basic" % name), 0)
		if tex != null:
			size = tex.get_size()
	container.set_meta(&"size", size)
	container.set_meta(&"hitbox",
		Rect2(Vector2.ZERO, size * BUTTON_SCALE * FUNKIN_TO_RUBICON))

	var logo := Sprite2D.new()
	logo.name = "Logo"
	logo.centered = true
	var logo_path: String = String(LOGOS.get(name, ""))
	if ResourceLoader.exists(logo_path):
		logo.texture = load(logo_path) as Texture2D
	logo.scale = Vector2.ONE * LOGO_SCALE * FUNKIN_TO_RUBICON
	# Attached, so it sits on the button's middle and travels with it.
	logo.position = size * 0.5 * BUTTON_SCALE * FUNKIN_TO_RUBICON
	container.add_child(logo)
	container.set_meta(&"logo", logo)

	if bool(LOCKED.get(name, false)):
		var lock := AnimatedSprite2D.new()
		lock.name = "Lock"
		lock.centered = true
		lock.sprite_frames = load(LOCK_FRAMES) as SpriteFrames
		if lock.sprite_frames != null and lock.sprite_frames.has_animation(LOCK_ANIM):
			lock.play(LOCK_ANIM)
		# createLock sets the lock's scale.x and scale.y to 1.1 through the point's
		# own set_x/set_y (0x3d846ec and 0x3d84701, both fed the same 1.1).
		lock.scale = Vector2.ONE * LOCK_SCALE * FUNKIN_TO_RUBICON
		lock.position = size * 0.5 * BUTTON_SCALE * FUNKIN_TO_RUBICON
		container.add_child(lock)

	container.position = Vector2(
		float(START_X.get(name, 0.0)) * FUNKIN_TO_RUBICON, 0.0)
	return container


# ─── Initial animations ───────────────────────────────────────────────────

## Both buttons slide in over a second. The left one stops at a margin of 50; the
## right one stops so its RIGHT edge sits at the same margin, which is why the
## mod reads its width first instead of writing a number.
func _apply_initial_animations() -> void:
	for btn: Node2D in buttons:
		var name: String = String(btn.get_meta(&"name", ""))
		var size: Vector2 = btn.get_meta(&"size", Vector2.ZERO) as Vector2
		var width: float = size.x * BUTTON_SCALE * FUNKIN_TO_RUBICON
		var target: float = MARGIN * FUNKIN_TO_RUBICON
		if name == "animania":
			target = SCREEN.x - MARGIN * FUNKIN_TO_RUBICON - width
		var tw: Tween = create_tween()
		tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(btn, "position:x", target, SLIDE_TIME)


# ─── Button navigation ────────────────────────────────────────────────────

func _navigate_button(dir: int) -> void:
	if buttons.is_empty():
		return
	var current: int = 0
	for i: int in buttons.size():
		if String(buttons[i].get_meta(&"name", "")) == selected:
			current = i
			break
	var next: int = wrapi(current + dir, 0, buttons.size())
	if next == current:
		return
	_select_button(next)
	_play(SOUND_SWITCH)


## The selected button swaps to its "white" frame and its logo grows from
## LOGO_SCALE to LOGO_HOVER_SCALE - 0.35 to 0.375, which is the whole hover.
func _select_button(index: int) -> void:
	if index < 0 or index >= buttons.size():
		return
	selected = String(buttons[index].get_meta(&"name", ""))

	for i: int in buttons.size():
		var btn: Node2D = buttons[i]
		var name: String = String(btn.get_meta(&"name", ""))
		var art: AnimatedSprite2D = btn.get_meta(&"art", null) as AnimatedSprite2D
		var logo: Sprite2D = btn.get_meta(&"logo", null) as Sprite2D
		var on: bool = i == index
		if art != null and art.sprite_frames != null:
			var anim: StringName = StringName("%s %s" % [name, "white" if on else "basic"])
			if art.sprite_frames.has_animation(anim):
				art.play(anim)
		if logo != null:
			var s: float = LOGO_HOVER_SCALE if on else LOGO_SCALE
			logo.scale = Vector2.ONE * s * FUNKIN_TO_RUBICON


# ─── Selection ────────────────────────────────────────────────────────────

## selectStory 0x3d82680: confirmMenu, an alpha tween over 1.35s linear, the
## cursor mode, and blurX/blurY to BLUR_INTENSITY over 1.45s backOut, while the
## button that was NOT chosen animates away.
func select_story(variant: String) -> void:
	if _is_selecting:
		return
	for btn: Node2D in buttons:
		if String(btn.get_meta(&"name", "")) == variant \
				and bool(btn.get_meta(&"locked", false)):
			_play(SOUND_LOCKED)
			return
	_is_selecting = true
	_play(SOUND_CONFIRM)

	for btn: Node2D in buttons:
		if String(btn.get_meta(&"name", "")) == variant:
			continue
		var away: Tween = create_tween()
		away.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		away.tween_property(btn, "modulate:a", 0.0, 0.45)

	if blur_shader != null:
		var bl: Tween = create_tween().set_parallel(true)
		bl.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bl.tween_property(blur_shader, "shader_parameter/blurX", BLUR_INTENSITY, 1.45)
		bl.tween_property(blur_shader, "shader_parameter/blurY", BLUR_INTENSITY, 1.45)

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(content, "modulate:a", 0.0, 1.35)
	tw.tween_callback(func() -> void:
		# Only the amtake half of the mod is ported, so both buttons lead to the
		# same song for now. The variant is passed on anyway, so the day the
		# other one exists this call site does not have to change.
		_clear_music_filters()
		if _menu_state != null and _menu_state.has_method("start_story"):
			_menu_state.start_story(variant)
		queue_free())


# ─── Close ────────────────────────────────────────────────────────────────

func close_sub_state() -> void:
	if _is_selecting:
		return
	_is_selecting = true
	_play(SOUND_CANCEL)
	_clear_music_filters()

	if blur_shader != null:
		var bl: Tween = create_tween().set_parallel(true)
		bl.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bl.tween_property(blur_shader, "shader_parameter/blurX", 0.0, BLUR_OUT)
		bl.tween_property(blur_shader, "shader_parameter/blurY", 0.0, BLUR_OUT)

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(content, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


# ─── Music filters ────────────────────────────────────────────────────────

## The menu track keeps playing under this screen, muffled. The mod does it with
## OpenAL EFX - a LOWPASS at GAIN 0.8 / GAINHF 0.05 plus a REVERB with
## DECAY_TIME 7.5 - and the port's menu music already goes through a "Music" bus,
## so the two effects go on that bus and come off again when the screen closes.
## They are appended and removed by index rather than by rebuilding the layout,
## so whatever else the bus carries survives.
func _configure_music_filters() -> void:
	var bus: int = AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	var low := AudioEffectLowPassFilter.new()
	low.cutoff_hz = FILTER_CUTOFF
	low.db = AudioEffectFilter.FILTER_12DB
	var reverb := AudioEffectReverb.new()
	reverb.wet = REVERB_WET
	reverb.dry = 1.0
	# Godot's room_size is 0..1 where the mod names seconds of decay; 7.5s is at
	# the top of what the effect can do, so it goes to the top.
	reverb.room_size = minf(1.0, REVERB_DECAY / 8.0)
	AudioServer.add_bus_effect(bus, low)
	AudioServer.add_bus_effect(bus, reverb)
	_bus_effects = 2
	# The GAIN of 0.8 is a flat attenuation of the whole track.
	_bus_volume = AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus, _bus_volume + FILTER_GAIN_DB)


func _clear_music_filters() -> void:
	if _bus_effects <= 0:
		return
	var bus: int = AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	for _i: int in _bus_effects:
		var last: int = AudioServer.get_bus_effect_count(bus) - 1
		if last >= 0:
			AudioServer.remove_bus_effect(bus, last)
	AudioServer.set_bus_volume_db(bus, _bus_volume)
	_bus_effects = 0


## Whatever happens to this node - closed, confirmed, or the whole menu torn
## down under it - the bus goes back to how it was found.
func _exit_tree() -> void:
	_clear_music_filters()


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = load(path) as AudioStream
	audio.bus = &"Master"
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
