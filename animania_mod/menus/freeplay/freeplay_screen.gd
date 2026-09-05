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

## `bpm` y `title` los pinta updateDataStuff (lineas 1120 y 1122) y salen de
## <id>-metadata.json del mod: el bpm del primer timeChange y `songName`. El campo `disk`
## es el nombre del fichero del disco, que no es lo mismo -"phone call" frente a
## "Phone Call"-, asi que el titulo no se puede sacar de ahi.
##
## `theme` y `layer` son los dos campos que decide changeTheme, y salen tal cual de
## assets/data/songs/<id>/<id>-metadata.json del mod: `freeplayTheme` y `freeplayLayer`.
## No se deducen del personaje rival -eso lo supuse en su dia y era falso: dadbattle tiene
## de rival a `dad-beast` y declara la capa `dad`-. Cuando la cancion no declara ninguno
## valen los respaldos THEME_DEFAULT / LAYER_DEFAULT.
const SONGS: Array[Dictionary] = [
	{
		"id": "phone-call",
		"disk": "phone call",
		"scene": "res://songs/phone-call/phone_call.tscn",
		"layer": "komi",
		"bpm": 152,
		"title": "Phone Call",
		"ratings": {"easy": 4, "normal": 4, "hard": 4},
	},
	{
		"id": "bopeebo",
		"disk": "bopeebo",
		"scene": "res://songs/bopeebo/bopeebo.tscn",
		"layer": "dad",
		"bpm": 110,
		"title": "Bopeebo",
		"ratings": {"easy": 5, "normal": 7, "hard": 9},
	},
	{
		"id": "fresh",
		"disk": "fresh",
		"scene": "res://songs/fresh/fresh.tscn",
		"layer": "dad",
		"bpm": 120,
		"title": "Fresh",
		"ratings": {"easy": 5, "normal": 7, "hard": 8},
	},
	{
		"id": "dadbattle",
		"disk": "dadbattle",
		"scene": "res://songs/dadbattle/dadbattle.tscn",
		"layer": "dad",
		"bpm": 180,
		"title": "DadBattle",
		"ratings": {"easy": 7, "normal": 9, "hard": 11},
	},
]

## ─── Sounds ──────────────────────────────────────────────────────────────────

const SOUND_SWITCH := "res://animania_mod/source/sounds/freeplay/song switch.ogg"
const SWITCH_VOLUME := 0.4
## changeDiff linea 1004: cambiar de dificultad tiene su propio sonido.
const SOUND_DIFF_CHANGE := "res://animania_mod/source/sounds/freeplay/diffChange.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/freeplay/diskConfirm.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/freeplay/diskLocked.ogg"
## handleExit linea 1875. Vive en animania/menu/freeplay/, no con los demas de freeplay.
const SOUND_TV_OFF := "res://animania_mod/source/sounds/freeplay/tvOff.ogg"
const SOUND_TV_ON := "res://animania_mod/source/sounds/freeplay/tvOn.ogg"

## ─── Navigation ──────────────────────────────────────────────────────────────

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## ─── Disk carousel constants ─────────────────────────────────────────────────
## Las que habia aqui -DISK_HALFLIFE_X/Y, DISK_SCALE_ON/OFF, DISK_ALPHA_OFF- se han ido.
## Los dos primeros numeros eran los correctos, 0.256 y 0.192, pero usados como vida media
## de un `to + (from-to)*2^(-dt/half)` cuando el mod usa smoothLerpPrecision, que es otra
## curva. Los otros tres eran invencion entera. Todo eso vive ahora en _drive_disk_animations
## y _apply_disk_pose, leido de DiskSpr.updateDiskPos.

## Lo que sube el disco elegido, de updateDisks linea 806: `disk.targetPos.y -= 3`.
##
## El campo 0x258 estaba marcado aqui como "un hijo del propio DiskSpr, todavia sin
## identificar, asi que no se aplica". Ya esta identificado: el __GetFields de DiskSpr da
## sus miembros en orden -disk, phText, targetPos, lockSpr, songData- y su __Mark da los
## offsets -0x248, 0x250, 0x258, 0x260, 0x268-, y el ultimo cuadra con el songData que
## changeTheme lee en 0x268. Asi que 0x258 es `targetPos` y esto se aplica: el disco
## elegido apunta tres pixeles mas arriba que los demas.
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

## buildBg's three addByIndices calls, in order: cada estado es un solo fotograma.
const BED_STATES := {"light": 0, "normal": 1, "none": 2}

## BED_RATIO_FACTOR = 0.5 from binary.
const BED_RATIO_FACTOR := 0.5

## ─── Intro animation ────────────────────────────────────────────────────────

## From binary: doIntroAnim uses 0.5 and 1.0.
## Los dos FlxTimer de doIntroAnim, y las duraciones de sus dos tweens (lineas 1639, 1642).
const INTRO_FIRST := 0.5
const INTRO_SECOND := 1.0
const INTRO_DARK := 0.65
const INTRO_FLASH := 0.75
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
var tv_noise_forward: AnimatedSprite2D  ## TV noise forward layer.
var tv_back_bg: Sprite2D  ## TV background.

## Shadows on bed.
var shadows_on_bed: Node2D
var _shadow_shake_amount: float = 0.0

## El estado en el que quedo la cama, por nombre. create() abre en 'none'.
var bed_state: String = "none"

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
## highScoreSpr (campo 0x218) es el SPRITE del marcador; el numero es freeplayScore
## (0x1c0). El puerto los tenia cruzados: high_score_spr apuntaba a la etiqueta y
## freeplay_score a un nodo "UI/FreeplayScore" que no existe, asi que el marcador no
## se pintaba nunca y nadie se enteraba porque _resolve_nodes usa get_node_or_null.
## songInfoCapsule (campo 0x260). La construye postHeader y la esconde/enseña
## updateDataStuff con el resto de la cabecera.
var song_info_capsule: AnimatedSprite2D
var high_score_spr: AnimatedSprite2D
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
## spamTimer (campo 0x2e0): cuanto lleva mantenida la tecla desde el ultimo paso.
var spam_timer: float = 0.0
var spamming: bool = false
var can_play_switch_sound: bool = true
## Campos 0x290 y 0x2a8. changeTheme los compara antes de tocar nada: si el nombre no
## cambia, la pista no se recarga.
var old_theme_name: String = ""
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
var bossfight_skull: AnimatedSprite2D
var diff_tweens: Array = []

## ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	_resolve_nodes()
	_load_songs()
	_refresh(true)
	_init_header()
	_post_header()
	_preload_themes()
	# buildBg linea 1337: shakeShadows cuelga del onFrameChange de la nieve de delante.
	var noise := get_node_or_null("TvNoiseForward") as AnimatedSprite2D
	if noise != null:
		noise.frame_changed.connect(_shake_shadows)
	# create() (0x34d6cc0) termina en checkBed('none'), linea 360.
	_check_bed(bed_state)
	_do_intro_anim.call_deferred()


func _resolve_nodes() -> void:
	tv_glow = get_node_or_null("TvGlow") as Sprite2D
	tv_sprite = get_node_or_null("Tv") as AnimatedSprite2D
	shadows_on_bed = get_node_or_null("ShadowsOnBed")
	dark_overlay = get_node_or_null("DarkOverlay") as ColorRect
	song_info_capsule = get_node_or_null("UI/SongInfoCapsule") as AnimatedSprite2D
	high_score_spr = get_node_or_null("UI/HighScoreSpr") as AnimatedSprite2D
	tv_noise_forward = get_node_or_null("TvNoiseForward") as AnimatedSprite2D
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
	_theme_music = get_node_or_null("ThemeMusic") as AudioStreamPlayer
	layer_sound = get_node_or_null("LayerSound") as AudioStreamPlayer
	boss_sound = get_node_or_null("BossSound") as AudioStreamPlayer
	bossfight_skull = get_node_or_null("BossfightSkull") as AnimatedSprite2D
	selector = get_node_or_null("Selector")
	completion_text = get_node_or_null("UI/CompletionText") as Label
	freeplay_score = get_node_or_null("UI/HighScore") as Label
	grp_disks = get_node_or_null("Disks") as Node2D
	tv_bg = get_node_or_null("TvBg") as Sprite2D
	tv_sprite_flash = get_node_or_null("TvSpriteFlash") as Sprite2D


## ─── loadAllAvalaibleSongs (0x34bf580, lineas 422-491) ─────────────────────
##   431  LevelRegistry.instance.listSortedLevelIds()
##   433  LevelRegistry.instance.fetchEntry(<id>)   -> si falla, '[WARN] Could not find
##        level with id (' por consola; lo mismo con SongRegistry y 'song with id ('
##   465  Paths.getPath('music/freeplayThemes/Freeplay_' + <tema>, 'MUSIC') -> cacheSound
##   468  Paths.getPath('music/freeplayThemes/Freeplay_Layer-' + <tema>, 'MUSIC') -> igual
##   479  Paths.music('freeplayThemes/Freeplay_' + <tema>)
##   485  Paths.music('freeplayThemes/Freeplay_Layer-' + <tema>)
##   489  songs.push(...)
##
## La lista NO es un array escrito a mano: sale de los registros de niveles y canciones.
## El SONGS de este puerto es un sustituto suyo y eso es una divergencia consciente.
##
## Lo que si aclara: cada cancion trae un TEMA, y cada tema son DOS pistas -la base
## `Freeplay_<tema>` y una capa `Freeplay_Layer-<tema>`- que se precachean aqui. De ahi
## salen layerSound, oldThemeName y oldThemeLayerName, y de ahi vive changeTheme. En el
## build hay 22 MB de assets/music/freeplayThemes/ y el puerto no reproduce ninguno.
func _load_songs() -> void:
	current_filtered_songs.clear()
	for song: Dictionary in SONGS:
		current_filtered_songs.append(song)
	selectable_disks.clear()
	for i: int in current_filtered_songs.size():
		selectable_disks.append(current_filtered_songs[i])


## ─── Process ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_handle_input(delta)
	_drive_score(delta)
	_update_camera_scroll(delta)
	_update_tv_glow(delta)
	# El acercamiento de cada disco a su sitio; updateDisks solo fija el destino.
	_drive_disk_animations(delta)


## ─── update (0x34d7200, lineas 897-...) ────────────────────────────────────
## Lo que update hace por frame, y son tres llamadas y este trozo, nada mas:
##
##   super.update(elapsed);
##   lerpScore      = MathUtil.smoothLerpPrecision(lerpScore, intendedScore, elapsed, 0.65);
##   lerpCompletion = MathUtil.smoothLerpPrecision(lerpCompletion, intendedCompletion, elapsed, 0.65);
##   if (Math.isNaN(lerpScore)) ...
##   if (Math.isNaN(lerpCompletion)) ...
##   _prevDisplayedScore = Std.int(lerpScore);
##   freeplayScore.updateScore(Std.int(lerpScore));
##   completionText.text = Std.string(Std.int(Math.floor(lerpCompletion * 100)));
##   _prevDisplayedCompletion = <eso>;
##   handleInput(elapsed); updateCameraScroll(elapsed); updateTvGlow(elapsed);
##   callOnScripts('update', [elapsed]);
##
## El puerto no interpolaba nada por frame: lo hacia updateDataStuff, con un factor 0.1
## inventado y un umbral, y ademas llamandolo cada frame cuando el mod solo lo llama
## desde changeDiff y changeSelection.
##
## El texto de completado NO lleva el signo de porcentaje: es solo el entero. El `%` es
## arte, el mismo `CLEARED %` que se ve en pantalla.

## El `duration` de los dos smoothLerpPrecision de update.
const SCORE_LERP := 0.65


## ─── handleInput (0x34d25e0, lineas 1802-1867) ─────────────────────────────
## Los ejes del puerto estaban cambiados. El binario es claro:
##
##   1828  if (UI_LEFT.checkPressed() || UI_RIGHT.checkPressed()) {
##   1835        if (spamming && spamTimer >= 0.07)                  // repetido
##   1844        else if (!spamming)                                 // primera pulsacion
##                   changeSelection(UI_LEFT.checkPressed() ? -1 : 1);
##         } else { spamming = false; spamTimer = 0; }
##   1854  UI_UP.checkJustPressed() / UI_DOWN.checkJustPressed()
##   1856      -> changeDiff(...)
##   1861  ... -> handleExit()
##
## IZQUIERDA y DERECHA cambian de CANCION; ARRIBA y ABAJO cambian de DIFICULTAD. El
## puerto los tenia al reves, lo cual encajaba con su carrusel vertical inventado: con la
## fila horizontal que updateDisks realmente dibuja, izquierda y derecha es lo natural.
##
## Y hay repetido al mantener, cada 0.07 s, con la primera pulsacion aparte. Por eventos
## eso queda en manos del repetido del sistema operativo, que es otro ritmo.
##
## Las tres condiciones que faltaban se leen por un hueco de VTABLE, no por una llamada
## directa, y por eso un rastreo por nombre no las veia: FunkinAction.check() es virtual
## (hueco 0x100 de su vtable) mientras checkPressed y checkJustPressed son directas.
##
##   1807  ACCEPT.check()        -> la confirmacion
##   1859  BACK.check()          -> handleExit()            (1861)
##   1864  DEBUG_CHART.check()   -> el editor de charts de la cancion elegida
##
## DEBUG_CHART es la accion 0x160 de Controls, sacada de su __GetFields junto al resto de
## la tabla. Es un atajo de desarrollo y no se portea, como el resto del menu de depuracion.

## El umbral de spamTimer con el que se repite la seleccion.
const INPUT_REPEAT := 0.07

const KEYS_PREV := [KEY_LEFT, KEY_A]
const KEYS_NEXT := [KEY_RIGHT, KEY_D]


func _any_held(keys: Array) -> bool:
	for key: int in keys:
		if Input.is_key_pressed(key as Key):
			return true
	return false


func _handle_input(delta: float) -> void:
	if _confirmed or not allow_input:
		return

	var prev: bool = _any_held(KEYS_PREV)
	if prev or _any_held(KEYS_NEXT):
		var step: int = -1 if prev else 1
		if not spamming:
			change_selection(step)
			spamming = true
			spam_timer = 0.0
		else:
			spam_timer += delta
			if spam_timer >= INPUT_REPEAT:
				change_selection(step)
				spam_timer = 0.0
	else:
		spamming = false
		spam_timer = 0.0


func _drive_score(delta: float) -> void:
	lerp_score = _smooth_lerp(lerp_score, float(intended_score), delta, SCORE_LERP)
	lerp_completion = _smooth_lerp(lerp_completion, intended_completion, delta, SCORE_LERP)
	if is_nan(lerp_score):
		lerp_score = float(intended_score)
	if is_nan(lerp_completion):
		lerp_completion = intended_completion
	prev_displayed_score = int(lerp_score)
	if freeplay_score != null:
		freeplay_score.text = str(prev_displayed_score)
	_show_score_digits(prev_displayed_score)
	prev_displayed_completion = floor(lerp_completion * 100.0)
	if completion_text != null:
		completion_text.text = str(int(prev_displayed_completion))


## MathUtil.smoothLerpPrecision (0x188bb20). Interpola de forma que a los `duration`
## segundos queda a `precision` del objetivo, asi que el factor por frame es
## 1 - precision^(dt/duration). El puerto tenia en su lugar un lerp de factor fijo.
func _smooth_lerp(base: float, target: float, dt: float, duration: float,
		precision: float = 0.01) -> float:
	if absf(base - target) < 1e-7 or duration <= 0.0:
		return target
	return lerpf(base, target, 1.0 - pow(precision, dt / duration))


## ─── DiskSpr.updateDiskPos (0x200bf70, lineas 150-168) ─────────────────────
## Esto estaba inventado de cabo a rabo: una interpolacion por vida media con dos
## constantes puestas a ojo, una escala de 1.0 / 0.72 y un alfa de 0.55. Nada de eso esta
## en el mod. DiskSpr.update (linea 141) llama a updateDiskPos con el elapsed y sin
## ninguna guarda, y lo que hace es:
##
##   150  x = MathUtil.smoothLerpPrecision(x, targetPos.x, elapsed, 0.256)
##   153  y = MathUtil.smoothLerpPrecision(y, targetPos.y, elapsed, 0.192)
##   161  angle = (x + 20) / 225 * -5.5                  // hueco 0x248 = set_angle
##   165  _reqScale = 1 - abs(angle) * 0.035             // campo 0x288
##   167  if (scale.x != _reqScale) scale.set(_reqScale, _reqScale)
##   168  color = FlxColor(255*_reqScale, 255*_reqScale, 255*_reqScale, 255)
##
## Tres cosas que solo se ven leyendolo:
##
## El (x + 20) / 225 no es un numero magico: 225 es el paso entre discos y -20 su
## desplazamiento, o sea que ese cociente ES la distancia en pasos hasta el elegido. Y se
## calcula sobre la x YA interpolada, no sobre el destino, asi que el giro, el tamaño y el
## color siguen a la animacion en vez de saltar con ella.
##
## El disco lejano no baja de ALFA: baja de COLOR. Los tres canales van a 255*escala con
## el alfa fijo en 255, que es un gris, no una transparencia. Se nota: sobre el fondo
## claro de la cama un gris y un alfa no se parecen en nada.
##
## Y el `andpd` de 0x200c0ef es la mascara que quita el bit de signo: es abs(), asi que el
## disco encoge igual a un lado que al otro.
const DISK_LERP_X := 0.256
const DISK_LERP_Y := 0.192
## Grados por paso, linea 161. Negativo: el carrusel gira al contrario que su avance.
const DISK_ANGLE_PER_STEP := -5.5
## Cuanto encoge por grado, linea 165.
const DISK_SCALE_PER_DEGREE := 0.035


func _drive_disk_animations(delta: float) -> void:
	if disks == null:
		return
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var target: Vector2 = disk.get_meta(&"target") as Vector2
		disk.position = Vector2(
			_smooth_lerp(disk.position.x, target.x, delta, DISK_LERP_X),
			_smooth_lerp(disk.position.y, target.y, delta, DISK_LERP_Y))
		_apply_disk_pose(disk)


## Las lineas 161-168: todo sale de la x actual, asi que vale igual para el fotograma a
## fotograma y para el salto de _refresh.
func _apply_disk_pose(disk: Node2D) -> void:
	# La x del mod, que es la del puerto sin el factor de escala de pantalla.
	var step: float = (disk.position.x / FUNKIN_TO_RUBICON - DISK_OFFSET_X) / DISK_STEP_X
	var angle: float = step * DISK_ANGLE_PER_STEP
	disk.rotation = deg_to_rad(angle)
	var at: float = 1.0 - absf(angle) * DISK_SCALE_PER_DEGREE
	disk.scale = Vector2(at, at)
	# Linea 168: gris, no alfa. Std.int() trunca y el resultado se recorta a 0..255.
	var grey: float = clampf(float(int(255.0 * at)), 0.0, 255.0) / 255.0
	disk.modulate = Color(grey, grey, grey, 1.0)




## ─── updateDisks (0x34bb470, lineas 798-807) ───────────────────────────────
## El parametro NO es un delta: es la seleccion. Por eso lo llama changeSelection y no
## update, y por eso la resta de abajo tiene sentido.
##
##   for (disk in grpDisks) {                                  // 799
##       disk.x = (disk.ID - sel) * 225 - 20;                  // 800
##       disk.y = DiskSpr.intendedY(disk.ID - sel);            // 801
##       disk.zIndex = 5;                                      // 802
##       disk.selected = (sel == disk.ID);                     // 803
##       if (sel == disk.ID) {                                 // 804
##           disk.<0x258>.y -= 3;                              // 806
##           disk.zIndex = 10;                                 // 807
##       }
##   }
##
## y DiskSpr.intendedY(d) (0x200c7a0) es (d * 1.5)^2 * 6 + 520: una parabola muy suave.
## O sea una FILA por la parte baja de la pantalla -el elegido en (-20, 520), el
## siguiente en (205, 533.5), el de mas alla en (430, 574)- no la columna vertical en
## (1390, 560) que tenia el puerto. Aquella era inventada, y el comentario que decia
## que "no son constantes simples en el binario" se contradecia con las dos constantes
## que el propio puerto ya tenia leidas: 225 y 20.

const DISK_STEP_X := 225.0
const DISK_OFFSET_X := -20.0
const DISK_CURVE_X := 1.5
const DISK_CURVE_Y := 6.0
const DISK_BASE_Y := 520.0
## En el mod son 5 y 10, pero eso es el zIndex DENTRO de grpDisks, que solo decide el
## orden entre discos; el grupo entero ocupa el 19. En Godot el z de un hijo se suma al
## del padre, asi que aqui van 0 y 1: mismo orden relativo, mismo hueco para el grupo.
const DISK_Z := 0
const DISK_Z_SELECTED := 1


## DiskSpr.intendedY (0x200c7a0), con `d` en pasos de seleccion.
func _disk_y(away: float) -> float:
	var t: float = away * DISK_CURVE_X
	return t * t * DISK_CURVE_Y + DISK_BASE_Y


func _update_disks(sel: float) -> void:
	if disks == null:
		return
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		# disk.ID, no la posicion en el arbol: _refresh reordenaba los hijos para poner el
		# elegido delante, asi que get_child(i) deja de ser el disco i en cuanto se mueve
		# la seleccion. En el mod el orden lo decide el zIndex y el ID no se toca.
		var away: float = float(int(disk.get_meta(&"index", i))) - sel
		var chosen: bool = is_zero_approx(away)
		# Linea 806: el elegido apunta tres pixeles mas arriba. Ver DISK_TOP_OFFSET.
		var y: float = _disk_y(away) - (DISK_TOP_OFFSET if chosen else 0.0)
		disk.set_meta(&"target", Vector2(
			away * DISK_STEP_X + DISK_OFFSET_X, y) * FUNKIN_TO_RUBICON)
		disk.z_index = DISK_Z_SELECTED if chosen else DISK_Z


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


## ─── shakeShadows (0x34bd260, lineas 1702-1709) ────────────────────────────
## Leido entero:
##
##   var p = FlxPoint.get(FlxG.width / 1.2, FlxG.height * 1.2);
##   mat.identity();
##   mat.translate(-p.x, -p.y);
##   mat.scale(FlxG.random.float(1.1, 1.11), FlxG.random.float(1.1, 1.11));
##   mat.translate(p.x, p.y);
##   p.put();
##
## Es un ESCALADO aleatorio alrededor de un pivote, no una traslacion: `mat` es la matriz
## de shadowsOnBed, que buildBg (linea 1216) crea como un FlxLayerGroup de
## funkin.graphics.framebuffer, no como un sprite. El puerto tenia en su lugar un
## sin/cos inventado que ademas corria en cada frame.
##
## Y no corre por frame: buildBg lo engancha (linea 1337) al onFrameChange de la
## animacion de tvNoiseForward, asi que se re-sortea cuando avanza la nieve del
## televisor, a 24 por segundo pero atado a ella.
##
## Lo que sigue faltando: el grupo esta VACIO. El arte de las sombras viaja con
## tvNoiseBack y aun no se ha separado, asi que esto es correcto y no se ve.

## FlxG.width / FlxG.height, en pixeles del puerto.
const SCREEN := Vector2(1920.0, 1080.0)
## 1280x720 del mod -> 1920x1080 del puerto.
const FUNKIN_TO_RUBICON := 1.5
const SHADOW_SCALE := Vector2(1.1, 1.11)
const SHADOW_PIVOT_X_DIVISOR := 1.2
const SHADOW_PIVOT_Y_FACTOR := 1.2


func _shake_shadows() -> void:
	if shadows_on_bed == null:
		return
	var pivot := Vector2(
		SCREEN.x / SHADOW_PIVOT_X_DIVISOR, SCREEN.y * SHADOW_PIVOT_Y_FACTOR)
	var scale := Vector2(
		randf_range(SHADOW_SCALE.x, SHADOW_SCALE.y),
		randf_range(SHADOW_SCALE.x, SHADOW_SCALE.y))
	# translate(p) * scale(s) * translate(-p), que en un Node2D es esto.
	shadows_on_bed.scale = scale
	shadows_on_bed.position = pivot - pivot * scale


## ─── checkBed (0x34bcac0, lineas 1696-1697) ─────────────────────────────────
## El metodo entero son dos lineas:
##
##   bgBed.animation.play(name, false);
##   callOnScripts('onUpdateBed', [name]);
##
## No comprueba nada por frame: es un cambio de animacion por nombre. buildBg le
## registra tres animaciones de UN solo fotograma con addByIndices - `light` -> [0],
## `normal` -> [1], `none` -> [2] - y los tres nombres salen del binario, no de una
## suposicion (el puerto llamaba `third` al tercero).
##
## Quien lo llama: create() con 'none' (asi abre la pantalla), la rama de
## playCurSongPreview en la que no hay disco -tambien con 'none', junto a
## changeCharacter('none') sobre el jugador y la novia- y un cierre que initCharacters
## (linea 1408) cuelga del personaje, que reenvia el nombre que le llegue.
##
## Antes esto corria en _process comparando bed.frame con una variable inventada.

func _check_bed(state: String) -> void:
	if bed == null:
		return
	if not BED_STATES.has(state):
		return
	bed.frame = BED_STATES[state]


## ─── updateCameraScroll (0x34bdcd0, lineas 1713-1718) ──────────────────────
## Es paralaje de RATON, no una deriva sola:
##
##   var t = elapsed * 3;                                                     // 1713
##   FlxG.camera.scroll.x += FlxMath.remapToRange(FlxG.mouse.x, 0, FlxG.width,  3, -6) * t;
##   FlxG.camera.scroll.y += FlxMath.remapToRange(FlxG.mouse.y, 0, FlxG.height, 1, -1) * t;
##
## El puerto tenia en su lugar un sin/cos del reloj, o sea una camara que se mueve sola
## cuando en el mod no se mueve nada si el raton esta quieto. Y llevaba un scroll_cooldown
## que aqui no pinta nada: ese campo es de handleInput, para el repetido de la seleccion.
##
## En un telefono no hay puntero, asi que esto queda inerte igual que el paralaje del menu
## principal. Se portea con la formula real -no con una invencion que si se mueve- para
## que en escritorio haga lo que hace el mod y en Android, correctamente, nada.

## Los cuatro extremos de los dos remapToRange, y el multiplicador del tiempo.
const SCROLL_RANGE_X := Vector2(3.0, -6.0)
const SCROLL_RANGE_Y := Vector2(1.0, -1.0)
const SCROLL_SPEED := 3.0


func _update_camera_scroll(delta: float) -> void:
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var mouse: Vector2 = cam.get_local_mouse_position() + cam.position
	var step: float = delta * SCROLL_SPEED
	cam.offset += Vector2(
		remap(mouse.x, 0.0, SCREEN.x, SCROLL_RANGE_X.x, SCROLL_RANGE_X.y),
		remap(mouse.y, 0.0, SCREEN.y, SCROLL_RANGE_Y.x, SCROLL_RANGE_Y.y)) * step


## ─── updateDataStuff (0x34c5f50, lineas 1081-1176) ─────────────────────────
## NO corre por frame: el grafo de llamadas del binario lo saca de changeDiff y de
## changeSelection y de ningun otro sitio. Lo que hacia aqui -interpolar el marcador con
## un factor 0.1 y un umbral- era de update, y ya esta en _drive_score.
##
## Ya leido. Son 6883 bytes con dos ramas, la de "hay cancion" y la de "no la hay":
##
##   1088  songData.currentDifficulty = currentDifficulty
##   1089  songData.updateValues(currentCharacter)
##   1090  <guardado>.getSongScore(<cancion>, currentDifficulty)
##   1091  score = <eso>.score
##   1092  el porcentaje sale de tallies.good, tallies.sick y tallies.totalNotes
##   1097  albumRoll.albumId = ...        1098  albumRoll.skipIntro()
##   1100  FlxTween.cancelTweensOf(tvNoiseForward, ['alpha'])
##   1101  tvNoiseForward.alpha = 0.7
##   1102  FlxTween.tween(tvNoiseForward, {alpha: 0.45}, 0.25, {ease: sineInOut})
##   1104  FlxTween.cancelTweensOf(infoTitleText, ...)
##   1105  infoTitleText.<amount> = 2
##   1106  FlxTween.tween(infoTitleText, {amount: 0.1}, 0.25, {ease: sineInOut})
##   1113  difficultyStars.difficulty = ...      1114  dotsGrp.setDots(currentDiffsIds)
##   1115  songInfoCapsule.curDiff = currentDifficulty
##   1117  alpha 1 sobre los siete de la cabecera    1118  visible = true
##   1120  infoBpmText.text  = 'BPM: ' + <bpm>
##   1122  infoTitleText.text = <titulo>
##   1125  infoDiffText.text = 'DIF: ' + <dificultad>
##   1131  FlxTween.cancelTweensOf(bossfightSkull, [...])
##   1132  FlxTween.tween(bossfightSkull, {alpha: ...}, 0.1, {ease: backOut})
##   1133  bossfightSkull.animation.play('y')
##   1137  bossSound ...        1142-1148  si no suena: pause, y alpha del craneo a 0
##   1148  'N/A'
##   -- la rama sin cancion --
##   1165  dotsGrp.setDots(...)   1166  curDiff   1169 albumId   1170 difficulty
##   1172  alpha 0.0001 sobre los mismos siete      1173  visible = false
##   1176  dispatch('onUpdateDataStuff')
##
## Los siete de las lineas 1117/1172 son los mismos que postHeader deja en 0.0001 al
## construir: infoBpmText, infoTitleText, infoDiffText, highScoreSpr, clearBoxSprite,
## freeplayScore y completionText. O sea que la cabecera no se oculta con visible, se
## queda en un alfa practicamente cero y updateDataStuff la sube a 1.
##
## `?` Sin portear, y dicho: la puntuacion y el porcentaje. Salen de getSongScore sobre
## un guardado que este proyecto no tiene -el menu de historia tambien deja su marcador
## a 0-, asi que la formula queda escrita arriba y los valores se quedan en cero.
## `?` Tampoco se portea el tween de la linea 1106: `amount` es una propiedad del
## FlxFixedText del mod -un efecto sobre el texto-, y aqui las etiquetas son Labels de
## Godot y no tienen nada equivalente.
const NOISE_KICK := 0.7
const NOISE_REST := 0.45
const NOISE_SETTLE := 0.25
const HEADER_HIDDEN := 0.0001
const SKULL_FADE := 0.1
## FreeplayDots: el elegido a alfa 1 y color entero, los demas a 0.9 y getDarkened(0.45),
## que en Flixel es multiplicar el RGB por (1 - 0.45). Los colores son diffColors, del
## __boot de la clase; los mismos que usa el builder.
const DIFF_COLORS := {
	"easy": Color8(0xc5, 0xfe, 0x59),
	"normal": Color8(0xfe, 0xe5, 0x43),
	"hard": Color8(0xfe, 0x24, 0x66),
	"legacy": Color8(0x7f, 0x6a, 0xf7),
	"standart": Color8(0x6c, 0xe7, 0xc3),
}
const DOT_DARKEN := 1.0 - 0.45
const DOT_DIM_ALPHA := 0.9


func _update_data_stuff(_force: bool) -> void:
	var has_song: bool = cur_selected >= 0 and cur_selected < current_filtered_songs.size()

	# Lineas 1117/1118 y 1172/1173: los siete de la cabecera a 1 o a 0.0001.
	var alpha: float = 1.0 if has_song else HEADER_HIDDEN
	for node: CanvasItem in [info_bpm_text, info_title, info_difficulty, high_score_spr,
			clear_box_sprite, freeplay_score, completion_text]:
		if node != null:
			node.modulate.a = alpha
			node.visible = has_song

	if not has_song:
		return

	_update_score_for_selection()

	var song: Dictionary = current_filtered_songs[cur_selected]
	# Lineas 1120 y 1125. El titulo (1122) va sin prefijo.
	if info_title != null:
		info_title.text = String(song.get("title", song.get("id", "")))
	if info_bpm_text != null:
		info_bpm_text.text = "BPM: %s" % str(song.get("bpm", ""))
	# Linea 1125. En el mod `currentDifficulty` es una cadena; aqui es el indice, asi que
	# el nombre sale de la tabla.
	if info_difficulty != null:
		var name: String = DIFFICULTIES[current_difficulty] \
			if current_difficulty >= 0 and current_difficulty < DIFFICULTIES.size() \
			else str(current_difficulty)
		info_difficulty.text = "DIF: %s" % name

	# Lineas 1100-1102: el ruido del televisor pega un golpe a 0.7 y se asienta en 0.45.
	# Es lo que se ve al cambiar de cancion.
	if tv_noise_forward != null:
		var kick: Tween = create_tween()
		tv_noise_forward.modulate.a = NOISE_KICK
		kick.tween_property(tv_noise_forward, "modulate:a", NOISE_REST, NOISE_SETTLE) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# El gancho del script del mod. Ver _on_change_selection.
	_on_change_selection(song)

	# Linea 1113: difficultyStars.difficulty. Ver _update_stars.
	_update_stars()

	# Lineas 1114-1115: los puntos de dificultad. setDots deja visibles solo los ids que
	# la cancion trae, y set_curDiff enciende el de la dificultad actual.
	_set_dots()

	# El craneo de jefe. La rama la decide un bool en el offset 0x40 del FreeplaySongData
	# -`cmpb $0x0,0x40(%rax)` en la linea 1129- que el __GetFields de esa clase nombra
	# `isBoss`, quinto de su lista.
	#
	#   1131  FlxTween.cancelTweensOf(bossfightSkull, [...])
	#   1132  FlxTween.tween(bossfightSkull, {alpha: ...}, 0.1, {ease: backOut})
	#   1133  bossfightSkull.animation.play(...)
	#   1137  bossSound ...
	#   1142-1148  si no: pause, cancelTweensOf y el alfa del craneo abajo
	#
	# `?` Quien pone `isBoss` a true no lo he encontrado: ningun metadata de cancion ni
	# ningun JSON de nivel del mod declara nada de jefe, y el constructor de
	# FreeplaySongData escribe ese byte a 0 (`movb $0x0,0x40(%rbx)`). No he descartado
	# todos los escritores posibles, asi que lo dejo dicho asi y no como "no lo pone
	# nadie". Con `is_boss` a false en las cuatro canciones, hoy solo corre la rama de
	# apagarlo, que es lo mismo que hace el mod.
	if bossfight_skull != null:
		var boss: bool = bool(song.get("is_boss", false))
		var fade: Tween = create_tween()
		fade.tween_property(bossfight_skull, "modulate:a", 1.0 if boss else 0.0,
			SKULL_FADE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		if boss:
			bossfight_skull.play()
			if boss_sound != null and not boss_sound.playing:
				boss_sound.play()
		elif boss_sound != null and boss_sound.playing:
			# Linea 1146: pause, no stop.
			boss_sound.stream_paused = true


## ─── onChangeSelection, de data/scripts/states/FreeplayScreen.script ───────
## Esta pantalla NO es solo la clase compilada: el mod le cuelga un HScript, y ahi estan
## dos cosas que el binario no cuenta.
##
## La primera corrige lo que documente al portear initCharacters. Yo escribi que el
## telefono se crea invisible y que "quien lo enseñe esta fuera de esta pantalla". Estaba
## fuera, si: en `createPost` del script, que crea un SEGUNDO telefono, distinto del
## currentPhone del binario -otro sitio, (FlxG.width - 510, 300) contra
## (FlxG.width - 517.6, 265.9), y zIndex 5 contra 6- con la misma animacion pero SIN
## bucle. El currentPhone de initCharacters sigue sin que nadie lo enseñe; el que se ve
## es este. Y se ve con phone-call, que es una de las cuatro canciones del puerto, asi
## que esto si se alcanza.
##
## La segunda es winter-horrorland: pausa las animaciones de los dos personajes, enseña
## sus `censureBlock` y sube un shader Glitch2 a 0.0125 en 1.5 s con circOut. Nada de eso
## se portea porque esa cancion no esta aqui, y el shader tampoco.
##
## `?` En el mod el telefono NO aparece al elegir la cancion: aparece dentro de
## `currentPlayer.onPopCallback`, o sea cuando el personaje hace su animacion de salto, y
## ese callback tambien llama a checkBed("none"). El callback es del subsistema de
## personajes, que no esta porteado, asi que aqui se enseña al elegir. Es una diferencia
## de MOMENTO, no de contenido, y va dicha.
func _on_change_selection(song: Dictionary) -> void:
	# El script se sale entero si el intro no ha terminado.
	if not tv_intro_done:
		return
	var phone := get_node_or_null("ShadowsOnBed/PhoneCallPhone") as AnimatedSprite2D
	if phone == null:
		return
	if String(song.get("id", "")) == "phone-call":
		phone.visible = true
		phone.frame = 0
		phone.play()
		_check_bed("none")
	else:
		phone.visible = false


## setDots (0x4092250, lineas 64-80) y set_curDiff (0x4091910, 25-29) juntos: cual se ve
## y cual esta encendido. En el mod son dos metodos de FreeplayDots porque el grupo es una
## clase; aqui los puntos son hijos de un Node2D y esto es todo lo que hacen.
func _set_dots() -> void:
	var dots := get_node_or_null("UI/DotsGrp") as Node2D
	if dots == null:
		return
	var current: String = ""
	if current_difficulty >= 0 and current_difficulty < current_diffs_ids.size():
		current = current_diffs_ids[current_difficulty]
	for dot: Node in dots.get_children():
		var sprite := dot as Sprite2D
		if sprite == null:
			continue
		var id: String = String(sprite.get_meta(&"diff", ""))
		# Linea 66: el que la cancion no ofrece se apaga del todo.
		sprite.visible = current_diffs_ids.has(id)
		var base: Color = DIFF_COLORS.get(id, Color.WHITE)
		sprite.modulate = Color(base, 1.0) if id == current \
			else Color(base * DOT_DARKEN, DOT_DIM_ALPHA)


## ─── doIntroAnim (from binary at 0x34bbf20) ────────────────────────────────
## Plays the TV turn-on intro animation. The TV flickers from off to on,
## the diorama fades in, and stickers appear.
## From binary: uses 0.5 and 1.0 as timing constants.

func _do_intro_anim() -> void:
	# doIntroAnim (0x34bbf20) son dos lineas: dos FlxTimer, uno a 0.5 y otro a 1.
	get_tree().create_timer(INTRO_FIRST).timeout.connect(_intro_switch_on)
	get_tree().create_timer(INTRO_SECOND).timeout.connect(_intro_light_up)


## El cierre del temporizador de 0.5 s (0x34b8df0, lineas 1601-1607).
##
##   diskPlayer.visible = true;                            // 1601
##   diskPlayer.animation.play('y');                       // 1602
##   tvSprite.visible = true;                              // 1603
##   tvSprite.animation.onFrameChange.add(...);            // 1605
##   tvSprite.animation.onFinish.addOnce(...);             // 1606
##   diskPlayer.animation.onFinish.addOnce(...);           // 1607
##
## Los tres callbacks encadenan el resto del encendido y no se han leido; lo que si se
## ve es que el aparato y el televisor aparecen aqui, medio segundo antes que nada mas.
func _intro_switch_on() -> void:
	var vcr := get_node_or_null("Player") as AnimatedSprite2D
	if vcr != null:
		vcr.visible = true
		vcr.play(&"player")
	if tv_sprite != null:
		tv_sprite.visible = true


## El cierre del temporizador de 1 s (0x34ca150, lineas 1612-1648).
##
##   dotsGrp/selectorsGroup/tvGlow/tvNoiseBack/tvNoiseForward .visible = true;   // 1612
##   dotsGrp.setDots([...]); dotsGrp.curDiff = 'hard';                           // 1613-1614
##   <flash>.color = 0xFFFFFFFF; <flash>.alpha = 1;                              // 1615-1616
##   FlxTween.tween(<colorTransform>, {...}, 0.291667, {ease: quadIn});          // 1619, 1630
##   FlxTween.tween(darkOverlay, {alpha: 0}, 0.65, {ease: circOut});             // 1639
##   albumRoll.playIntro();                                                      // 1640
##   FlxTween.tween(tvSpriteFlash, {...}, 0.75, {ease: circOut});                // 1642
##   FlxG.sound.playOnce(...);                                                   // 1643
##   shadowsOnBed.visible = true;                                                // 1645
##   freeplayScore.updateScore(0);                                               // 1646
##   changeSelection(...);                                                       // 1648
##
## El destino del tween de darkOverlay esta comprobado, no supuesto: el Anon de la linea
## 1639 lleva nombre de 5 letras -'alpha'-, valor 0 y tipo 3 (entero).
func _intro_light_up() -> void:
	# Linea 1612: dotsGrp va en esta lista, es de los primeros que se encienden.
	for name: String in ["TvGlow", "TvNoiseBack", "TvNoiseForward", "PlayerLayer",
			"Disks", "ShadowsOnBed", "UI/DotsGrp"]:
		var node := get_node_or_null(name) as CanvasItem
		if node != null:
			node.visible = true

	# El destello blanco: se enciende opaco y se apaga en 0.75 s.
	if tv_sprite_flash != null:
		tv_sprite_flash.visible = true
		tv_sprite_flash.modulate = Color(1.0, 1.0, 1.0, 1.0)
		create_tween().tween_property(tv_sprite_flash, "modulate:a", 0.0, INTRO_FLASH) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CIRC)

	if dark_overlay != null:
		create_tween().tween_property(dark_overlay, "modulate:a", 0.0, INTRO_DARK) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CIRC)

	# El sonido va aqui, no al abrir la pantalla: la linea 1643 lo toca dentro de este
	# temporizador. Que sea tvOn es lo unico que no esta leido del binario.
	_play_sound(SOUND_TV_ON, 0.6)

	intended_score = 0
	lerp_score = 0.0
	change_selection(0, false)
	# Linea 1651: playCurSongPreview otra vez, aparte del que ya lleva changeSelection
	# dentro. No es redundante: en 1648 `allow_input` todavia es false y changeSelection se
	# sale por su guarda, asi que esta es la llamada que arranca el tema del primer disco.
	_play_cur_song_preview()
	tv_intro_done = true
	intro_done = true
	allow_input = true
	_show_stickers()


## ─── handleExit (from binary at 0x34c5330) ──────────────────────────────────
## Handles the exit transition back to the main menu.
## From binary: references "onExit" event and "animania/menu/freeplay/tvOff".

## ─── handleExit (0x34c5330, lineas 1873-1937) ──────────────────────────────
##   1873  callOnScripts('onExit')
##   1875  FunkinSound.playOnce(Paths.sound('animania/menu/freeplay/tvOff'))
##   1880  shadowsOnBed.visible = false
##   1882  FlxTween.cancelTweensOf(bossfightSkull, [...]);  1883 su alpha
##   1890  tvGlow / tvNoiseBack / tvNoiseForward .visible = false
##   1891  el alfa de songInfoCapsule, los tres textos de info, highScoreSpr,
##         clearBoxSprite, freeplayScore y completionText
##   1892  albumRoll.visible = false        1896  difficultyStars.visible = false
##   1898  <fondo>.color = 0xFF000000       1899  su alpha = 0.4
##   1901  FlxG.camera.fade(0xFF000000, 1, ...)      <- el fundido, UN segundo
##   1928  y 1935  cleanup() y destroy() de dos sonidos; 1937 bossSound
##
## No es un tween del velo oscuro a opaco en medio segundo: es apagar todo lo que se
## encendio en doIntroAnim, en el mismo orden inverso, y un FADE DE CAMARA a negro de un
## segundo. El sonido `tvOff` vive en animania/menu/freeplay/, no junto a los otros de
## freeplay, y no estaba vendorizado.
const EXIT_FADE := 1.0

## capsuleOnConfirmDefault: el salto del disco y el tono de la musica.
const CONFIRM_DELAY := 0.2
const CONFIRM_TIME := 1.0
const CONFIRM_PITCH := 0.9
## `?` La altura del salto no es un literal del metodo; sale de la propia posicion del
## disco. Este 60 es una eleccion mia, marcada.
const CONFIRM_JUMP := 60.0


func _handle_exit() -> void:
	if _confirmed:
		return
	_confirmed = true
	allow_input = false
	_play_sound(SOUND_TV_OFF, 1.0)

	# Se apaga lo que doIntroAnim habia encendido.
	for name: String in ["ShadowsOnBed", "TvGlow", "TvNoiseBack", "TvNoiseForward"]:
		var node := get_node_or_null(name) as CanvasItem
		if node != null:
			node.visible = false
	for path: String in ["UI/AlbumRoll", "UI/DifficultyStars"]:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false

	# El fundido es de camara, negro y de un segundo. Aqui lo hace el velo, que ya esta
	# encima de todo el diorama con su zIndex 8; la camara de Godot no tiene un fade.
	if dark_overlay != null:
		dark_overlay.color = Color(0.0, 0.0, 0.0, dark_overlay.color.a)
		create_tween().tween_property(dark_overlay, "modulate:a", 1.0, EXIT_FADE)

	await get_tree().create_timer(EXIT_FADE).timeout
	get_tree().change_scene_to_file(MENU)


## ─── initHeader (from binary at 0x34cca20) ──────────────────────────────────
## Creates the header UI with song title, BPM, difficulty info.
## From binary: uses 76.0 and 0.5 constants.

func _init_header() -> void:
	# The header elements are created in the scene or added here.
	# Position them at the top of the screen.
	# Este metodo ya no toca las tres etiquetas de info, ni su sitio ni su alfa. No son
	# suyas: las coloca postHeader (lineas 1574-1580) y las construye el builder con esa
	# geometria, y el alfa lo reparten postHeader (0.0001) y updateDataStuff (1).
	#
	# Lo que habia aqui era una columna inventada en la esquina de arriba -"colocarlas en
	# lo alto de la pantalla"- que se ejecutaba DESPUES del builder y las devolvia ahi.
	# Cuarto sitio en este fichero con dos escritores para la misma propiedad. Cuando algo
	# se coloca donde no debe, el sospechoso no es quien lo coloca bien.
	pass


## ─── postHeader (0x34cb6e0, lineas 1550-1594) ──────────────────────────────
## Leido entero, construido a medias. Lo que hace: el grupo de puntos de dificultad
## (zIndex 70), la capsula de abajo -sparrow 'animania-freeplay/bottom capsule', zIndex
## 650- y las tres etiquetas de info encima de ella (ancho 300, y = capsula.y + 23,
## alineadas izquierda/centro/derecha, fuente DS-DIGIB.TTF a 28).
##
## De todo eso aqui solo va lo que esta pinchado sin ambiguedad, que son las dos ultimas
## lineas del metodo:
##
##   1593  alpha = 0.0001 en infoBpmText, infoTitleText, infoDiffText, highScoreSpr,
##         clearBoxSprite, freeplayScore y completionText
##   1594  dotsGrp.visible = false
##
## O sea: la cabecera NO nace oculta con visible, nace con un alfa practicamente cero, y
## quien la sube a 1 es updateDataStuff. Eso es lo que hace que aparezca al elegir
## cancion en vez de estar puesta desde el principio.
##
## `?` La capsula, los puntos y la fila de etiquetas siguen sin construir, por dos
## motivos concretos: la x/y de la capsula sale de aritmetica con get_width/get_height a
## traves de setters de vtable que falta trazar, y DS-DIGIB.TTF no esta en el build -no
## hay ni un .ttf en el-, asi que la fuente sera una sustitucion. Ver PORTING.md 8f.
func _post_header() -> void:
	_update_song_info()
	# Linea 1593.
	for node: CanvasItem in [info_bpm_text, info_title, info_difficulty, high_score_spr,
			clear_box_sprite, freeplay_score, completion_text]:
		if node != null:
			node.modulate.a = HEADER_HIDDEN
	# Linea 1594.
	var dots := get_node_or_null("UI/DotsGrp") as CanvasItem
	if dots != null:
		dots.visible = false


## ─── changeDiff (from binary at 0x34c7a40) ──────────────────────────────────
## Changes the current difficulty. Wraps around.
## From binary: references rememberedDifficulty.

## ─── changeDiff (0x34c7a40, lineas 978-1073) ───────────────────────────────
##    989  currentDifficulty = MathUtil.curSelectionWrap(...)
##   1004  FunkinSound.playOnce(Paths.sound('freeplay/diffChange'))
##   1009  SongRegistry.instance ...  (si no encuentra la cancion, avisa por consola)
##   1020  Save.instance.getSongScore(<cancion>, <dificultad>)
##   1021  score  = <eso>.score
##   1022  <eso>.tallies.sick / .good / .totalNotes   -> el porcentaje
##   1073  updateDataStuff(false)
##
## El sonido NO es el de cambiar de cancion: es `freeplay/diffChange`, otro fichero. El
## puerto reutilizaba `song switch` para las dos cosas.
##
## Los dos argumentos son Null y el prologo (0x34c7a69) dice que valen cuando llegan a
## nulo: `xor %eax,%eax` antes de mirar cada bandera, o sea amount = 0 y playSound =
## false. Por eso changeSelection puede llamar a changeDiff() sin que suene dos veces.
##
## `?` Lo que no he acabado de trazar es cuando suena de verdad: el bloque del sonido
## esta ademas detras de un `cmpb $0x0,0x2d8(%r12)`, o sea de allowInput, y su relacion
## con la rama de playSound se pierde en la reordenacion de bloques del compilador. Aqui
## suena cuando se cambia de dificultad a proposito y calla cuando lo arrastra un cambio
## de cancion, que es lo que hacen los dos sitios que lo llaman.
##
## De donde salen la puntuacion y el porcentaje queda identificado y sin portear: son
## Save.getSongScore y sus tallies (sick, good, totalNotes), y el puerto no tiene
## guardado de partidas.
func change_diff(amount: int = 0, play_sound: bool = false) -> void:
	if _confirmed or not allow_input:
		return
	current_difficulty = wrapi(current_difficulty + amount, 0, total_diffs)
	_update_data_stuff(false)
	if play_sound:
		_play_sound(SOUND_DIFF_CHANGE, SWITCH_VOLUME)


## ─── FreeplayScore / ScoreNum ──────────────────────────────────────────────
## initHeader linea 1540: `new FreeplayScore(0, 61, 7)`. La x es un `pxor %xmm0,%xmm0`,
## o sea cero; la y es el double 61.0; el 7 va en %edx. El bucle de su constructor avanza
## 0x2d = 45 px por digito antes de cada ScoreNum.
##
## set_scoreShit (lineas 14-26) parte el numero con `% 10` y division entera y le da a
## cada ScoreNum su digito, de derecha a izquierda.
##
## Y cada digito NO es un numero pintado: ScoreNum monta en su linea 100 diez animaciones
## por prefijo -"ZERO DIGITAL", "ONE DIGITAL", ... "NINE DIGITAL"- de 16 fotogramas a 24
## desde 'animania-freeplay/digital_numbers'. Es un display que parpadea.
##
## La etiqueta de texto se queda al lado: el resto del puerto la lee y quitarla ahora seria
## un cambio que no toca aqui. Los digitos son lo que se ve.
##
## `?` Los ceros a la izquierda se dejan puestos, que es lo que sale de un display de siete
## digitos. No he leido si set_scoreShit los oculta.
const SCORE_DIGIT_WORDS := ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN",
	"EIGHT", "NINE"]


func _show_score_digits(value: int) -> void:
	var row := get_node_or_null("UI/FreeplayScore") as Node2D
	if row == null:
		return
	var left: int = maxi(value, 0)
	# De derecha a izquierda, como el % 10 de la linea 19.
	for i: int in range(row.get_child_count() - 1, -1, -1):
		var digit := row.get_child(i) as AnimatedSprite2D
		if digit == null:
			continue
		var name := StringName("%s DIGITAL" % SCORE_DIGIT_WORDS[left % 10])
		if digit.animation != name:
			digit.animation = name
			digit.play()
		left /= 10


## ─── DifficultyStars (0x39ddf80) ───────────────────────────────────────────
## La clase del mod es una reexportacion LITERAL de la del juego base: los dos
## generateSprites miden 0xf02 bytes y, normalizando los destinos de salto, no hay ni una
## instruccion distinta entre los dos. Comprobado, no supuesto -y hay que comprobarlo:
## un `nm | grep DifficultyStars_obj` devuelve el del juego base primero, que es el mismo
## tropiezo que con CharPlayer, solo que alli SI eran clases distintas.
##
##   generateSprites 29  sparrow 'animania-freeplay/diffstars', escala 0.281843
##                   40  addByPrefix('dot',  'difficulty dot',  1)
##                   41  addByPrefix('star', 'difficulty star', 1)
##                   48  addByIndices('flame',     'difficulty fire', [...])
##                   49  addByIndices('flameloop', ...)
##                   42  once huecos, paso 40 px, y = sin(i/3.5)*10 - 10
##   set_difficulty  66  Std.int(...) y updateStars()
##   updateStars     87-90  el que se apaga: cancelTweensOf, scale 1.15/1.1 y un tween
##                          de 0.4 con quartOut
##                   110    el que se enciende: tween de 0.25 con quartOut y un
##                          startDelay, mas un +-0.05 al azar
##
## PORTEADO: los once huecos con su onda y su escala, y el reparto dot/star por el rating.
## `?` SIN portear: los tweens de encendido y apagado de updateStars y la llama. La llama
## son doce fotogramas que en el mod se disparan al SUBIR de dificultad, y eso cuelga de
## los tweens; sin ellos seria una llama fija, que es peor que ninguna.
##
## Los ratings salen de `ratings` en el metadata de cada cancion. phone-call solo declara
## `standart: 4`, que no es ninguna de las tres del puerto, asi que sus tres valen 4.
func _update_stars() -> void:
	if difficulty_stars == null:
		return
	var rating: int = 0
	if cur_selected >= 0 and cur_selected < current_filtered_songs.size():
		var song: Dictionary = current_filtered_songs[cur_selected]
		var table: Dictionary = song.get("ratings", {}) as Dictionary
		var id: String = ""
		if current_difficulty >= 0 and current_difficulty < current_diffs_ids.size():
			id = current_diffs_ids[current_difficulty]
		rating = int(table.get(id, 0))
	for i: int in difficulty_stars.get_child_count():
		var star := difficulty_stars.get_child(i) as AnimatedSprite2D
		if star == null:
			continue
		star.animation = &"difficulty star" if i < rating else &"difficulty dot"


## _update_difficulty_display se ha ido entera, no vaciada a un `pass`.
##
## Hacia dos cosas y las dos eran invencion que pisaba a lo leido: escribia el texto de
## dificultad sin el prefijo 'DIF: ' que pone updateDataStuff en su linea 1125, y encendia
## `current_difficulty + 1` estrellas por VISIBILIDAD -entre una y tres- cuando en el mod
## son once huecos que pasan de punto a estrella segun el RATING de la cancion, que llega
## a 11. Lo primero lo hace updateDataStuff y lo segundo _update_stars, los dos desde donde
## el binario los llama. Un metodo que solo existe para que sus llamadas no fallen es peor
## que ninguno: parece que algo se hace.


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
	# El sonido va al principio, linea 824, no al final.
	if play_sound and can_play_switch_sound:
		_play_sound(SOUND_SWITCH, SWITCH_VOLUME)
	# Linea 840: changeDiff() con los dos argumentos a null, o sea con sus valores por
	# defecto. Cambiar de cancion vuelve a fijar la dificultad para la nueva, que es lo
	# que trae su puntuacion y su porcentaje.
	change_diff()
	_refresh(false)
	# Linea 855: cambiar de disco cambia el tema que suena. Va al final, despues de
	# changeDiff.
	_play_cur_song_preview()


## ─── _refresh (updated) ─────────────────────────────────────────────────────
## Where each disk is heading and how it should look getting there.

func _refresh(snap: bool) -> void:
	# updateDisks es quien coloca; aqui solo queda la escala y el alfa, que el mod maneja
	# desde DiskSpr y no desde este metodo.
	_update_disks(cur_selected_float)
	# Ya no se guardan metas de escala ni de alfa: no existen en el mod. El tamaño, el
	# giro y el gris salen los tres de la x, en _apply_disk_pose.
	if snap:
		for i: int in disks.get_child_count():
			var disk: Node2D = disks.get_child(i)
			disk.position = disk.get_meta(&"target") as Vector2
			_apply_disk_pose(disk)
	# Nada de move_child: quien pone el elegido delante es su zIndex (10 contra 5 en el
	# mod, 1 contra 0 aqui), y reordenar el arbol rompia la correspondencia con el ID.
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
	# Aqui habia dos lineas que pisaban las etiquetas: el titulo con
	# `id.capitalize()` y el BPM con la cadena vacia, "el BPM vendria de los datos de la
	# cancion". No son de ningun metodo del mod -quien escribe esos textos es
	# updateDataStuff, lineas 1120-1125-, y como _refresh llama a esto DESPUES, el BPM
	# acababa siempre en blanco por mucho que updateDataStuff lo rellenara. Fuera.
	# El titulo colaba porque capitalize() sobre "phone-call" da justo "Phone Call".


## ─── _update_score_for_selection ─────────────────────────────────────────────

## updateDataStuff lineas 1090-1092:
##
##   var save = <guardado>.getSongScore(<cancion>, currentDifficulty);
##   score      = save.score;
##   completion = (save.tallies.good + save.tallies.sick) / save.tallies.totalNotes;
##
## Los dos `asDouble` que se suman son good y sick, el tercero es totalNotes y el `divsd`
## esta en 0x34c657f. El porcentaje es una fraccion de 0 a 1; el *100 lo hace _drive_score
## al pintarlo, no esto.
##
## `?` De donde sale ese guardado NO se portea, y es un hueco de verdad, no un descuido:
## getSongScore lee el Save del juego base y este proyecto no tiene guardado ninguno -ni
## el mod portado ni Rubicon-, y el menu de historia tambien deja su marcador a 0. La
## formula queda escrita y aislada en _completion_of para que el dia que haya guardado
## esto sea una linea, no una reconstruccion.
func _update_score_for_selection() -> void:
	if cur_selected < 0 or cur_selected >= current_filtered_songs.size():
		return
	var record: Dictionary = _song_score(
		String(current_filtered_songs[cur_selected].get("id", "")), current_difficulty)
	intended_score = int(record.get("score", 0))
	intended_completion = _completion_of(record)
	prev_displayed_score = 0
	prev_displayed_completion = 0.0
	lerp_score = 0.0
	lerp_completion = 0.0


## El getSongScore de la linea 1090. Sin guardado devuelve vacio, que es lo mismo que
## devuelve el mod cuando la cancion no se ha jugado.
func _song_score(_song_id: String, _difficulty: int) -> Dictionary:
	return {}


## Linea 1092. Aislada porque es lo unico de este bloque que esta leido del binario.
func _completion_of(record: Dictionary) -> float:
	var tallies: Dictionary = record.get("tallies", {}) as Dictionary
	var total: float = float(tallies.get("totalNotes", 0))
	if total <= 0.0:
		return 0.0
	return (float(tallies.get("good", 0)) + float(tallies.get("sick", 0))) / total


## ─── generateDisksList (0x34d4070, lineas 508-553) ─────────────────────────
##   514-521  un DiskSpr por cancion, con sus currentDiffsIds
##   524-526  scrollFactor, zIndex 0 y el tamano tomado del propio disco
##   535-542  currentPhone e initLock(...) para los bloqueados
##   545      selectorsGroup
##   550      rememberSelection()
##   552      changeSelection(...)
##   553      changeDiff(...)
##
## Los discos nacen con zIndex 0; el 5 y el 10 los pone updateDisks despues. La cola
## -recordar, seleccionar, fijar dificultad- si se portea; la creacion de los DiskSpr no
## hace falta porque aqui los discos ya estan en la escena.
func _generate_disks_list() -> void:
	if cur_selected < 0 or cur_selected >= SONGS.size():
		cur_selected = 0
	cur_selected_float = float(cur_selected)
	_remember_selection()
	change_selection(0, false)
	change_diff()


## ─── initCharacters (0x34c1800, lineas 1401-1423) ──────────────────────────
## Lo que decia el comentario viejo -"230.0 y 235.0 para colocar, 0.5 de escala"- estaba
## a medias y en un punto mal: el 0.5 no es escala, es la razon de paralaje que se le pasa
## al FlxTypedRatioHandler. Los tres objetos que crea, leidos:
##
##   1401  currentGirlfriend = new CharGirlfriend(FlxG.width - 508, 230, 'none')
##   1402  currentGirlfriend.zIndex = 4
##   1403  add(currentGirlfriend)
##   1404  <ratioHandler>.add(currentGirlfriend, 0.5, 0);  shadowsOnBed.add(...)
##   1407  currentPlayer = new CharPlayer(FlxG.width - 780, 235, 'none', null, null)
##   1408  currentPlayer.zIndex = 5   (+ un cierre colgado del personaje)
##   1411  add(currentPlayer);  <ratioHandler>.add(currentPlayer, 0.5, 0)
##   1415  currentPhone = new FunkinSprite(FlxG.width - 517.6, 265.9,
##             'animania-freeplay/skinSelector/phone')
##   1416  currentPhone.zIndex = 6
##   1418  animation.addByPrefix('switch', 'Phone fall', 24)
##   1419  animation.play('switch');   1420  currentPhone.visible = false
##   1422  <ratioHandler>.add(currentPhone, 0.5, 0);  shadowsOnBed.add(currentPhone)
##
## Las restas son sobre FlxG.width, que en el mod es 1280: la novia en 772, el jugador en
## 500 y el telefono en 762.4. Los tres van dentro de shadowsOnBed, que buildBg deja
## invisible (linea 1219) y que doIntroAnim enciende: los personajes no se ven hasta que
## se enciende el televisor.
##
## PORTEADO: el telefono, que es un sparrow suelto y esta entero. Lo crea la escena
## (build_freeplay_scene.gd), invisible y con z absoluto 6. Se crea invisible y NINGUN
## metodo de FreeplayScreen lo vuelve a tocar -initCharacters es el unico de la clase que
## lee el campo 0x198-, asi que quien lo enseñe esta fuera de esta pantalla.
##
## SIN PORTEAR, y no es un olvido: CharPlayer y CharGirlfriend no son del mod, son
## `funkin::ui::freeplay::charSelect::` del juego base, con loadCharacter, getData sobre
## un JSON de personaje, loadSkinChanger y loadIcon, y sus skins son atlas de Adobe
## (Animation.json + spritemap) en skinSelector/bf y /gf. Es un subsistema, no dos
## sprites. Los dos se construyen con el personaje 'none', y el unico sitio de esta clase
## que llama a changeCharacter es la rama del disco aleatorio de playCurSongPreview, que
## tambien pasa 'none'; quien pone un personaje de verdad esta en updateDataStuff o
## postHeader. Las posiciones, los zIndex y el 0.5 de paralaje quedan escritos arriba para
## cuando se porteen.
func _init_characters() -> void:
	# Las cadenas siguen siendo el estado que lee el resto del puerto. El mod construye
	# los dos personajes con la skin 'none' (lineas 1401 y 1407), no con bf/gf.
	#
	# `currentCharacterId` (campo 0xe0) NO se toca aqui: es otra cosa -el personaje de
	# freeplay, el que viene de rememberedCharacterId- y initCharacters no lo escribe.
	# Ponerlo a 'none' de paso habria sido cambiar algo que este metodo no cambia.
	current_girlfriend = "none"
	current_player = "none"


## ─── showStickers (0x34bb090, lineas 410-416) ──────────────────────────────
## Corto: lee `currentCharacter` (campo 0xe8), llama a un metodo virtual de la propia
## pantalla (hueco 0x290 de su vtable) y termina en `currentCharacter.degenStickers(...)`.
##
## Sin portear a proposito: cuelga entero de `currentCharacter`, que en el puerto es una
## cadena y no el objeto de personaje del mod, y de un sistema de pegatinas que no existe
## aqui. Queda como hueco declarado y no como un `pass` sin explicacion.
func _show_stickers() -> void:
	pass


## ─── openHelp (0x34bc930, linea 1685) ──────────────────────────────────────
## Esta VACIO en el mod. Los 312 bytes del metodo son el prologo y el epilogo del marco
## de pila de hxcpp -empujar la posicion, comprobar el limite, sacarla- y entre medias no
## hay ni una instruccion. El `pass` del puerto era correcto, pero por la razon
## equivocada: no es que falte portear FreeplayScreenHelp, es que este metodo no llama a
## nadie. La clase FreeplayScreenHelp existe (22 simbolos) y la abre otro sitio.
func _open_help() -> void:
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

	# capsuleOnConfirmDefault (0x34c0a20, lineas 627-645):
	#   627  new FlxTimer().start(0.5, ...)
	#   634  <disco>.forcePosition()
	#   635  FlxTween.tween(<disco>, {y: ...}, 1, {startDelay: 0.2, ease: backInOut})
	#   640  FlxTween.tween(<musica>, {pitch: 0.9}, ..., {ease: quadInOut})
	#   643  lo mismo sobre layerSound
	#   645  new FlxTimer().start(1, ...)   <- y aqui se cambia de pantalla
	# O sea: el disco salta con un backInOut de un segundo tras 0.2 de espera, la musica
	# baja de tono a 0.9, y la transicion tarda UN segundo, no 0.6.
	var disk: Node2D = _get_selected_disk()
	if disk != null:
		var jump := create_tween()
		jump.tween_property(disk, "position:y",
			disk.position.y - CONFIRM_JUMP, CONFIRM_TIME) \
			.set_delay(CONFIRM_DELAY).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)
	_bend_pitch(CONFIRM_PITCH)

	await get_tree().create_timer(CONFIRM_TIME).timeout
	LoadingScreen.go_to(get_tree(), String(song["scene"]), String(song.get("id", "")))


## Los dos tweens de tono de capsuleOnConfirmDefault, lineas 640 y 643. En Godot el tono
## de un AudioStreamPlayer es pitch_scale, no una propiedad interpolable de un tween de
## flixel, pero el destino y la curva son los mismos.
func _bend_pitch(to: float) -> void:
	for player: Node in [sfx, layer_sound]:
		if player is AudioStreamPlayer and (player as AudioStreamPlayer).playing:
			create_tween().tween_property(player, "pitch_scale", to, CONFIRM_TIME) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


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

	# Las flechas NO se atienden aqui: handleInput las SONDEA por frame para poder repetir
	# mientras se mantienen. Lo que queda por evento es lo que no se repite.
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			# changeDiff(UI_DOWN.checkJustPressed() ? -1 : 1), linea 1856: ABAJO resta.
			# Es checkJustPressed, no checkPressed, asi que aqui no hay repetido.
			KEY_DOWN, KEY_S:
				change_diff(-1, true)
			KEY_UP, KEY_W:
				change_diff(1, true)
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


## ─── playCurSongPreview (0x34c3670, lineas 887-916) ────────────────────────
## Es el unico sitio desde el que se llama a changeTheme (la llamada esta en 0x34c3984,
## linea 911), y a el se llega desde dos: changeSelection linea 855, y el cierre de un
## segundo de doIntroAnim, linea 1651.
##
##   887  dispatch("onSongPreview")
##   891  if (disk.songData == null) {           // la capsula del disco aleatorio
##   894      <vtable +0x108 sobre la musica actual>
##   896      FunkinSound.playMusic("freeplayRandomAnimania",
##                {overrideExisting: ..., startingVolume: ..., restartTrack: ...})
##   902      FlxTween.num(..., 1.0, {onComplete: ...}, snd.volumeTween)
##   903      currentPlayer.changeCharacter("none")
##   904      currentGirlfriend.changeCharacter(...)
##   905      checkBed(...); oldThemeName = "RANDOM"; oldThemeLayerName = "RANDOM"
##        } else {
##   911      changeTheme(disk)
##        }
##   914  Conductor.instance.update(...)
##   916  dispatch("onSongPreviewPost")
##
## La rama del disco aleatorio se deja escrita pero NO se vendorizo su musica
## (assets/music/freeplayRandomAnimania/freeplayRandomAnimania.ogg, 1.31 MB): en el puerto
## no hay capsula aleatoria en la lista, asi que hoy no hay forma de llegar a esa rama.
## Cuando la haya, hay que meter ese .ogg y esto ya funciona. Marcar "RANDOM" en los dos
## nombres viejos es lo que hace que el siguiente changeTheme vuelva a cargar de verdad.
const RANDOM_TRACK := "res://animania_mod/source/music/freeplayRandomAnimania/freeplayRandomAnimania.ogg"
const THEME_RANDOM := "RANDOM"


func _play_cur_song_preview(disk: Node2D = null) -> void:
	var target: Node2D = disk if disk != null else _get_current_disk()
	if target != null and not _song_of(target).is_empty():
		_change_theme(target)
		return

	# Linea 891: sin songData es la capsula aleatoria.
	_theme_tween = _swap_track(_theme_music, _theme_tween, RANDOM_TRACK,
		LAYER_TARGET_VOLUME)
	_layer_tween = _swap_track(layer_sound, _layer_tween, "", 0.0)
	current_player = "none"
	_check_bed("none")
	old_theme_name = THEME_RANDOM
	old_theme_layer_name = THEME_RANDOM


## ─── changeTheme (0x34c2540, lineas 920-970) ───────────────────────────────
## Lo que habia aqui estaba inventado de arriba abajo: trataba el tema como una TEXTURA
## -cargaba `images/freeplayThemes/Freeplay_<id>.png` y se la pegaba al Backwall- y usaba
## el id de la cancion como nombre de tema. No hay ninguna imagen de tema en el mod. El
## tema es MUSICA, y son los 22 MB de assets/music/freeplayThemes/ que el puerto no tocaba.
##
## El metodo real, leido linea a linea:
##
##   920  tema  = disk.songData.<campo 0xa8>              // freeplayTheme
##   922  capa  = "-" + disk.songData.<campo 0xb8>        // freeplayLayer, con el guion
##   925  if (tema != oldThemeName) {
##   929        FlxTween.cancel(<el tween que hubiera>)
##   930        <cleanup del sonido anterior>
##   931        <vtable +0x108 sobre el sonido anterior>
##   933        FunkinSound.load("freeplayThemes/Freeplay_" + tema)
##   940        FlxTween.num(<vol actual>, <destino>, 1.0, {onComplete: ...}, snd.volumeTween)
##        }
##   945  if (capa != oldThemeLayerName) {
##   951        <mismo apagado del layerSound anterior, tween de 1.0>
##   954        layerSound = FunkinSound.load("freeplayThemes/Freeplay_Layer" + capa)
##   959        destino = <musica base>.<campo 0xe0>
##   960        FlxTween.num(layerSound.<0xd8 = volume>, destino, 1.0, ..., volumeTween)
##        }
##   970  oldThemeName = tema; oldThemeLayerName = capa; dispatch("onChangeTheme")
##
## La duracion del tween es literal y sale dos veces: el double en 0x59fa558 es 1.0.
##
## Rutas exactas, de los literales del binario: "freeplayThemes/Freeplay_" (0x5c28fa0) y
## "freeplayThemes/Freeplay_Layer" (0x5c290f8). La segunda NO lleva guion porque la capa ya
## se lo puso en la linea 922.
##
## `?` El destino del fundido de la capa es el campo 0xe0 de la musica base. 0xd8 es
## `volume` (lo escribe FlxSound.set_volume en 0x15f7530), asi que 0xe0 es el double
## siguiente, que en HaxeFlixel es `_volumeAdjust`: vale 1.0 salvo que se use proximity, y
## freeplay no la usa. Por eso aqui el destino es 1.0. Deducido, no leido.
const THEME_DEFAULT := "Base"
const LAYER_DEFAULT := "default"
const THEME_TWEEN := 1.0
const THEME_DIR := "res://animania_mod/source/music/freeplayThemes/"
## El campo 0xe0 de arriba. Ver la nota.
const LAYER_TARGET_VOLUME := 1.0

var _theme_music: AudioStreamPlayer
var _theme_tween: Tween
var _layer_tween: Tween


func _change_theme(disk: Node2D, _data: Variant = null) -> void:
	var song: Dictionary = _song_of(disk)
	if song.is_empty():
		return
	var theme: String = String(song.get("theme", THEME_DEFAULT))
	# Linea 922: el guion lo pone changeTheme, no el metadato.
	var layer: String = "-" + String(song.get("layer", LAYER_DEFAULT))

	if theme != old_theme_name:
		_theme_tween = _swap_track(_theme_music, _theme_tween,
			THEME_DIR + "Freeplay_" + theme + ".ogg", LAYER_TARGET_VOLUME)
		old_theme_name = theme

	if layer != old_theme_layer_name:
		_layer_tween = _swap_track(layer_sound, _layer_tween,
			THEME_DIR + "Freeplay_Layer" + layer + ".ogg", LAYER_TARGET_VOLUME)
		old_theme_layer_name = layer


## Las lineas 929-940 y 951-960 son el mismo bloque dos veces: cancelar el tween que
## hubiera, cambiar la pista y subir el volumen en 1.0 s. Aqui van juntas.
func _swap_track(player: AudioStreamPlayer, tween: Tween, path: String,
		target: float) -> Tween:
	if player == null:
		return null
	if tween != null and tween.is_valid():
		tween.kill()
	if not ResourceLoader.exists(path):
		# Un tema que no se vendorizo. Se calla en vez de sonar el anterior, que es lo
		# que haria si nos limitasemos a volver.
		player.stop()
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		player.stop()
		return null
	player.stream = stream
	player.volume_db = linear_to_db(0.0001)
	player.play()
	var fresh: Tween = create_tween()
	fresh.tween_method(
		func(v: float) -> void: player.volume_db = linear_to_db(maxf(v, 0.0001)),
		0.0, target, THEME_TWEEN)
	return fresh


## La cancion que hay detras de un disco. changeTheme la saca del `songData` en el offset
## 0x268 del DiskSpr; aqui el disco lleva su indice en un meta, como en updateDisks.
func _song_of(disk: Node2D) -> Dictionary:
	if disk == null:
		return {}
	var index: int = int(disk.get_meta(&"index", -1))
	if index < 0 or index >= current_filtered_songs.size():
		return {}
	return current_filtered_songs[index] as Dictionary


## ─── getCurrentDisk (from binary at 0x34bf330) ──────────────────────────────
## Returns the currently selected disk node. From binary: accesses the
## selector's song list at vtable offset 0x68 and reads the current entry.
## References the "." path for relative access.

## ─── getCurrentDisk (0x34bf330, lineas 579-586) ────────────────────────────
## Un acceso con dos comprobaciones y poco mas. Aqui se busca por el meta `index`, no por
## la posicion en el arbol, por lo mismo que en updateDisks: el ID del disco es estable y
## su sitio en el arbol no tiene por que serlo.
func _get_current_disk() -> Node2D:
	if disks == null:
		return null
	for child: Node in disks.get_children():
		if int(child.get_meta(&"index", -1)) == cur_selected:
			_current_disk_cache = child as Node2D
			return _current_disk_cache
	return null


## ─── fadeOut (from binary at 0x34bbc50) ─────────────────────────────────────
## Bridge method that calls into HScript by name. From binary: the method
## references these strings and calls HScript bridge 0x5491020:
##   "fadeOut", "playCurSongPreview", "changeTheme", "changeDiff",
##   "updateDataStuff", "buildBg", "initCharacters"
## In practice, this triggers a fade-out of the current music and
## reinitializes the screen state.

## ─── fadeOut (0x34bb860, linea 877) ────────────────────────────────────────
## Corto y solo hace una cosa: cancela el tween que ya tuviera ese sonido
## (FlxTween.cancel), lee su volumen (campo 0xd8) y lanza un tween de volumen con
## FlxSound.volumeTween y un `onComplete`. Nada mas.
##
## El puerto le habia colgado detras un _load_songs + _refresh + _init_characters +
## _update_data_stuff "del patron del puente de HScript", que no esta en el metodo ni en
## ninguna parte de esta pantalla. Fuera.
##
## `?` La duracion del tween no es un literal del metodo: llega por la via del Dynamic y
## no la he trazado. Se deja el 0.5 que ya habia, marcado como no leido.
const FADE_SECONDS := 0.5


func _fade_out(sound: Variant = null) -> void:
	var target: Node = sound as Node if sound is Node else sfx
	if target == null or not (target is AudioStreamPlayer):
		return
	var player: AudioStreamPlayer = target as AudioStreamPlayer
	if not player.playing:
		return
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", -40.0, FADE_SECONDS)
	tween.tween_callback(func() -> void: player.stop())


## ─── preloadThemes (0x34ba820, lineas 398-405) ─────────────────────────────
## Otra que estaba inventada: recorria `images/freeplayThemes/*.png`, un directorio que no
## existe. El metodo real solo precachea SONIDO, y son tres cosas:
##
##   398  Paths.getPath("music/freeplayRandomAnimania/freeplayRandomAnimania" + "." +
##            Constants.EXT_SOUND, "MUSIC") -> FunkinMemory.cacheSound(...)
##   401  for (t in FreeplayScreen.freeplayThemes)        // estatico, .bss 0x805ef58
##   402      cacheSound(getPath("music/freeplayThemes/Freeplay_" + t, "MUSIC"))
##   404  for (l in FreeplayScreen.freeplayThemesLayers)  // estatico, .bss 0x805ef50
##   405      cacheSound(getPath("music/freeplayThemes/Freeplay_Layer" + l, "MUSIC"))
##
## Los dos estaticos son arrays de String; el mod los precachea ENTEROS al entrar, no solo
## los que alcanzan sus canciones.
##
## Aqui no se replica el precacheo ciego. Godot resuelve el .ogg por ResourceLoader y las
## cuatro pistas que el puerto alcanza pesan 7.6 MB en total; cargarlas todas de golpe al
## entrar en freeplay es peor en Android que cargarlas al cambiar de disco, que es cuando
## changeTheme las pide y tiene un segundo entero de fundido para hacerlo.
##
## Lo que si se hace es tocarlas una vez para que ResourceLoader las tenga en cache, en
## segundo plano, sin bloquear la entrada a la pantalla.
func _preload_themes() -> void:
	for path: String in _reachable_themes():
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)


## Las pistas que las canciones de SONGS pueden llegar a pedir, que es lo unico que se
## vendorizo. Ver la nota de arriba y tools/animania/PORTING.md.
func _reachable_themes() -> PackedStringArray:
	var wanted: Dictionary = {}
	for song: Dictionary in SONGS:
		wanted[THEME_DIR + "Freeplay_" + String(song.get("theme", THEME_DEFAULT)) + ".ogg"] = true
		wanted[THEME_DIR + "Freeplay_Layer-" + String(song.get("layer", LAYER_DEFAULT)) + ".ogg"] = true
	var out: PackedStringArray = PackedStringArray()
	for path: String in wanted:
		out.append(path)
	return out


## ─── destroy (from binary at 0x34d7890) ─────────────────────────────────────
## Cleanup when the screen is destroyed.
## From binary: references "overrideExisting", "restartTrack".

## ─── destroy (0x34d7890, lineas 1981-1998) ─────────────────────────────────
##   1981  <cache>.clearCache()
##   1982  super.destroy()
##   1998  FunkinSound.playMusic(Constants.defaultThemeTrack,
##             {overrideExisting: true, restartTrack: false});
##
## O sea que al salir de freeplay se vuelve a poner el tema del menu. El valor de
## Constants.defaultThemeTrack esta en .bss, asi que no se lee del fichero: se lee de su
## __boot (0x1f8dec7), y es 'animaniaLOOP' -longitud 12, que cuadra con el movl $0xc de
## al lado-. Los dos campos del objeto anonimo tambien estan leidos: overrideExisting
## true (byte a 1 en 0x30) y restartTrack false (byte a 0 en 0x58).
## Lo de la musica NO se portea, y no por olvido. El mod tiene una musica global
## (FlxG.sound.music), asi que al destruir freeplay hay que volver a ponerla a mano. En el
## puerto la musica es de cada escena: el menu principal la crea en su _init_music y la
## crea otra vez al volver a entrar, asi que `playMusic(..., restartTrack: false)` aqui no
## tendria a quien hablarle. Escribir un get_node("/root/MenuMusic") -que es lo que estuve
## a punto de dejar aqui- habria sido inventarse un autoload que este proyecto no tiene:
## los suyos son ErrorLog, MusicFilter y DebugOverlay.
func _destroy() -> void:
	if sfx != null and sfx.playing:
		sfx.stop()
	_current_disk_cache = null


## Cache for _get_current_disk.
var _current_disk_cache: Node2D = null
