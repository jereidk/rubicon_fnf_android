# Authors animania_mod/menus/freeplay/freeplay_screen.tscn.
#
#   godot --headless --path . --script tools/animania/build_freeplay_scene.gd
#
# The diorama's placements come out of FreeplayScreen.buildBg in the Linux build: a black
# backdrop, `freeplay backwall`, the `bed` sparrow, `tv glow`, the TV itself, and the
# `player` with its `player-layer` over it.
#
# Reading a FunkinSprite.create call takes one step of care. It takes two Null<double>, each
# a 16-byte block of {flag byte, double}, and the caller builds both on the stack - so which
# block is x is not obvious from the loads. create() itself settles it: it does
# `cmpb $0,(%rsi); jne skip; mov 0x8(%rsi),%r13` for the first and the same on %rdx for the
# second, and buildBg loads %rsi from the block at -0x70 and %rdx from the one at -0x60. So
# the FIRST block is x, and a flag byte of zero means the value is there.
#
# Read that way: backwall (0, 18.75), bed (0, 254), tv glow (computed, 493), player
# (50, 505), player-layer (45.75, 515) - a bedroom with the wall behind, the bed under it
# and the VCR at the bottom left. Getting it backwards put the VCR in the sky.
extends SceneTree

const OUT := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const DIR := "res://animania_mod/menus/freeplay"
const ART := "res://animania_mod/source/images/freeplay"

## postHeader, todo en el espacio 1280x720 del mod. Ver el comentario de la capsula.
const CAPSULE_SIZE := Vector2(382.0, 54.0)
const TV_AT_X := -40.0
const TV_WIDTH := 727.0
const CAPSULE_AT := Vector2(
	TV_AT_X + TV_WIDTH * 0.5 - CAPSULE_SIZE.x * 0.5,   # 1566
	720.0 - CAPSULE_SIZE.y + 1.0)                      # 1567
const TEXT_WIDTH := 300.0
const TEXT_HEIGHT := 40.0
const TEXT_AT := Vector2(
	CAPSULE_AT.x + CAPSULE_SIZE.x * 0.5 - 153.0,       # 1574
	CAPSULE_AT.y + 23.0)                               # 1580
const TEXT_SIZE := 28.0                                # 1585
## Las tres etiquetas comparten UNA caja de 300 con tres alineaciones, asi que el ancho de
## la fuente decide si caben. La del mod, DS-DIGIB, es una de siete segmentos y estrecha;
## VCR OSD Mono Cyr es monoespaciada y bastante mas ancha, y a 28 los tres textos suman
## 477 px sobre una caja de 450 y se pisan -medido, no supuesto: a 42/36/32/28 chocan-.
##
## A 24 suman 406 y "caben", pero la del centro va CENTRADA, no pegada a la izquierda:
## ocupa de 155 a 295 y la de la derecha arranca en 296, asi que se tocan igual. Sumar
## anchos no basta cuando una de las tres esta centrada. A 20 la izquierda acaba en 94, la
## del centro va de 166 a 284 y la derecha arranca en 321: 72 y 37 px de aire.
##
## La constante leida sigue siendo 28; esto es el precio de la sustitucion y va con
## nombre propio en vez de escondido dentro del 28.
const FONT_SUBSTITUTE_NARROW := 20.0 / (28.0 * 1.5)
const TEXT_COLOR := Color8(0xcc, 0xff, 0xff)           # 1588, 0xFFCCFFFF
const TEXT_FONT := "res://animania_mod/source/fonts/VCR OSD Mono Cyr.ttf"

## Los puntos de dificultad, FreeplayDots (0x4090f60 y alrededores). Leido:
##   postHeader 1550  new FreeplayDots(tvSprite.x + tvSprite.width*0.5 - 2, null)
##              1551  zIndex = 70      1552  scrollFactor.set(0, 0)
##              1553  y = 20           1554  visible = false
##   repositionDots 87-91  dot.x = grupo.x - n*distance*0.5 + i*distance;  dot.y = grupo.y
##   loadDots 57 / setDots 76 / set_curDiff 25-27:
##       el elegido  -> alpha 1   y su color entero
##       los demas   -> alpha 0.9 y color.getDarkened(0.45)
##
## `distance` es el segundo argumento del constructor y postHeader pasa null, asi que
## vale su valor por defecto, que es el double en 0x59fa980: 35. Los nombres de campo
## salen del __GetFields de la clase: distance, dots, fuckingDots, curDiff.
const DOTS_AT := Vector2(TV_AT_X + TV_WIDTH * 0.5 - 2.0, 20.0)
const DOT_DISTANCE := 35.0
## FreeplayDots.diffColors, del __boot de la clase (0x4090f60). Cinco entradas.
const DIFF_COLORS := {
	"easy": Color8(0xc5, 0xfe, 0x59),
	"normal": Color8(0xfe, 0xe5, 0x43),
	"hard": Color8(0xfe, 0x24, 0x66),
	"legacy": Color8(0x7f, 0x6a, 0xf7),
	"standart": Color8(0x6c, 0xe7, 0xc3),
}
## Las dificultades que el puerto ofrece hoy, en el mismo orden que su tabla.
const DOT_IDS := ["easy", "normal", "hard"]
## Flixel getDarkened(f) multiplica el RGB por (1 - f). Aqui f = 0.45.
const DOT_DARKEN := 1.0 - 0.45
const DOT_DIM_ALPHA := 0.9

## El craneo de jefe. buildBg 1347 lo pone en (105, -200) con zIndex 900.
const BOSS_AT := Vector2(105.0, -200.0)
## Su hoja se vendoriza a la mitad, asi que el nodo compensa con el doble de escala.
const BOSS_ATLAS_SCALE := 0.5
const BOSS_VOLUME := 0.25

## Las estrellas de dificultad, DifficultyStars.generateSprites (0x39ddf80).
##
## El bucle de la linea 42 va de 0 a 10 -sale del `cmp $0xb` con su `addl $0x1`- asi que
## son ONCE huecos, y el acumulador de al lado suma 0x28 por vuelta: 40 px de paso. La `y`
## es una onda, `sin(i / 3.5) * 10 - 10`, y la escala es el 0.281843 de la linea 29.
##
## Once cuadra con los datos: dadbattle en hard tiene rating 11, que las llena todas.
const STAR_COUNT := 11
const STAR_STEP_X := 40.0
const STAR_WAVE_PERIOD := 3.5
const STAR_WAVE_AMPLITUDE := 10.0
const STAR_SCALE := 0.281843

## El marcador. initHeader linea 1540 crea FreeplayScore(0, 61, 7) -la x es un
## `pxor %xmm0,%xmm0`, o sea cero; la y el double 61.0; y el 7 va en %edx-, y el bucle de
## su constructor avanza 0x2d = 45 px por digito antes de cada ScoreNum.
##
## Cada digito es una animacion de DIEZ que ScoreNum monta en su linea 100, nombradas por
## el prefijo "<PALABRA> DIGITAL" -ZERO, ONE, ... NINE-, de 16 fotogramas a 24. O sea que
## no es un numero pintado: es un display que parpadea.
## El 0 del constructor NO es donde acaba: initHeader linea 1543 le cambia la x justo
## despues, con `freeplayScore.x = FlxG.width - freeplayScore.width + 5` -el get_width es
## el hueco 0x230, el set_x el 0x210 y el 5.0 el double en 0x59fa820-. O sea que el
## marcador va pegado al borde DERECHO, debajo del HIGHSCORE, no en la esquina izquierda
## encima del televisor, que es donde lo puso el 0 a secas.
##
## El ancho es el de la caja de los siete: 6*45 mas el fotograma mas ancho, que son 138.
const SCORE_DIGITS := 7
const SCORE_STEP_X := 45.0
const SCORE_FRAME_W := 138.0
const SCORE_WIDTH := (SCORE_DIGITS - 1) * SCORE_STEP_X + SCORE_FRAME_W
const SCORE_AT := Vector2(1280.0 - SCORE_WIDTH + 5.0, 61.0)
## Los prefijos del atlas, en orden de digito.
const DIGIT_WORDS := ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN",
	"EIGHT", "NINE"]

## Los dos personajes del dormitorio y el SEGUNDO telefono, el del script.
##
## initCharacters coloca por la esquina como todo Flixel, pero un atlas de Adobe no trae
## tamano: gdanimate lo dibuja de un arbol de simbolos. Asi que la esquina se MIDE, con
## tools/animania/harness/measure_freeplay_chars.gd, que lo pinta y cuenta pixeles opacos.
## Medido: bf esquina local (-6, -5) y 383x423; gf esquina local (-20, 1) y 310x383. La
## posicion del nodo es el destino menos esa esquina.
## CORREGIDO. A las coordenadas de initCharacters hay que sumarles el `position` del JSON
## de la skin, porque loadCharacter linea 147 crea el sprite que se ve
## -`skinAtlas = new FunkinSprite(position[0], position[1], ...)`, guardado en 0x2c0, que
## el __Field de CharPlayer identifica como skinAtlas- en esa posicion RELATIVA al grupo.
##
## Que es relativa se ve en los propios datos: bf-standart pide [70,0] y gf-animania
## [-115,-5], y como coordenadas de mundo eso seria fuera de la pantalla.
##
## bf-animania trae [0,0], asi que bf no se mueve. gf-animania trae [-115,-5], asi que la
## novia estaba 115 px a la derecha y 5 abajo de donde le toca.
const GF_AT := Vector2(772.0 - 115.0 + 20.0, 230.0 - 5.0 - 1.0)   # 1401 + position
const BF_AT := Vector2(500.0 + 0.0 + 6.0, 235.0 + 0.0 + 5.0)      # 1407 + position
## data/scripts/states/FreeplayScreen.script, createPost: un sparrow aparte del que crea
## initCharacters, en otro sitio y con otro zIndex, y ESTE si se enseña.
const PHONE_CALL_AT := Vector2(1280.0 - 510.0, 300.0)
const SCREEN := Vector2(1920.0, 1080.0)

## Funkin is 1280x720 and this project is 1920x1080. buildBg places everything against
## FlxG.width/height, so the whole diorama lives in that space.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _root: Node2D


func _init() -> void:
	# Los dos atlas de televisor los adelgaza tools/animania/optimize_atlas.py; sus
	# SpriteFrames se generan aqui para que la escena no dependa de un .tres a mano.
	_build_frames("TVNOISE", "freeplay_tvnoise", 24.0)
	_build_frames("TVBACK", "freeplay_tvback", 24.0)
	# initHeader 1442-1443 y 1487-1488: los dos botones traen un unico prefijo de 19
	# fotogramas y se parten con addByIndices en `idle` (0..17 y vuelta al 0) y `pressed`
	# (el 18). Los indices salen de los Array_obj<int>::fromData del propio metodo.
	_build_split_frames("help", "freeplay_help", "help button")
	_build_split_frames("characters", "freeplay_characters", "character button")
	# initHeader 1523: addByPrefix('y', 'highscore small instance 1'), 27 fotogramas.
	_build_frames("highscore", "freeplay_highscore", 24.0, ".")
	# postHeader linea 1561: la capsula de info de abajo.
	_build_frames("bottom_capsule", "freeplay_capsule", 24.0, ".")
	# buildBg linea 1349: addByPrefix(..., 'bossfight indicator', 24).
	_build_frames("bossfightIndicator", "freeplay_boss", 24.0, ".")
	# DifficultyStars.generateSprites lineas 40-49: dot, star y las dos de la llama.
	_build_frames("diffstars", "freeplay_stars", 24.0, ".")
	# ScoreNum ctor linea 100: diez animaciones "<PALABRA> DIGITAL" a 24.
	_build_frames("digital_numbers", "freeplay_digits", 24.0, ".")
	# initCharacters linea 1417: el telefono, un sparrow de una sola animacion.
	_build_frames("phone", "freeplay_phone", 24.0, ".")

	_root = Node2D.new()
	_root.name = "FreeplayScreen"
	_root.set_script(load("res://animania_mod/menus/freeplay/freeplay_screen.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	# buildBg's first sprite: a black FlxSprite blown up to 1500x1500 and centred. It is
	# what the diorama sits on, and why nothing behind it can show through.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	# buildBg linea 1195: makeGraphic(..., 0xFF18121C). No es negro puro.
	backdrop.color = Color8(0x18, 0x12, 0x1C)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(backdrop)
	backdrop.set(&"layout_mode", 0)
	backdrop.size = Vector2.ONE * 1500.0 * FUNKIN_TO_RUBICON
	backdrop.position = (SCREEN - backdrop.size) * 0.5

	# El orden de dibujo es el zIndex de cada pieza en buildBg, no el orden del arbol:
	# bgWall 1, bgBed 2, shadowsOnBed 3, tvGlow 7, darkOverlay 8, tvBg 10, diskPlayer 16,
	# grpDisks 19, tvBackBG 20, diskPlayerMask 24, tvNoiseBack 26, albumRoll 27,
	# tvNoiseForward 28, tvSpriteFlash 29, tvSprite 30, difficultyStars 35,
	# selectorsGroup 100, bossfightSkull 900. El puerto los tenia todos en 0 y se apoyaba
	# en el orden del arbol, lo que dejaba DarkOverlay -que va en 8, por DEBAJO del tele y
	# de los discos- encima de todo por ser el ultimo.
	_sprite("Backwall", "bg/freeplay backwall.png", Vector2(0.0, 18.75)).z_index = 1

	# The bed. Three frames that are three STATES rather than a cycle. buildBg names them
	# with addByIndices: `light` -> [0], `normal` -> [1], `none` -> [2] (the third one is
	# `none`, read out of the binary rather than guessed), and checkBed(name) plays one of
	# them. create() ends on checkBed('none'), so the screen opens on frame 2.
	#
	# `pause()` here did nothing to the saved scene: _sparrow sets `autoplay`, which the
	# packed scene keeps, so the bed came back cycling all three frames at 24 fps on load.
	# Clear autoplay, or the bed flickers through its own states for ever.
	var bed: AnimatedSprite2D = _sparrow("Bed", "freeplay_bed", "bed", Vector2(0.0, 254.0))
	bed.autoplay = ""
	bed.frame = 2
	bed.z_index = 2

	# shadowsOnBed is a funkin.graphics.framebuffer.FlxLayerGroup (buildBg line 1216), and
	# shakeShadows scales its matrix. Nothing is inside it yet - the shadow art rides on
	# tvNoiseBack, which is not ported - so this is an empty seat, but _resolve_nodes looks
	# it up and it has to exist. It sits between the bed and the glow in draw order.
	var shadows := Node2D.new()
	shadows.name = "ShadowsOnBed"
	shadows.z_index = 3
	shadows.visible = false          # buildBg 1219
	_add(shadows)

	# initCharacters (0x34c1800, lineas 1415-1422): el telefono del selector de skins.
	#   1415  currentPhone = new FunkinSprite(FlxG.width - 517.6, 265.9,
	#             'animania-freeplay/skinSelector/phone')
	#   1416  currentPhone.zIndex = 6
	#   1418  animation.addByPrefix('switch', 'Phone fall', 24)
	#   1419  animation.play('switch')
	#   1420  currentPhone.visible = false
	#   1422  <ratioHandler>.add(currentPhone, 0.5, 0);  shadowsOnBed.add(currentPhone)
	# Se crea invisible y NADIE dentro de FreeplayScreen lo vuelve a tocar: es el unico
	# metodo de la clase que lee el campo 0x198. Quien lo enseñe esta fuera de aqui.
	# Va colgado de ShadowsOnBed porque ahi lo mete la linea 1422, y con z absoluto: en
	# Godot el z_index de un hijo es relativo al padre salvo que se apague z_as_relative,
	# y el del mod es absoluto.
	var phone := AnimatedSprite2D.new()
	phone.name = "Phone"
	phone.sprite_frames = load("%s/freeplay_phone_frames.tres" % DIR)
	phone.animation = phone.sprite_frames.get_animation_names()[0]
	phone.centered = false
	phone.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	phone.position = Vector2(1280.0 - 517.6, 265.9) * FUNKIN_TO_RUBICON
	phone.z_index = 6
	phone.z_as_relative = false
	phone.visible = false            # initCharacters 1420
	shadows.add_child(phone)
	phone.owner = _root

	# Los dos personajes del dormitorio. Ver GF_AT / BF_AT arriba para las medidas.
	#
	# `?` La SKIN es una eleccion, no una lectura: initCharacters construye los dos con
	# 'none' y el unico changeCharacter de la clase pasa tambien 'none', asi que quien
	# pone una de verdad es el selector de personajes del juego base a traves de
	# rememberedCharacterId, y de un guardado que este proyecto no tiene. Se usa
	# bf-animania / gf-animania, que son las del mod. Con guardado, esto se cambia aqui.
	for who: Array in [["Girlfriend", "freeplay_gf", GF_AT, 4],
			["Player2", "freeplay_bf", BF_AT, 5]]:
		var sym := AnimateSymbol.new()
		sym.name = who[0] as String
		sym.atlases = [load("%s/%s_atlas.tres" % [DIR, who[1]])] as Array[AnimateAtlas]
		sym.position = (who[2] as Vector2) * FUNKIN_TO_RUBICON
		sym.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		sym.z_index = who[3] as int
		sym.z_as_relative = false
		shadows.add_child(sym)
		sym.owner = _root
		var anims := AnimationPlayer.new()
		anims.name = "Anims"
		anims.add_animation_library(&"", load("%s/%s_library.tres" % [DIR, who[1]]))
		sym.add_child(anims)
		anims.owner = _root
		anims.root_node = anims.get_path_to(sym)
		anims.autoplay = "%s_idle" % who[1]

	# El telefono del script (createPost). No es el currentPhone de initCharacters: es un
	# sparrow distinto, en (FlxG.width - 510, 300) y con zIndex 5, y su animacion 'y' NO
	# hace bucle. Nace invisible y onChangeSelection lo enseña con phone-call.
	var call_phone := AnimatedSprite2D.new()
	call_phone.name = "PhoneCallPhone"
	call_phone.sprite_frames = load("%s/freeplay_phone_frames.tres" % DIR)
	call_phone.animation = call_phone.sprite_frames.get_animation_names()[0]
	call_phone.sprite_frames.set_animation_loop(call_phone.animation, false)
	call_phone.centered = false
	call_phone.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	call_phone.position = PHONE_CALL_AT * FUNKIN_TO_RUBICON
	call_phone.z_index = 5
	call_phone.z_as_relative = false
	call_phone.visible = false
	shadows.add_child(call_phone)
	call_phone.owner = _root

	# Only tv glow's y is a constant; its x is worked out from something buildBg computes
	# earlier, and the TV's placement is not a constant at all - it is created through
	# Paths.imageGraphic and positioned by setters that read other sprites. So both x's are
	# placed rather than read, and the arithmetic says where: the wall is 912 wide in a
	# 1280 screen, which leaves 368 of nothing to the right, and the TV is 727 wide. Put
	# its right edge on the screen's, at x = 553, and it covers that gap exactly while
	# overlapping the wall by the rest. The glow is 997 wide and lands the same way.
	# buildBg deja media pantalla invisible y doIntroAnim la va encendiendo; el numero de
	# linea de cada set_visible(false) va al lado.
	var tv_glow: Sprite2D = _sprite("TvGlow", "bg/tv glow.png", Vector2(283.0, 493.0))
	tv_glow.z_index = 7
	tv_glow.visible = false          # buildBg 1236

	# La pantalla del televisor, leida de buildBg linea por linea. Todo lo de dentro
	# comparte esquina en (117, 128) y el rectangulo mide 375x305; el zIndex de cada pieza
	# sale de su `movl $N,0x28(%rax)` y es lo que decide el orden:
	#
	#   1247-1255  tvBg           createSparrow(0, 0, 'bg/TVBACK'), anim 'a' de 'pink' @24, z 10
	#   1289-1297  tvBackBG       makeGraphic(375, 305, 0xFF000000), invisible, z 20
	#   1299-1307  tvSpriteFlash  makeGraphic(375, 305, 0xFFFFFFFF), invisible, z 29
	#   1309-1317  tvNoiseBack    createSparrow(117, 128, 'bg/TVNOISE'), 'noise sprite' @24, z 26
	#   1327-1336  tvNoiseForward igual, alpha 0.45, z 28
	#   1337       tvNoiseForward.animation.onFrameChange.add(_ -> shakeShadows())
	#
	# La animacion de tvBg se llama 'a' en el mod (addByPrefix('a', 'pink')); aqui se queda
	# con el nombre del prefijo, que es como las nombra el importador de sparrow.
	#
	# El orden completo del diorama, por si hace falta: bgWall 1, bgBed 2, shadowsOnBed 3,
	# tvGlow 7, darkOverlay 8, tvBg 10, diskPlayer 16, grpDisks 19, tvBackBG 20,
	# diskPlayerMask 24, tvNoiseBack 26, albumRoll 27, tvNoiseForward 28, tvSpriteFlash 29,
	# tvSprite 30, difficultyStars 35, selectorsGroup 100, bossfightSkull 900.
	const TV_INNER := Vector2(117.0, 128.0)
	const TV_INNER_SIZE := Vector2(375.0, 305.0)

	var tv_bg: AnimatedSprite2D = _sparrow("TvBg", "freeplay_tvback", "pink", Vector2.ZERO)
	tv_bg.z_index = 10

	var tv_back_bg := _panel("TvBackBG", TV_INNER, TV_INNER_SIZE, Color(0, 0, 0, 1))
	tv_back_bg.z_index = 20
	tv_back_bg.visible = false

	var noise_back: AnimatedSprite2D = _sparrow(
		"TvNoiseBack", "freeplay_tvnoise", "noise sprite", TV_INNER)
	noise_back.z_index = 26
	noise_back.visible = false       # buildBg 1315

	var noise_forward: AnimatedSprite2D = _sparrow(
		"TvNoiseForward", "freeplay_tvnoise", "noise sprite", TV_INNER)
	noise_forward.z_index = 28
	noise_forward.modulate.a = 0.45
	noise_forward.visible = false    # buildBg 1336

	var tv_flash := _panel("TvSpriteFlash", TV_INNER, TV_INNER_SIZE, Color(1, 1, 1, 1))
	tv_flash.z_index = 29
	tv_flash.visible = false

	# El televisor NO estaba en (553, 60) ni mostraba el fotograma que toca. Esa x se habia
	# colocado por aritmetica -"el muro mide 912 de 1280, quedan 368 a la derecha y el tele
	# mide 727"- porque buildBg lo posiciona con setters en vez de con constantes. Pero las
	# piezas de DENTRO si son constantes, y son ellas las que lo fijan.
	#
	# El sparrow trae seis fotogramas en tres tamanos: 727x627 con la pantalla opaca y un
	# halo azul, y dos pares huecos de 451x473 y 466x457. buildBg hace addByPrefix('f'),
	# que casa con los seis, y luego finish() (linea 1281), que deja la animacion en el
	# ULTIMO: el 466x457, cuya pantalla es un agujero transparente. El puerto se quedaba en
	# el primero, con la pantalla tapada, y por eso nada de lo de dentro se veia.
	#
	# La posicion es la del constructor, linea 1277: new FunkinSprite(-60, -198). Cuadra
	# hasta el pixel una vez se tiene en cuenta que el sparrow viene RECORTADO: los seis
	# fotogramas declaran frameWidth 727 x frameHeight 749, y el hueco de 466x457 se pega
	# dentro de ese lienzo en (135, 288). El agujero de su pantalla va de (60, 49) a
	# (402, 326), o sea (195, 337) + 342x277 dentro del lienzo; con el sprite en (-60, -198)
	# eso cae en (135, 139)-(477, 416), justo dentro del rectangulo de (117, 128)+375x305,
	# que sobresale unos pixeles por cada lado para que el bisel redondeado no deje huecos.
	#
	# El importador de sparrow rellena los tres fotogramas al lienzo comun, asi que aqui son
	# tres de 727x749 y el hueco es el indice 2.
	const TV_FRAME := 2
	var tv: AnimatedSprite2D = _sparrow(
		"Tv", "freeplay_tv", "freeplay tv образец ", Vector2(-60.0, -198.0))
	tv.z_index = 30
	tv.visible = false               # buildBg 1282
	tv.autoplay = ""
	tv.frame = TV_FRAME

	# The VCR and the layer that goes over it, four pixels left and ten down from it.
	# `diskPlayer` en el mod, con addByPrefix('y', 'player') a 24 fps.
	var vcr: AnimatedSprite2D = _sparrow(
		"Player", "freeplay_player", "player", Vector2(50.0, 505.0))
	vcr.z_index = 16
	vcr.visible = false              # buildBg 1266
	vcr.autoplay = ""
	var vcr_layer: Sprite2D = _sprite(
		"PlayerLayer", "bg/player-layer.png", Vector2(45.75, 515.0))
	vcr_layer.z_index = 24
	vcr_layer.visible = false        # buildBg 1274

	var disks := Node2D.new()
	disks.name = "Disks"
	disks.z_index = 19
	disks.visible = false            # buildBg 1367
	_add(disks)

	var songs: Array = _root.get_script().get_script_constant_map()["SONGS"]
	for i: int in songs.size():
		var song: Dictionary = songs[i]
		var disk := Sprite2D.new()
		disk.name = "Disk%d" % i
		disk.texture = load("%s/disks/%s.png" % [ART, song["disk"]])
		# updateDisks (linea 800) escribe disk.x, y en flixel eso es el borde IZQUIERDO:
		# la fila se alinea por ahi, no por el centro, y los discos no miden todos igual.
		disk.centered = false
		disk.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		# The rect a tap has to land in, around the disk's own middle - the sprite is
		# centred, so this is too. Kept in the disk's LOCAL space so the carousel can move
		# it without the hitbox drifting.
		var size: Vector2 = disk.texture.get_size() * FUNKIN_TO_RUBICON
		disk.set_meta(&"hitbox", Rect2(Vector2.ZERO, size))
		disk.set_meta(&"index", i)
		disk.set_meta(&"target", Vector2.ZERO)
		disk.set_meta(&"scale", 1.0)
		disk.set_meta(&"alpha", 1.0)
		disks.add_child(disk)
		disk.owner = _root
		print("OUT disco %d: %s %dx%d" % [i, song["disk"], size.x, size.y])

	# The UI layer. These are the placeholders the script's _resolve_nodes() looks up; they
	# were hand-added to the scene once and this builder did not know about them, so a
	# rebuild wiped them. Anything the script resolves has to be built HERE.
	# La capa de arriba. Los zIndex ya NO son una eleccion mia: initHeader los reparte
	# entre 50 y 55 -el panel de fondo 50, helpButton/charactersButtons/clearBox 52,
	# completionText 53, freeplayScore 54, highScoreSpr 55- y esos son los que van aqui.
	#
	# Las POSICIONES en cambio siguen siendo aproximadas, y no por dejadez: initHeader no
	# usa constantes, coloca cada pieza a partir de `albumRoll.width`, de
	# `highScoreSpr.height` y de un margen de 76. Mientras albumRoll no exista en el
	# puerto -es un funkin.ui.freeplay.AlbumRoll- esas cuentas no se pueden evaluar, asi
	# que no hay numeros que leer. Lo unico literal es el 76.
	const HEADER_MARGIN := 76.0
	var ui := Node2D.new()
	ui.name = "UI"
	_add(ui)
	_label(ui, "HighScore", Rect2(1400.0, 50.0, 450.0, 40.0), "0").z_index = 54

	# Los siete digitos del marcador. Ver SCORE_AT / SCORE_STEP_X.
	var score := Node2D.new()
	score.name = "FreeplayScore"
	score.position = SCORE_AT * FUNKIN_TO_RUBICON
	score.z_index = 54
	ui.add_child(score)
	score.owner = _root
	var digit_frames: SpriteFrames = load("%s/freeplay_digits_frames.tres" % DIR)
	for i: int in SCORE_DIGITS:
		var d := AnimatedSprite2D.new()
		d.name = "Digit%d" % i
		d.sprite_frames = digit_frames
		d.animation = StringName("%s DIGITAL" % DIGIT_WORDS[0])
		d.centered = false
		d.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		d.position = Vector2(float(i) * SCORE_STEP_X, 0.0) * FUNKIN_TO_RUBICON
		d.autoplay = d.animation
		score.add_child(d)
		d.owner = _root
	var clear_box := Sprite2D.new()
	clear_box.name = "ClearBox"
	clear_box.texture = load("%s/bg/clearBox.png" % ART)
	clear_box.position = Vector2(1500.0, 100.0)
	clear_box.scale = Vector2.ONE * 0.8
	clear_box.z_index = 52
	ui.add_child(clear_box)
	clear_box.owner = _root
	# El craneo de jefe, buildBg 0x34d1170, lineas 1347-1355:
	#
	#   1347  bossfightSkull = new FunkinSprite(105, -200, ...)
	#   1348  sparrow 'animania-freeplay/bossfightIndicator'
	#   1349  animation.addByPrefix(..., 'bossfight indicator', 24)   1350  play
	#   1352  alpha = 0      1353  zIndex = 900     1354  scrollFactor.set(0, 0)
	#
	# Nace con alfa 0 y quien lo sube es updateDataStuff (linea 1132, tween de 0.1 con
	# backOut). O sea que la cancion que no es de jefe no lo esconde: es que nunca llega
	# a subirlo.
	#
	# El atlas se guarda a la MITAD de escala, asi que se dibuja al doble de lo normal
	# para salir del mismo tamano. Ver la nota de PORTING.md: la hoja original ya venia
	# empaquetada al 86% -reempaquetarla la EMPEORA, 20.8 -> 26.8 MB- y lo unico que
	# rinde aqui es la escala.
	var skull := AnimatedSprite2D.new()
	skull.name = "BossfightSkull"
	skull.sprite_frames = load("%s/freeplay_boss_frames.tres" % DIR)
	skull.animation = skull.sprite_frames.get_animation_names()[0]
	skull.centered = false
	skull.scale = Vector2.ONE * FUNKIN_TO_RUBICON / BOSS_ATLAS_SCALE
	skull.position = BOSS_AT * FUNKIN_TO_RUBICON
	skull.z_index = 900
	skull.modulate.a = 0.0            # buildBg 1352
	_add(skull)

	# buildBg 1357: bossSound = FunkinSound.load(Paths.sound('freeplay/bossIndicator'))
	# con 0.25 -el double en 0x59fa550- como volumen de partida.
	var boss_sound := AudioStreamPlayer.new()
	boss_sound.name = "BossSound"
	boss_sound.bus = &"Master"
	boss_sound.stream = load("res://animania_mod/source/sounds/freeplay/bossIndicator.ogg")
	boss_sound.volume_db = linear_to_db(BOSS_VOLUME)
	_add(boss_sound)

	# postHeader (0x34cb6e0), leido linea a linea. Ya no son posiciones aproximadas.
	#
	#   1564  songInfoCapsule.zIndex = 650      1565  scrollFactor.set(0, 0)
	#   1566  x = tvSprite.x + tvSprite.width*0.5 - capsula.width*0.5
	#   1567  y = FlxG.height - capsula.height + 1
	#   1574  las TRES etiquetas comparten x: capsula.x + capsula.width*0.5 - 153
	#   1580  y = capsula.y + 23, ancho de campo 300
	#   1576-1578  infoBpmText a la izquierda, infoTitleText al centro, infoDiffText a
	#              la derecha: es UNA caja de 300 con las tres alineaciones, no tres
	#              cajas separadas. Por eso comparten x.
	#   1586  zIndex 652
	#
	# El televisor esta en (-40, -132) del mod y su fotograma mide 727 de ancho; la
	# capsula mide 382x54. De ahi salen los numeros de abajo.
	var capsule := AnimatedSprite2D.new()
	capsule.name = "SongInfoCapsule"
	capsule.sprite_frames = load("%s/freeplay_capsule_frames.tres" % DIR)
	capsule.animation = capsule.sprite_frames.get_animation_names()[0]
	capsule.centered = false
	capsule.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	capsule.position = CAPSULE_AT * FUNKIN_TO_RUBICON
	capsule.z_index = 650
	ui.add_child(capsule)
	capsule.owner = _root

	# El grupo de puntos. Nace invisible (linea 1554); lo enciende doIntroAnim.
	var dots := Node2D.new()
	dots.name = "DotsGrp"
	dots.position = DOTS_AT * FUNKIN_TO_RUBICON
	dots.z_index = 70
	dots.visible = false
	ui.add_child(dots)
	dots.owner = _root
	var dot_texture: Texture2D = load("%s/dot.png" % ART)
	for i: int in DOT_IDS.size():
		var dot := Sprite2D.new()
		dot.name = "Dot%d" % i
		dot.texture = dot_texture
		dot.centered = false
		dot.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		# repositionDots lineas 87-91, en local al grupo.
		dot.position = Vector2(
			(float(i) - DOT_IDS.size() * 0.5) * DOT_DISTANCE, 0.0) * FUNKIN_TO_RUBICON
		# Nacen todos apagados; updateDataStuff enciende el que toque.
		dot.modulate = Color(DIFF_COLORS[DOT_IDS[i]] * DOT_DARKEN, DOT_DIM_ALPHA)
		dot.set_meta(&"diff", DOT_IDS[i])
		dots.add_child(dot)
		dot.owner = _root

	# La fila. Las tres en la misma caja de 300 de ancho, a capsula.y + 23.
	var row := Rect2(TEXT_AT * FUNKIN_TO_RUBICON,
		Vector2(TEXT_WIDTH, TEXT_HEIGHT) * FUNKIN_TO_RUBICON)
	for pair: Array in [["InfoBpm", HORIZONTAL_ALIGNMENT_LEFT],
			["InfoTitle", HORIZONTAL_ALIGNMENT_CENTER],
			["InfoDifficulty", HORIZONTAL_ALIGNMENT_RIGHT]]:
		var label := _label(ui, pair[0] as String, row, "")
		label.horizontal_alignment = pair[1] as HorizontalAlignment
		label.z_index = 652
		# `?` La fuente del mod es DS-DIGIB.TTF y NO esta en el build -no hay ni un .ttf
		# dentro-, asi que va en el ejecutable o en un empaquetado. VCR OSD Mono Cyr es
		# la sustitucion: es monoespaciada, de aire de pantalla, y cubre el cirilico que
		# lleva el arte de esta pantalla. No es la misma fuente.
		label.add_theme_font_override("font", load(TEXT_FONT))
		label.add_theme_font_size_override("font_size",
			int(TEXT_SIZE * FUNKIN_TO_RUBICON * FONT_SUBSTITUTE_NARROW))
		label.add_theme_color_override("font_color", TEXT_COLOR)
	_label(ui, "CompletionText", Rect2(1500.0, 140.0, 200.0, 40.0), "100").z_index = 53
	var stars := Node2D.new()
	stars.name = "DifficultyStars"
	stars.position = Vector2(525.0, 120.0) * FUNKIN_TO_RUBICON
	stars.z_index = 35
	ui.add_child(stars)
	stars.owner = _root
	# Los once huecos. Nacen todos en `dot`; set_difficulty enciende los que toquen.
	var star_frames: SpriteFrames = load("%s/freeplay_stars_frames.tres" % DIR)
	for i: int in STAR_COUNT:
		var star := AnimatedSprite2D.new()
		star.name = "Star%d" % i
		star.sprite_frames = star_frames
		star.animation = &"difficulty dot"
		star.centered = false
		star.scale = Vector2.ONE * FUNKIN_TO_RUBICON * STAR_SCALE
		star.position = Vector2(
			float(i) * STAR_STEP_X,
			sin(float(i) / STAR_WAVE_PERIOD) * STAR_WAVE_AMPLITUDE - STAR_WAVE_AMPLITUDE
		) * FUNKIN_TO_RUBICON
		stars.add_child(star)
		star.owner = _root
	var album := Node2D.new()
	album.name = "AlbumRoll"
	album.position = Vector2(0.0, -100.0 * FUNKIN_TO_RUBICON)
	album.z_index = 27
	ui.add_child(album)
	album.owner = _root

	# helpButton: addByIndices idle/pressed sobre `help button`, play('idle'), finish(),
	# zIndex 52 y alpha 0.4 (initHeader 1440-1453).
	var help := _ui_sparrow(ui, "HelpButton", "freeplay_help",
		Vector2(1800.0, 1000.0) - Vector2(HEADER_MARGIN, 0.0))
	help.z_index = 52
	help.modulate.a = 0.4

	# charactersButtons: lo mismo sobre `character button` (1485-1497).
	var chars := _ui_sparrow(ui, "CharactersButtons", "freeplay_characters",
		Vector2(1800.0, 1000.0) - Vector2(HEADER_MARGIN * 3.0, 0.0))
	chars.z_index = 52

	# highScoreSpr: addByPrefix('y', 'highscore small instance 1') y finish(), que lo deja
	# en el ultimo fotograma (1521-1532).
	var score_spr := _ui_sparrow(ui, "HighScoreSpr", "freeplay_highscore",
		Vector2(1400.0, 40.0))
	score_spr.z_index = 55
	score_spr.frame = score_spr.sprite_frames.get_frame_count(score_spr.animation) - 1

	# buildBg 1240-1245: color 0xFF000000, alpha 0.4, zIndex 8. El puerto lo tenia opaco y
	# el ultimo del arbol, o sea tapando el tele, los discos y el mueble entero.
	var dark := ColorRect.new()
	dark.name = "DarkOverlay"
	dark.z_index = 8
	dark.set(&"layout_mode", 0)
	dark.offset_left = -200.0
	dark.offset_top = -200.0
	dark.offset_right = 2120.0
	dark.offset_bottom = 1280.0
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.color = Color(0.0, 0.0, 0.0, 0.4)
	_add(dark)

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	# changeTheme (0x34c2540) mueve dos pistas a la vez: la base y su capa. Van al bus
	# Music, no al Master, porque son musica y el mod las carga con getPath(..., 'MUSIC').
	for track: String in ["ThemeMusic", "LayerSound"]:
		var player := AudioStreamPlayer.new()
		player.name = track
		player.bus = &"Music"
		# Las arranca changeTheme con el fundido de un segundo, no la escena.
		player.autoplay = false
		_add(player)

	_root.set(&"disks", disks)
	_root.set(&"sfx", sfx)
	_root.set(&"bed", bed)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


## makeGraphic(w, h, color): un rectangulo liso, colocado por su esquina como todo aqui.
## Genera un SpriteFrames a partir de un sparrow vendorizado. Se reconstruye siempre, sin
## comprobar si ya existe: un builder que se salta su propio trabajo cuando encuentra la
## version anterior es la trampa de siempre.
func _build_frames(source_name: String, basename: String, fps: float,
		folder: String = "bg") -> void:
	var data := SparrowImporterSpriteData.new()
	data.texture = load("%s/%s/%s.png" % [ART, folder, source_name])
	data.atlas_path = "%s/%s/%s.xml" % [ART, folder, source_name]
	data.fps = fps
	data.loop = true
	# Igual que en build_icons.gd: sparrow.gd revienta con las duraciones puestas cuando
	# hay fotogramas repetidos, y TVBACK trae doce.
	data.use_frame_duration = false
	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var frames: SpriteFrames = importer.convert_sprite([data])
	var out := "%s/%s_frames.tres" % [DIR, basename]
	var err: int = ResourceSaver.save(frames, out)
	print("OUT %s %s  %s" % ["frames" if err == OK else "FALLO", out,
		str(frames.get_animation_names())])


## Los dos botones de cabecera: un prefijo, dos animaciones sacadas por indice.
const BUTTON_IDLE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 0]
const BUTTON_PRESSED := [18]


## Un sparrow dentro de la capa de arriba, parado en su primer fotograma.
func _ui_sparrow(parent: Node, node_name: String, basename: String,
		at: Vector2) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name
	sprite.sprite_frames = load("%s/%s_frames.tres" % [DIR, basename])
	sprite.animation = sprite.sprite_frames.get_animation_names()[0]
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	sprite.position = at
	parent.add_child(sprite)
	sprite.owner = _root
	return sprite


func _build_split_frames(source_name: String, basename: String, prefix: String) -> void:
	var data := SparrowImporterSpriteData.new()
	data.texture = load("%s/%s.png" % [ART, source_name])
	data.atlas_path = "%s/%s.xml" % [ART, source_name]
	data.fps = 24.0
	data.loop = true
	data.use_frame_duration = false
	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var whole: SpriteFrames = importer.convert_sprite([data])
	if not whole.has_animation(prefix):
		print("OUT FALLO %s no tiene %s (%s)" % [source_name, prefix,
			str(whole.get_animation_names())])
		return
	var out := SpriteFrames.new()
	out.remove_animation(&"default")
	for pair: Array in [["idle", BUTTON_IDLE], ["pressed", BUTTON_PRESSED]]:
		var name := StringName(pair[0])
		out.add_animation(name)
		out.set_animation_speed(name, 24.0)
		out.set_animation_loop(name, pair[0] == "idle")
		for index: int in pair[1] as Array:
			out.add_frame(name, whole.get_frame_texture(prefix, index))
	var path := "%s/%s_frames.tres" % [DIR, basename]
	print("OUT %s %s  %s" % ["frames" if ResourceSaver.save(out, path) == OK else "FALLO",
		path, str(out.get_animation_names())])


func _panel(node_name: String, at: Vector2, size: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.set(&"layout_mode", 0)
	panel.offset_left = at.x * FUNKIN_TO_RUBICON
	panel.offset_top = at.y * FUNKIN_TO_RUBICON
	panel.offset_right = (at.x + size.x) * FUNKIN_TO_RUBICON
	panel.offset_bottom = (at.y + size.y) * FUNKIN_TO_RUBICON
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = color
	_add(panel)
	return panel


func _label(parent: Node, node_name: String, box: Rect2, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.set(&"layout_mode", 0)
	label.offset_left = box.position.x
	label.offset_top = box.position.y
	label.offset_right = box.position.x + box.size.x
	label.offset_bottom = box.position.y + box.size.y
	label.text = text
	parent.add_child(label)
	label.owner = _root
	return label


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root


## One flat piece of the diorama, placed by its top-left corner the way FunkinSprite.create
## does.
func _sprite(node_name: String, path: String, at: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = load("%s/%s" % [ART, path])
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	sprite.position = at * FUNKIN_TO_RUBICON
	_add(sprite)
	return sprite


func _sparrow(node_name: String, basename: String, animation: String,
		at: Vector2) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name
	sprite.sprite_frames = load("%s/%s_frames.tres" % [DIR, basename])
	sprite.animation = StringName(animation)
	sprite.autoplay = animation
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	sprite.position = at * FUNKIN_TO_RUBICON
	_add(sprite)
	return sprite
