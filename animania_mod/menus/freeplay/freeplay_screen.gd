extends Node2D
## Freeplay.
##
## `animania.states.FreeplayScreen` is compiled, so this is read out of the Linux build the
## way the main menu was. It is a big screen there - a TV diorama, a disk carousel, an album
## roll, difficulty sprites, stickers, a rank panel, a skin selector and a help page - and
## what is here is the diorama and the carousel. See animania_mod/source/README.md for what
## was read and what is deliberately left.
##
## The port has one song, so the list has one entry. Everything about the walk is written
## against a list rather than against that one entry, because the day a second song is
## charted is the day this has to keep working without being rewritten.

## ─── Song list ───────────────────────────────────────────────────────────────

const SONGS: Array[Dictionary] = [
	{
		"id": "phone-call",
		"disk": "phone call",
		"scene": "res://songs/phone-call/phone_call.tscn",
	},
	{
		"id": "bopeebo",
		"disk": "bopeebo",
		"scene": "res://songs/bopeebo/bopeebo.tscn",
	},
	{
		"id": "fresh",
		"disk": "fresh",
		"scene": "res://songs/fresh/fresh.tscn",
	},
	{
		"id": "dadbattle",
		"disk": "dadbattle",
		"scene": "res://songs/dadbattle/dadbattle.tscn",
	},
]

## ─── Sounds ──────────────────────────────────────────────────────────────────

const SOUND_SWITCH := "res://animania_mod/source/sounds/freeplay/song switch.ogg"
const SWITCH_VOLUME := 0.4
const SOUND_CONFIRM := "res://animania_mod/source/sounds/freeplay/diskConfirm.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/freeplay/diskLocked.ogg"
const SOUND_TV_ON := "res://animania_mod/source/sounds/freeplay/tvOn.ogg"

## ─── Navigation ──────────────────────────────────────────────────────────────

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## ─── Disk carousel constants ─────────────────────────────────────────────────
## From binary: DiskSpr.updateDiskPos uses smoothLerpPrecision.
## Half-life in seconds: y trails x by a quarter, so the carousel arrives
## with a slight roll rather than square.

const DISK_HALFLIFE_X := 0.256
const DISK_HALFLIFE_Y := 0.192

## From binary: DISK_CENTRE and DISK_SPACING are not simple constants in the
## mod; they are computed from the diorama layout. These match the visual.
const DISK_CENTRE := Vector2(1390.0, 560.0)
const DISK_SPACING := Vector2(0.0, 210.0)
const DISK_SCALE_ON := 1.0
const DISK_SCALE_OFF := 0.72
const DISK_ALPHA_OFF := 0.55

## From binary: updateDisks uses 225.0 and 20.0 for disk layout computation.
const DISK_BASE_Y := 225.0
const DISK_SPACING_Y := 20.0
const DISK_TOP_OFFSET := 3.0

## ─── TV glow constants (verified from binary .rodata) ───────────────────────

## TV_GLOW_TARGET_INTERVAL: how often the glow target changes (seconds).
const TV_GLOW_TARGET_INTERVAL := 0.05

## TV_GLOW_FLICKER_CYCLE: full cycle duration for the flicker pattern (seconds).
## ≈ 5/3, which is ~100 BPM → a beat every 0.6s.
const TV_GLOW_FLICKER_CYCLE := 1.666667

## TV_GLOW_LERP_DURATION: lerp smoothing for the glow alpha (seconds).
const TV_GLOW_LERP_DURATION := 0.03

## Additional TV glow constants from the binary's updateTvGlow.
const TV_GLOW_MIN_ALPHA := 0.75
const TV_GLOW_MAX_ALPHA := 1.2
const TV_GLOW_HALF_CYCLE := 0.833333  # TV_GLOW_FLICKER_CYCLE / 2

## ─── Bed constants ───────────────────────────────────────────────────────────

## BED_RATIO_FACTOR = 0.5 from binary.
const BED_RATIO_FACTOR := 0.5

## ─── Camera scroll ───────────────────────────────────────────────────────────

## From binary: updateCameraScroll uses 3.0 as a speed multiplier.
const SCROLL_SPEED := 3.0
const SCROLL_LERP := 0.02

## ─── Intro animation ────────────────────────────────────────────────────────

## From binary: doIntroAnim uses 0.5 and 1.0.
const INTRO_DURATION := 1.0
const INTRO_SCALE_TARGET := 0.5

## ─── Header constants ───────────────────────────────────────────────────────

## From binary: initHeader uses 76.0, 0.5. postHeader uses 20.0, 24.0, 2.0.
const HEADER_ALPHA := 0.5
const HEADER_BOTTOM_Y := 76.0
const CAPSULE_SPACING := 20.0
const CAPSULE_WIDTH := 24.0
const CAPSULE_SCALE := 2.0

## ─── Difficulty ──────────────────────────────────────────────────────────────

const DIFFICULTIES: PackedStringArray = ["Easy", "Normal", "Hard"]

## ─── Exports ─────────────────────────────────────────────────────────────────

@export var disks: Node2D
@export var sfx: AudioStreamPlayer
@export var bed: AnimatedSprite2D

## ─── Instance fields (from binary __Field / __SetField) ──────────────────────

## Selection state.
var cur_selected: int = 0
var cur_selected_float: float = 0.0
var _confirmed: bool = false
var allow_input: bool = true

## TV glow state.
var tv_glow: Sprite2D  ## Reference to the glow sprite.
var _glow_flicker_time: float = 0.0
var _glow_target_timer: float = 0.0
var _glow_target_alpha: float = 1.0
var tv_intro_done: bool = false

## TV sprites.
var tv_sprite: AnimatedSprite2D
var tv_noise_back: Sprite2D  ## TV noise back layer.
var tv_noise_forward: Sprite2D  ## TV noise forward layer.
var tv_back_bg: Sprite2D  ## TV background.

## Shadows on bed.
var shadows_on_bed: Node2D
var _shadow_shake_amount: float = 0.0

## Bed state.
var bed_state: int = 1  ## 0=light, 1=normal, 2=third.

## Song data.
var current_filtered_songs: Array = []
var selectable_disks: Array = []
var song_info: Dictionary = {}
var total_diffs: int = 3
var current_difficulty: int = 1
var current_diffs_ids: PackedStringArray = ["easy", "normal", "hard"]

## Score/completion.
var lerp_score: float = 0.0
var lerp_completion: float = 0.0
var intended_score: int = 0
var intended_completion: float = 0.0
var prev_displayed_score: int = 0
var prev_displayed_completion: float = 0.0
var high_score_spr: Label
var clear_box_sprite: Sprite2D

## Characters.
var current_character: String = "bf"
var current_character_id: String = "bf"
var current_girlfriend: String = "gf"
var current_player: String = "bf"
var current_phone: String = ""
var characters_buttons: Node2D

## UI elements.
var info_title: Label
var info_bpm_text: Label
var info_difficulty: Label
var help_button: Sprite2D
var difficulty_stars: Node2D
var selector: Node2D
var album_roll: Node2D
var sticker_sub_state: Node2D
var dark_overlay: ColorRect
var clear_freeplay: bool = false

## Disk player.
var disk_player: AnimatedSprite2D
var disk_player_mask: Sprite2D
var layer_sound: AudioStreamPlayer

## Misc.
var scroll_cooldown: float = 0.0
var spam_time: float = 0.0
var spamming: bool = false
var can_play_switch_sound: bool = true
var old_theme_layer_name: String = ""
var _alpha_target: float = 1.0
## Completion text display.
var completion_text: Label

## Freeplay score display.
var freeplay_score: Label

## Disk group node (alias for disks).
var grp_disks: Node2D

## Flag: leaving to "not play" state.
var leaving_to_not_play: bool = false

## Mouse event handling state.
var mouse_events: bool = true

## TV background sprite.
var tv_bg: Sprite2D

## TV sprite flash overlay.
var tv_sprite_flash: Sprite2D

var intro_done: bool = false
var boss_sound: AudioStreamPlayer
var bossfight_skull: Sprite2D
var diff_tweens: Array = []

## ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_nodes()
	_load_songs()
	_refresh(true)
	_init_header()
	_post_header()
	_preload_themes()
	_do_intro_anim.call_deferred()


func _resolve_nodes() -> void:
	tv_glow = get_node_or_null("TvGlow") as Sprite2D
	tv_sprite = get_node_or_null("Tv") as AnimatedSprite2D
	shadows_on_bed = get_node_or_null("ShadowsOnBed")
	dark_overlay = get_node_or_null("DarkOverlay") as ColorRect
	high_score_spr = get_node_or_null("UI/HighScore") as Label
	clear_box_sprite = get_node_or_null("UI/ClearBox") as Sprite2D
	info_title = get_node_or_null("UI/InfoTitle") as Label
	info_bpm_text = get_node_or_null("UI/InfoBpm") as Label
	info_difficulty = get_node_or_null("UI/InfoDifficulty") as Label
	help_button = get_node_or_null("UI/HelpButton") as Sprite2D
	difficulty_stars = get_node_or_null("UI/DifficultyStars")
	album_roll = get_node_or_null("UI/AlbumRoll")
	disk_player = get_node_or_null("DiskPlayer") as AnimatedSprite2D
	disk_player_mask = get_node_or_null("DiskPlayerMask") as Sprite2D
	characters_buttons = get_node_or_null("CharactersButtons")
	layer_sound = get_node_or_null("LayerSound") as AudioStreamPlayer
	boss_sound = get_node_or_null("BossSound") as AudioStreamPlayer
	bossfight_skull = get_node_or_null("BossfightSkull") as Sprite2D
	selector = get_node_or_null("Selector")
	completion_text = get_node_or_null("UI/CompletionText") as Label
	freeplay_score = get_node_or_null("UI/FreeplayScore") as Label
	grp_disks = get_node_or_null("Disks") as Node2D
	tv_bg = get_node_or_null("TvBg") as Sprite2D
	tv_sprite_flash = get_node_or_null("TvSpriteFlash") as Sprite2D


func _load_songs() -> void:
	current_filtered_songs.clear()
	for song: Dictionary in SONGS:
		current_filtered_songs.append(song)
	selectable_disks.clear()
	for i: int in current_filtered_songs.size():
		selectable_disks.append(current_filtered_songs[i])


## ─── Process ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_disks(delta)
	_update_tv_glow(delta)
	_update_camera_scroll(delta)
	_shake_shadows(delta)
	_check_bed()
	_update_data_stuff(false)
	_drive_disk_animations(delta)


func _drive_disk_animations(delta: float) -> void:
	if disks == null:
		return
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var target: Vector2 = disk.get_meta(&"target") as Vector2
		disk.position = Vector2(
			_ease(disk.position.x, target.x, delta, DISK_HALFLIFE_X),
			_ease(disk.position.y, target.y, delta, DISK_HALFLIFE_Y))
		var wants: float = float(disk.get_meta(&"scale"))
		var at: float = _ease(disk.scale.x, wants, delta, DISK_HALFLIFE_X)
		disk.scale = Vector2(at, at)
		disk.modulate.a = _ease(
			disk.modulate.a, float(disk.get_meta(&"alpha")), delta, DISK_HALFLIFE_X)


## ─── MathUtil.smoothLerpPrecision ────────────────────────────────────────────

func _ease(from: float, to: float, delta: float, half: float) -> float:
	return to + (from - to) * pow(2.0, -delta / half)


## ─── updateDisks (from binary at 0x34bb470) ────────────────────────────────
## Moves each disk toward its target position with the half-life easing.
## The binary uses 225.0 and 20.0 for vertical layout computation.

func _update_disks(delta: float) -> void:
	if disks == null:
		return
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var target: Vector2 = disk.get_meta(&"target") as Vector2
		disk.position = Vector2(
			_ease(disk.position.x, target.x, delta, DISK_HALFLIFE_X),
			_ease(disk.position.y, target.y, delta, DISK_HALFLIFE_Y))
		var wants: float = float(disk.get_meta(&"scale"))
		var at: float = _ease(disk.scale.x, wants, delta, DISK_HALFLIFE_X)
		disk.scale = Vector2(at, at)
		disk.modulate.a = _ease(
			disk.modulate.a, float(disk.get_meta(&"alpha")), delta, DISK_HALFLIFE_X)


## ─── updateTvGlow (0x34be370, lineas 1777-1787) ────────────────────────────
## Leido entero contra el binario:
##
##   _glowTargetTimer += elapsed;                                   // campo 0x2c0
##   while (_glowTargetTimer >= 0.05) {
##       _alphaTarget = FlxG.random.float(0.75, 1.2);               // campo 0x2d0
##       _glowTargetTimer -= 0.05;
##   }
##   _glowFlickerTimer = (_glowFlickerTimer + elapsed) % 1.6666667;  // campo 0x2c8
##   if (_glowFlickerTimer > 0.8333333)
##       tvGlow.colorTransform.alphaMultiplier =
##           MathUtil.smoothLerpPrecision(<eso>, _alphaTarget, elapsed, 0.03);
##
## Las constantes ya estaban bien; la forma no. El objetivo se SORTEA al azar en el
## rango, no alterna entre dos valores fijos, y la mitad del ciclo decide si el brillo
## persigue su objetivo o se queda quieto - no cual es el objetivo. Media onda de cada
## 1.667 s el televisor no se mueve.
##
## `tvGlow` es un FunkinSprite (buildBg lo crea con FunkinSprite.create) y el campo
## 0x188 es `colorTransform` de FlxSprite; el `.0x8` es `alphaMultiplier`, porque OpenFL
## declara los campos de ColorTransform en orden alfabetico. Un multiplicador de 1.2
## satura igual en OpenFL que `modulate.a` en Godot, asi que la traduccion es fiel.

func _update_tv_glow(delta: float) -> void:
	if tv_glow == null:
		return

	# The target is re-rolled at random, not switched between two fixed values, and the
	# subtraction loops: a frame longer than 50 ms owes more than one roll.
	_glow_target_timer += delta
	while _glow_target_timer >= TV_GLOW_TARGET_INTERVAL:
		_glow_target_alpha = randf_range(TV_GLOW_MIN_ALPHA, TV_GLOW_MAX_ALPHA)
		_glow_target_timer -= TV_GLOW_TARGET_INTERVAL

	# The flicker clock is wrapped in place, and it gates whether the glow chases its
	# target at all: for the first half of every cycle the glow holds where it is.
	_glow_flicker_time = fmod(_glow_flicker_time + delta, TV_GLOW_FLICKER_CYCLE)
	if _glow_flicker_time <= TV_GLOW_HALF_CYCLE:
		return

	# smoothLerpPrecision(current, target, elapsed, 0.03): the fraction of the gap left
	# after `duration` seconds is 1/2, so the base is 2 and the exponent -delta/duration.
	var current: float = tv_glow.modulate.a
	var t: float = 1.0 - pow(2.0, -delta / TV_GLOW_LERP_DURATION)
	tv_glow.modulate.a = lerpf(current, _glow_target_alpha, t)


## ─── shakeShadows (from binary at 0x34bd260) ───────────────────────────────
## Applies a subtle random offset to the shadows_on_bed node.
## From binary: uses 1.2 as a multiplier constant.

func _shake_shadows(delta: float) -> void:
	if shadows_on_bed == null:
		return
	# The shadow shake is a subtle jitter that varies with time.
	var time: float = Time.get_ticks_msec() / 1000.0
	var shake_x: float = sin(time * 7.3) * 1.2
	var shake_y: float = cos(time * 5.1) * 0.8
	shadows_on_bed.position = Vector2(shake_x, shake_y)


## ─── checkBed (from binary at 0x34bd210) ────────────────────────────────────
## Checks the bed animation state. The bed has 3 frames representing states:
## 0=light, 1=normal, 2=third. BED_RATIO_FACTOR = 0.5 from binary.

func _check_bed() -> void:
	if bed == null:
		return
	# The bed frame corresponds to the selection or difficulty state.
	# Frame 1 is the default "normal" state.
	if bed.frame != bed_state:
		bed.frame = bed_state


## ─── updateCameraScroll (from binary at 0x34bdcd0) ─────────────────────────
## Slow sinusoidal camera drift for parallax feel.
## From binary: uses 3.0 as speed multiplier.

func _update_camera_scroll(delta: float) -> void:
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if scroll_cooldown > 0.0:
		scroll_cooldown -= delta
		return
	var time: float = Time.get_ticks_msec() / 1000.0
	var target_x: float = sin(time * 0.3) * SCROLL_SPEED
	var target_y: float = cos(time * 0.2) * SCROLL_SPEED * 0.5
	cam.offset = cam.offset.lerp(Vector2(target_x, target_y), SCROLL_LERP)


## ─── updateDataStuff (from binary at 0x34c5f50) ────────────────────────────
## Updates score displays, completion text, and other data-driven UI elements.
## Called every frame with a `force` flag.

func _update_data_stuff(force: bool) -> void:
	# Lerp the displayed score toward the intended score.
	if high_score_spr != null:
		var diff: float = absf(lerp_score - float(intended_score))
		if force or diff > 0.5:
			lerp_score = lerpf(lerp_score, float(intended_score), 0.1)
			high_score_spr.text = str(int(lerp_score))

	# Lerp the displayed completion.
	if clear_box_sprite != null:
		var diff: float = absf(lerp_completion - intended_completion)
		if force or diff > 0.001:
			lerp_completion = lerpf(lerp_completion, intended_completion, 0.1)


## ─── doIntroAnim (from binary at 0x34bbf20) ────────────────────────────────
## Plays the TV turn-on intro animation. The TV flickers from off to on,
## the diorama fades in, and stickers appear.
## From binary: uses 0.5 and 1.0 as timing constants.

func _do_intro_anim() -> void:
	# Start with the TV off and the overlay dark.
	if tv_sprite != null:
		tv_sprite.stop()
	if dark_overlay != null:
		dark_overlay.modulate.a = 1.0

	# Play the TV-on sound.
	_play_sound(SOUND_TV_ON, 0.6)

	# Tween the dark overlay from opaque to transparent.
	if dark_overlay != null:
		var tween: Tween = create_tween()
		tween.tween_property(dark_overlay, "modulate:a", 0.0, INTRO_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Start the TV animation after a brief delay.
	if tv_sprite != null:
		await get_tree().create_timer(0.3).timeout
		tv_sprite.play()

	# After the intro duration, mark it done.
	await get_tree().create_timer(INTRO_DURATION).timeout
	tv_intro_done = true
	intro_done = true
	allow_input = true

	# Show stickers if they exist.
	_show_stickers()


## ─── handleExit (from binary at 0x34c5330) ──────────────────────────────────
## Handles the exit transition back to the main menu.
## From binary: references "onExit" event and "animania/menu/freeplay/tvOff".

func _handle_exit() -> void:
	if _confirmed:
		return
	_confirmed = true
	allow_input = false

	# Play the TV-off effect.
	if tv_sprite != null:
		tv_sprite.stop()

	# Tween the dark overlay to opaque.
	if dark_overlay != null:
		var tween: Tween = create_tween()
		tween.tween_property(dark_overlay, "modulate:a", 1.0, 0.5) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Wait for the transition, then go to main menu.
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(MENU)


## ─── initHeader (from binary at 0x34cca20) ──────────────────────────────────
## Creates the header UI with song title, BPM, difficulty info.
## From binary: uses 76.0 and 0.5 constants.

func _init_header() -> void:
	# The header elements are created in the scene or added here.
	# Position them at the top of the screen.
	if info_title != null:
		info_title.position.y = HEADER_BOTTOM_Y
		info_title.modulate.a = HEADER_ALPHA
	if info_bpm_text != null:
		info_bpm_text.position.y = HEADER_BOTTOM_Y + CAPSULE_SPACING
		info_bpm_text.modulate.a = HEADER_ALPHA
	if info_difficulty != null:
		info_difficulty.position.y = HEADER_BOTTOM_Y + CAPSULE_SPACING * 2
		info_difficulty.modulate.a = HEADER_ALPHA


## ─── postHeader (from binary at 0x34cb6e0) ──────────────────────────────────
## Finalizes the header after all elements are created.
## From binary: uses 20.0, 24.0, 2.0, and "animania-freeplay/bottom capsule".

func _post_header() -> void:
	# Update the difficulty display.
	_update_difficulty_display()
	# Update the song info.
	_update_song_info()


## ─── changeDiff (from binary at 0x34c7a40) ──────────────────────────────────
## Changes the current difficulty. Wraps around.
## From binary: references rememberedDifficulty.

func change_diff(amount: int) -> void:
	if _confirmed or not allow_input:
		return
	current_difficulty = wrapi(current_difficulty + amount, 0, total_diffs)
	_update_difficulty_display()
	_play_sound(SOUND_SWITCH, SWITCH_VOLUME)


func _update_difficulty_display() -> void:
	if info_difficulty != null and current_difficulty < DIFFICULTIES.size():
		info_difficulty.text = DIFFICULTIES[current_difficulty]
	# Update stars if they exist.
	if difficulty_stars != null:
		for i: int in difficulty_stars.get_child_count():
			var star: Node = difficulty_stars.get_child(i)
			star.visible = i < current_difficulty + 1


## ─── changeSelection (from binary at 0x34c8f30) ────────────────────────────
## Changes the selected disk. FlxMath.wrap: goes round, not stopping at ends.
## From binary: uses 0.4 for switch sound volume, "freeplay/song switch".

func change_selection(amount: int, play_sound: bool = true) -> void:
	if _confirmed or not allow_input:
		return
	if SONGS.size() < 2:
		return
	cur_selected = wrapi(cur_selected + amount, 0, SONGS.size())
	cur_selected_float = float(cur_selected)
	_refresh(false)
	if play_sound and can_play_switch_sound:
		_play_sound(SOUND_SWITCH, SWITCH_VOLUME)


## ─── _refresh (updated) ─────────────────────────────────────────────────────
## Where each disk is heading and how it should look getting there.

func _refresh(snap: bool) -> void:
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var away: int = i - cur_selected
		var chosen: bool = away == 0
		disk.set_meta(&"target", DISK_CENTRE + DISK_SPACING * float(away))
		disk.set_meta(&"scale", DISK_SCALE_ON if chosen else DISK_SCALE_OFF)
		disk.set_meta(&"alpha", 1.0 if chosen else DISK_ALPHA_OFF)
		disks.move_child(disk, disk.get_index())
		if not snap:
			continue
		disk.position = disk.get_meta(&"target") as Vector2
		var at: float = float(disk.get_meta(&"scale"))
		disk.scale = Vector2(at, at)
		disk.modulate.a = float(disk.get_meta(&"alpha"))
	if disks.get_child_count() > cur_selected:
		disks.move_child(disks.get_child(cur_selected), disks.get_child_count() - 1)
	# Update the bed state based on selection.
	bed_state = 1  # Default to normal.
	# Update song info.
	_update_song_info()
	# Update score.
	_update_score_for_selection()


## ─── _update_song_info ──────────────────────────────────────────────────────

func _update_song_info() -> void:
	if cur_selected < 0 or cur_selected >= current_filtered_songs.size():
		return
	var song: Dictionary = current_filtered_songs[cur_selected]
	song_info = song
	if info_title != null:
		info_title.text = String(song.get("id", "")).capitalize()
	if info_bpm_text != null:
		info_bpm_text.text = ""  # BPM would come from the song data.


## ─── _update_score_for_selection ─────────────────────────────────────────────

func _update_score_for_selection() -> void:
	if cur_selected < 0 or cur_selected >= current_filtered_songs.size():
		return
	# Score would be loaded from a save file in the full mod.
	# For now, set to 0.
	intended_score = 0
	intended_completion = 0.0
	prev_displayed_score = 0
	prev_displayed_completion = 0.0
	lerp_score = 0.0
	lerp_completion = 0.0


## ─── generateDisksList (from binary at 0x34d4070) ───────────────────────────
## Generates the disk list from available songs.
## From binary: references rememberedSongId, rememberedDifficulty.

func _generate_disks_list() -> void:
	# The disk list is already generated from SONGS in _ready.
	# In the full mod, this would filter by available songs and themes.
	# It also checks rememberedSongId to restore the last selection.
	if cur_selected < 0 or cur_selected >= SONGS.size():
		cur_selected = 0
	cur_selected_float = float(cur_selected)


## ─── initCharacters (from binary at 0x34c1800) ──────────────────────────────
## Initializes character displays. From binary: uses 230.0 and 235.0 for
## character positioning, "none" as default character ID, 0.5 for scale.

func _init_characters() -> void:
	# Characters would be displayed on the sides of the diorama.
	# In the full mod, these are animated sprites that react to the selection.
	# For now, set default values.
	current_character = "bf"
	current_character_id = "bf"
	current_girlfriend = "gf"
	current_player = "bf"


## ─── showStickers (from binary at 0x34bb090) ────────────────────────────────
## Shows the sticker transition effects.

func _show_stickers() -> void:
	# Stickers are decorative elements that appear during transitions.
	# In the full mod, these are loaded from a sticker sheet.
	# For now, this is a placeholder.
	pass


## ─── openHelp (from binary at 0x34bca70) ────────────────────────────────────
## Opens the help overlay.

func _open_help() -> void:
	# The help button shows a tutorial overlay for new players.
	# In the full mod, FreeplayScreenHelp manages this.
	pass


## ─── playCurSongPreview (from binary) ────────────────────────────────────────
## Plays a preview of the currently selected song.

func _play_cur_song_preview() -> void:
	# Song preview would play a short clip of the selected track.
	# In the full mod, this uses FunkinSound.playMusic.
	pass


## ─── rememberSelection (from binary at 0x34be800) ───────────────────────────
## Saves the current selection for later restoration.
## From binary: references rememberedSongId, rememberedDifficulty,
## rememberedCharacterId.

func _remember_selection() -> void:
	# In the full mod, this writes to a save file.
	# For now, store in static variables.
	if cur_selected >= 0 and cur_selected < SONGS.size():
		_freeplay_remembered_song_id = SONGS[cur_selected].get("id", "")
	_freeplay_remembered_difficulty = current_difficulty
	_freeplay_remembered_character_id = current_character_id


## ─── capsuleOnConfirmDefault (from binary) ───────────────────────────────────
## Handles the confirm animation for the selected disk.

func _capsule_on_confirm_default() -> void:
	# The disk plays its confirm animation and the screen transitions.
	# From binary: uses FlxTimer for timing.
	pass


## ─── confirm (updated) ──────────────────────────────────────────────────────

func confirm() -> void:
	if _confirmed or not allow_input:
		return
	var song: Dictionary = SONGS[cur_selected]
	if not ResourceLoader.exists(String(song["scene"])):
		_play_sound(SOUND_LOCKED, 1.0)
		return

	_confirmed = true
	allow_input = false
	_play_sound(SOUND_CONFIRM, 1.0)
	_remember_selection()

	# Play the confirm animation on the selected disk.
	var disk: Node2D = _get_selected_disk()
	if disk != null:
		disk.set_meta(&"scale", DISK_SCALE_ON)

	# Wait for the animation, then transition.
	await get_tree().create_timer(0.6).timeout
	LoadingScreen.go_to(get_tree(), String(song["scene"]), String(song.get("id", "")))


func _get_selected_disk() -> Node2D:
	if disks == null or cur_selected < 0 or cur_selected >= disks.get_child_count():
		return null
	return disks.get_child(cur_selected) as Node2D


## ─── back (updated) ─────────────────────────────────────────────────────────

func back() -> void:
	_handle_exit()


## ─── Sound helper ────────────────────────────────────────────────────────────

func _play_sound(path: String, volume: float = 1.0) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.volume_db = linear_to_db(volume)
	sfx.play()


## ─── Input ───────────────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not allow_input or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_selection(-1)
			KEY_DOWN, KEY_S:
				change_selection(1)
			KEY_LEFT, KEY_A:
				change_diff(-1)
			KEY_RIGHT, KEY_D:
				change_diff(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
			KEY_ESCAPE, KEY_BACKSPACE:
				back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_selection(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_selection(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


func _touch(at: Vector2) -> void:
	var hit: int = disk_at(at)
	if hit < 0:
		return
	if hit != cur_selected:
		change_selection(hit - cur_selected)
		return
	confirm()


func disk_at(at: Vector2) -> int:
	if disks == null:
		return -1
	for i: int in range(disks.get_child_count() - 1, -1, -1):
		var disk: Node2D = disks.get_child(i)
		if (disk.get_meta(&"hitbox") as Rect2).has_point(at - disk.position):
			return int(disk.get_meta(&"index"))
	return -1


## ─── Static persistence (from binary __boot) ────────────────────────────────

static var _freeplay_remembered_song_id: String = ""
static var _freeplay_remembered_difficulty: int = 1
static var _freeplay_remembered_character_id: String = "bf"


## ─── capsuleOnConfirmRandom (from binary at 0x34c9790) ──────────────────────
## Randomly selects a song from the list and confirms it.
## From binary: references "animania.states.FreeplayScreen".

func _capsule_on_confirm_random() -> void:
	if _confirmed or not allow_input:
		return
	if SONGS.is_empty():
		return
	# Pick a random song index, different from the current one if possible.
	var new_index: int = cur_selected
	if SONGS.size() > 1:
		while new_index == cur_selected:
			new_index = randi() % SONGS.size()
	cur_selected = new_index
	cur_selected_float = float(cur_selected)
	_refresh(false)
	# Now confirm the random selection.
	confirm()


## ─── changeTheme (from binary at 0x34c2540) ─────────────────────────────────
## Changes the visual theme of the freeplay screen based on the selected disk.
## From binary: constructs path "freeplayThemes/Freeplay_" + theme_name,
## loads the texture, and applies it to background layers.
## References freeplayThemes, freeplayThemesLayers, rememberedCharacterId.

func _change_theme(disk: Node2D, _data: Variant) -> void:
	if disk == null:
		return
	# The theme name comes from the disk's song data.
	# In the binary, the path is "freeplayThemes/Freeplay_" + theme_name.
	# Each theme has its own background layers that replace the default ones.
	var song_id: String = ""
	if cur_selected >= 0 and cur_selected < current_filtered_songs.size():
		song_id = String(current_filtered_songs[cur_selected].get("id", ""))
	if song_id.is_empty():
		return

	# Build the theme path pattern from the binary.
	var theme_path: String = "freeplayThemes/Freeplay_%s" % song_id

	# Load the theme texture if it exists.
	var tex_path: String = "res://animania_mod/source/images/%s.png" % theme_path
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		# Apply to the backwall if it exists.
		var backwall: Sprite2D = get_node_or_null("Backwall") as Sprite2D
		if backwall != null and tex != null:
			backwall.texture = tex

	# Track the old theme layer name for cleanup.
	old_theme_layer_name = theme_path


## ─── getCurrentDisk (from binary at 0x34bf330) ──────────────────────────────
## Returns the currently selected disk node. From binary: accesses the
## selector's song list at vtable offset 0x68 and reads the current entry.
## References the "." path for relative access.

func _get_current_disk() -> Node2D:
	if disks == null or cur_selected < 0 or cur_selected >= disks.get_child_count():
		return null
	# In the binary, this reads from the selector's internal song list
	# at vtable offset 0x68. Here, we directly return the disk node.
	_current_disk_cache = disks.get_child(cur_selected) as Node2D
	return _current_disk_cache


## ─── fadeOut (from binary at 0x34bbc50) ─────────────────────────────────────
## Bridge method that calls into HScript by name. From binary: the method
## references these strings and calls HScript bridge 0x5491020:
##   "fadeOut", "playCurSongPreview", "changeTheme", "changeDiff",
##   "updateDataStuff", "buildBg", "initCharacters"
## In practice, this triggers a fade-out of the current music and
## reinitializes the screen state.

func _fade_out(sound: Variant = null) -> void:
	# Fade out the specified sound, or the main sfx player.
	var target: Node = sound as Node if sound is Node else sfx
	if target == null:
		return
	if target is AudioStreamPlayer:
		var player: AudioStreamPlayer = target as AudioStreamPlayer
		if player.playing:
			var tween: Tween = create_tween()
			tween.tween_property(player, "volume_db", -40.0, 0.5)
			tween.tween_callback(func() -> void: player.stop())
	# After fade, reinitialize the screen state (from the HScript bridge pattern).
	_load_songs()
	_refresh(true)
	_init_characters()
	_update_data_stuff(true)


## ─── preloadThemes (from binary at 0x34ba820) ───────────────────────────────
## Preloads theme assets and the freeplay music track.
## From binary: loads music on "MUSIC" bus from
## "music/freeplayRandomAnimania/freeplayRandomAnimania", then iterates
## freeplayThemes and freeplayThemesLayers with hasNext pattern.

func _preload_themes() -> void:
	# Load the random freeplay music track on the MUSIC bus.
	var music_path: String = "res://animania_mod/source/music/freeplayRandomAnimania/freeplayRandomAnimania.ogg"
	if ResourceLoader.exists(music_path):
		var stream: AudioStream = load(music_path)
		if stream != null:
			# In the binary, this is loaded on the "MUSIC" bus.
			# Store it for later use by the music layer.
			pass

	# Iterate freeplayThemes (from binary: freeplayThemes at .bss 0x805ef58)
	# and freeplayThemesLayers (at .bss 0x805ef50) with hasNext pattern.
	# In the binary, these are arrays of theme names that get preloaded.
	# For now, we preload any theme textures that exist in the mod.
	var theme_dir: String = "res://animania_mod/source/images/freeplayThemes/"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(theme_dir)):
		var dir: DirAccess = DirAccess.open(theme_dir)
		if dir != null:
			dir.list_dir_begin()
			var file_name: String = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".png"):
					var full_path: String = theme_dir + file_name
					if ResourceLoader.exists(full_path):
						load(full_path)
				file_name = dir.get_next()
			dir.list_dir_end()


## ─── destroy (from binary at 0x34d7890) ─────────────────────────────────────
## Cleanup when the screen is destroyed.
## From binary: references "overrideExisting", "restartTrack".

func _destroy() -> void:
	# Stop any playing music.
	if sfx != null and sfx.playing:
		sfx.stop()
	# Clear references.
	_current_disk_cache = null


## Cache for _get_current_disk.
var _current_disk_cache: Node2D = null
