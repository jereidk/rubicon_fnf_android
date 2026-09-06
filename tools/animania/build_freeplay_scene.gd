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
## buildBg 1277: `new FunkinSprite(-60, -198)`. La x del SPRITE del televisor, que no es lo
## mismo que TV_AT_X -aquella es donde empieza el arte visible dentro de su lienzo-.
const TV_SPRITE_X := -60.0
## La 1566 es `x = tvSprite.x + tvSprite.width*0.5 - capsula.width*0.5`, y ese `tvSprite`
## es el campo 0x1e0, el mismo que usa el banner de dificultad:
##
##   34cb6fb  lea 0x1e0(%rbx),%r12          <- tvSprite
##   34cbb27  movl $0x61e,-0x40(%rbp)       <- linea 1566
##   34cbb3a  movsd 0x30(%rax),%xmm3        <- tvSprite.x, el campo, no get_x()
##   34cbb55  call *0x230(%rax) / mulsd 0.5 <- + tvSprite.width * 0.5
##   34cbb9b  call *0x230(%rax) / subsd     <- - capsula.width * 0.5
##
## O sea que va con el -60, no con el -40. Con el -40 la capsula salia 20 px a la derecha,
## exactamente el mismo tropiezo que ya se corrigio en el banner. Medido contra la captura
## del mod casando el arte `bottom capsule` en las dos: esquina en x=132 en el mod y en
## x=151 en el puerto, misma escala y misma y.
const CAPSULE_AT := Vector2(
	TV_SPRITE_X + TV_WIDTH * 0.5 - CAPSULE_SIZE.x * 0.5,   # 1566
	720.0 - CAPSULE_SIZE.y + 1.0)                          # 1567
const TEXT_WIDTH := 300.0
const TEXT_HEIGHT := 40.0
const TEXT_AT := Vector2(
	CAPSULE_AT.x + CAPSULE_SIZE.x * 0.5 - 153.0,       # 1574
	CAPSULE_AT.y + 23.0)                               # 1580
const TEXT_SIZE := 28.0                                # 1585
## La fuente ES la del mod, y ya no hay sustitucion ni recorte de tamaño.
##
## Decia aqui que DS-DIGIB.TTF "no esta en el build -no hay ni un .ttf dentro-". Lo
## primero es cierto y lo segundo enganoso: no hay ficheros sueltos porque OpenFL los
## EMPOTRA en el ejecutable, y un `strings` da
## `__ASSET__assets_fonts_ds_digib_ttf_obj` junto al aviso de derechos de la propia
## tipografia. Un sfnt es autodescriptivo -cabecera 00 01 00 00, tantas tablas, y cada
## una con su desplazamiento y su tamaño-, asi que se localiza y se recorta sin adivinar
## nada: esta en 0x71c1264 y mide 25480 bytes. Su tabla `name` dice DS-Digital Bold
## Italic, que es lo que DS-DIGIB.TTF resulta ser en este mod. Es el UNICO corte de la
## familia que el binario lleva; los otros diez sfnt que hay son otras fuentes.
##
## Con la de verdad el 28 leido cabe: era la anchura de VCR OSD Mono Cyr la que obligaba
## a bajar a 20, y esa concesion -FONT_SUBSTITUTE_NARROW- se ha ido.
##
## Aviso: la tipografia es de Dusit Supasawat y su cadena de copyright dice "All Rights
## Reserved". Se vendoriza porque el mod la lleva, igual que su arte.
const TEXT_COLOR := Color8(0xcc, 0xff, 0xff)           # 1588, 0xFFCCFFFF
const TEXT_FONT := "res://animania_mod/source/fonts/DS-DIGIB.ttf"

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
## Cuantos puntos y cuantos carteles de dificultad EXISTEN no es una lista escrita a mano:
## sale de `totalDiffs`, la union de las dificultades de todas las canciones. En el mod la
## llena `loadAllAvalaibleSongs` con pushUnique (linea 491) y la consumen buildBg 1378 -un
## cartel por entrada- y postHeader 1557 -`loadDots`, un punto por entrada-. Aqui se pide
## la misma cuenta a `FreeplayScreen.total_diffs_of` para no tener dos reglas.
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
## El banner de dificultad, buildBg lineas 1378-1388. Es un BUCLE: crea un
## `new DifficultySprite(<id>)` por cada dificultad -que carga
## 'animania-freeplay/diffs/<id>text'-, los deja todos apilados en el mismo sitio y solo
## le sube el alfa a 1 (hueco 0x3a8) al que coincide con currentDifficulty.
##
##   1382  scale.set(0.95, 0.95)          1383  updateHitbox()
##   1384  x = tvSprite.x + tvSprite.width*0.5 - self.width*0.5   (0x1e0 es tvSprite)
##   1385  y = 70
##   1388  if (height > 85) offset.y += abs(height - 85)
##
## Esa ultima linea alinea por abajo los banners altos. Con los cinco que trae el mod
## ninguno pasa de 85 despues del 0.95 -el mas alto es standarttext, 89*0.95 = 84.5- asi
## que la rama no se dispara nunca y no se portea.
##
## Ni el bucle ni nada cerca le pone zIndex, asi que hereda el del estado. Va por encima
## del televisor, que es 30, porque asi sale en el mod.
const DIFF_BANNER_SCALE := 0.95
const DIFF_BANNER_Y := 70.0
const DIFF_BANNER_Z := 31

## DIEZ huecos, no once, y la onda va desfasada un hueco. Los dos salen del mismo sitio:
##
##   39de21d  movl $0x1,-0x12c(%rbp)     <- el contador NACE EN 1, no en 0
##   39de20b  movl $0x0,-0x130(%rbp)     <- la x si nace en 0
##   39de6ac  addl $0x1,-0x12c(%rbp)     i++
##   39de6b9  addl $0x28,-0x130(%rbp)    x += 40
##   39de6c0  cmp  $0xb,%eax / je fin    <- sale cuando i vale 11
##   39de6d1  divsd 3.5 / sin / *10 / -10
##
## Con i de 1 a 10 son diez vueltas, y el seno usa esa i: el hueco k (0..9) queda en
## x = 40k pero con y = sin((k+1)/3.5)*10 - 10. Confirmado contra la captura del mod, que
## es donde se vio primero: los diez centros salen en x = 129.5, 168.5 ... 489.0 -paso 40,
## el once del puerto sobraba y colgaba fuera del mueble- y las y miden 526.0, 528.9,
## 531.0, 532.6, 533.3, 533.2, 532.5, 531.0, 528.9, 526.1, que es sin((k+1)/3.5)*10-10
## clavado y NO sin(k/3.5)*10-10.
##
## Que dadbattle en hard tenga rating 11 y solo haya diez huecos no es un fallo del
## puerto: `i < rating` los enciende todos y el punto de mas no se ve, igual que en el mod.
const STAR_COUNT := 10
const STAR_STEP_X := 40.0
const STAR_WAVE_PERIOD := 3.5
const STAR_WAVE_AMPLITUDE := 10.0
## El fotograma de `difficulty star` mide 43x45 y el de `difficulty dot` 17x17. Anclando
## los dos por la esquina -que es lo que hace Flixel de serie- la estrella crece hacia
## abajo y a la derecha, y asi salia el puerto: su estrella caia en (143.0, 539.1) cuando
## la del mod esta en (129.5, 526.0), o sea 13 px a la derecha y 13 abajo. Trece y catorce
## son justo la mitad de la diferencia de tamaño entre los dos fotogramas: en el mod la
## estrella queda CENTRADA sobre el punto que sustituye.
##
## El mecanismo es `starsAnimsOffsets`, un StringMap estatico de la clase (0x80aa9c8) con
## las claves 'dot', 'star' y 'flame' que playSprAnim consulta para escribir `offset`:
##
##   39dc849  mov starsAnimsOffsets,%rsi     39dc884  StringMap::get(String)
##   39dc925  mov 0x168(%rax),%rbp           <- el `offset` del sprite
##   39dc9e7  call *0x118(%rax) / *0x120     <- set_x y set_y del punto, linea 131
##
## El __boot los crea los tres con `FlxPoint.get(null, null)`, o sea (0,0), asi que los
## valores se escriben en algun sitio que NO encontre. Lo que si esta medido es el efecto,
## y es exactamente centrar: aqui se hace con `centered` y medio fotograma de punto.
const STAR_SLOT_HALF := Vector2(8.5, 8.5)
## NO hay escala. El 0.281843 que habia aqui es un double que generateSprites carga junto
## a dos contadores de bucle, y la clase declara `fastDelayTime` y `delayTime`: es un
## RETARDO, no un tamaño. Tomarlo por escala dejaba las estrellas a 12 px cuando el
## fotograma de `difficulty star` mide 43x45 y el de `difficulty dot` 17x17.
##
## A tamaño nativo, once estrellas de 43 px con paso de 40 se tocan y forman una fila
## continua sobre el cuerpo del televisor, que es como sale en el mod.
const STAR_SCALE := 1.0
## AlbumRoll.buildAlbumTitle linea 185: scale.set(0.75, 0.75) sobre el titulo del album.
const ALBUM_TITLE_SCALE := 0.75
## initHeader 1514: completionText nace en clearBox + (12, 22).
const COMPLETION_OFFSET := Vector2(12.0, 22.0)
const COMPLETION_DIGITS := 3
## `?` El avance entre glifos de un AtlasText sale del codigo del juego base y no de
## ningun dato del build. Esto es una eleccion.
const COMPLETION_KERNING := 1.0

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
## Los tres numeros salen ya del binario y no de una medida a ojo:
##
##   initHeader 1540   new FreeplayScore(0, 61, 7, ...)   <- `mov $0x7,%edx`, xmm1 = 61
##   FreeplayScore 38  el bucle crea ScoreNum en x + 45*i  <- `add $0x2d,%ebx`
##   ScoreNum 107      setGraphicSize(Std.int(width * 0.4))
##   ScoreNum 110      color = 0xFF66FFFF
##
## O sea que cada digito va al 40% y en cian, no a tamano completo y en gris, que es como
## los tenia el puerto: siete bloques enormes que se comian media cabecera. El ancho del
## grupo -el que usa la linea 1543- es 6*45 mas el fotograma ya encogido, asi que se mide
## de la textura en vez de escribirlo.
const SCORE_DIGITS := 7
const SCORE_STEP_X := 45.0
const SCORE_DIGIT_SCALE := 0.4
const SCORE_COLOR := Color8(0x66, 0xff, 0xff)
## Y la y son 61 DOS VECES, no una. `FreeplayScore` es un FlxTypedSpriteGroup: su
## constructor (0x3532f20) llama primero a `FlxTypedSpriteGroup.__construct(x, y)` -o sea
## que el grupo queda en (0, 61)- y despues crea cada `ScoreNum(x + 45*i, y, ...)`, con la
## MISMA y, y se los anade. Y `FlxTypedSpriteGroup.preAdd` le suma al hijo la posicion del
## grupo, asi que cada digito acaba en `61 + 61 = 122`.
##
## No es una deduccion: la captura del mod sobre tutorial mide los digitos con el borde de
## arriba en y = 132 y el puerto los sacaba en 71, exactamente 61 px mas arriba. El
## HIGHSCORE, que no es un grupo, cae en su sitio con una sola y (81..120 en la captura,
## 80..121 en el puerto).
const SCORE_Y := 61.0 * 2.0
## Los prefijos del atlas, en orden de digito.
const DIGIT_WORDS := ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN",
	"EIGHT", "NINE"]

## Los dos personajes del dormitorio y el SEGUNDO telefono, el del script.
##
## initCharacters (0x34c1800) da sus dos posiciones sin ninguna duda:
##
##   1401  currentGirlfriend = new CharGirlfriend(FlxG.width - 508, 230, 'none')
##   1407  currentPlayer     = new CharPlayer(FlxG.width - 780, 235, 'none', ...)
##
## -el 508 es el `sub $0x1fc,%eax` de 0x34c188e, el 780 el `sub $0x30c` de 0x34c19ea, y
## las dos y son dobles: 230.0 en 0x59fb610 y 235.0 en 0x59fb618-. Lo que NO se puede
## deducir de ahi es donde caen los pixeles: entre esa x y el arte que se ve estan la
## `position` del JSON de la skin, el origen del simbolo de Adobe y lo que haga
## CharPlayer.loadCharacter por dentro, y nada de eso esta porteado.
##
## Asi que la colocacion se MIDE contra la captura del mod sobre tutorial, igual que se
## midio la pared y la cama en 8v. Como: char_solo.gd saca cada personaje solo sobre negro
## -que da su caja exacta en el puerto y un recorte limpio con su mascara- y match.py lo
## busca en la captura por correlacion normalizada CON MASCARA, contando solo los pixeles
## del personaje. Los dos dan el mismo resultado por separado:
##
##   bf  escala 0.910  r 0.599     gf  escala 0.910  r 0.857
##
## y con la colocacion ya corregida y la POSE CONGELADA -char_solo para el idle en el
## fotograma 0, porque el brazo de bf mueve la caja unos 20 px de un fotograma a otro y sin
## eso la medida no repite- una segunda pasada afina el resto:
##
##   bf  escala 0.990  r 0.587   caja de la captura x 647..1018  y 262..675
##   gf  escala 0.990  r 0.853   caja de la captura x 903..1232  y 240..605
##
## O sea 0.910 * 0.990 = 0.9009 en total. Dos plantillas independientes cayendo en la misma
## escala, dos veces seguidas, es lo que hace fiable esto; el alineador por bordes daba
## 1.15, 0.88 y 0.87 segun la caja que se le diera, con r de 0.23, 0.19 y 0.12.
##
## Y ESE 0.9009 IBA AL REVES. Repetida la medida sobre el render final del puerto -no sobre
## char_solo, que dibuja al personaje solo y en otro espacio, que es donde se colo el
## factor- y contra la misma captura, las dos correlaciones dan un pico limpio y unimodal
## en 1.11, no en 0.9:
##
##   bf  escala mod/puerto 1.11  r 0.794      gf  escala mod/puerto 1.10  r 0.962
##
## 1 / 1.11 = 0.9009: el mismo numero, aplicado al reves, encogiendo lo que habia que
## dejar quieto. Los personajes van a FUNKIN_TO_RUBICON pelado.
##
## A la x de la captura se le suman 7: el diorama del puerto sale 14 px a la derecha del
## de la captura -deriva de updateCameraScroll, medida sobre el televisor, los discos, la
## cabecera y las estrellas-, y los personajes cuelgan de shadowsOnBed, que initCharacters
## anade al FlxTypedRatioHandler con razon 0.5 (lineas 1404 y 1411), o sea media deriva.
##
## De ahi, con la esquina local del arte que da char_solo con la pose congelada -bf
## (-33.22, -62.45) y gf (-55.60, -52.53) respecto al nodo, a escala 1-, sale el nodo:
##
##   nodo = caja_destino - escala * esquina_local
##
## Con la escala ya en 1.0 se vuelve a medir la POSICION contra la misma captura, cada
## personaje por su cuenta y con la plantilla sacada del render final del puerto:
##
##   bf  r 0.899  el puerto lo tiene 39 px a la derecha y 58 abajo
##   gf  r 0.959  el puerto la tiene 11 px a la derecha y 60 abajo
##
## De la x hay que devolver 7.5: cmp.py corre el puerto 15 px para cancelar la deriva de
## camara del FONDO, y los personajes cuelgan de shadowsOnBed, que va en el ratio handler
## a 0.5, o sea que en el mod solo derivan la mitad. La y no lleva correccion. Que a bf le
## toquen 31.5 y a gf 3.5 -28 px de diferencia- dice que esto no es un desplazamiento
## comun del grupo sino la colocacion de cada uno, que es justo lo que se saco de la
## medida vieja con la escala equivocada.
const CHAR_SCALE := 1.0
const GF_AT := Vector2(956.6, 227.3)
const BF_AT := Vector2(652.4, 260.3)
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
	# AlbumRoll.buildAlbumTitle lineas 183-184: addByPrefix('idle', 'idle0', 24) y
	# addByPrefix('switch', 'switch0', 24) sobre el sparrow del titulo del album. El
	# importador nombra cada animacion por el prefijo sin los digitos, que da justo
	# `idle` y `switch`.
	_build_frames("animania05-text", "freeplay_album_title", 24.0, "albumRoll")
	# initHeader 1514: completionText es un AtlasText con la fuente 'freeplay-clear', que
	# no es una fuente: es un sparrow de DIEZ glifos, los digitos 0-9, de unos 25x24.
	_build_frames("freeplay-clear", "freeplay_clear", 24.0, "fonts")

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
	# La pared y la cama NO estan en x = 0, que es donde el puerto las tenia. buildBg las
	# coloca contra el borde DERECHO igual que la cabecera, y las dos cuentas estan leidas:
	#
	#   1203  bgWall.x = FlxG.width - bgWall.width - 230     -> 1280 - 912 - 230 = 138
	#   1214  bgBed.x  = FlxG.width - bgBed.width  + 10      -> 1280 - 742 +  10 = 548
	#
	# En las dos, `cvtsi2sd` sobre el entero de FlxG.width, `call *0x230` para el ancho y
	# un `subsd`/`addsd` con el literal. Con las dos en 0 la cama caia medio dormitorio a
	# la izquierda y por eso en la superposicion contra el mod los postes no cuadraban.
	const WALL_WIDTH := 912.0
	const BED_WIDTH := 742.0
	_sprite("Backwall", "bg/freeplay backwall.png",
		Vector2(1280.0 - WALL_WIDTH - 230.0, 18.75)).z_index = 1

	# The bed. Three frames that are three STATES rather than a cycle. buildBg names them
	# with addByIndices: `light` -> [0], `normal` -> [1], `none` -> [2] (the third one is
	# `none`, read out of the binary rather than guessed), and checkBed(name) plays one of
	# them. create() ends on checkBed('none'), so the screen opens on frame 2.
	#
	# `pause()` here did nothing to the saved scene: _sparrow sets `autoplay`, which the
	# packed scene keeps, so the bed came back cycling all three frames at 24 fps on load.
	# Clear autoplay, or the bed flickers through its own states for ever.
	# Linea 1206 le da la y (254) y la 1214 la x. Ver el bloque de la pared arriba.
	var bed: AnimatedSprite2D = _sparrow("Bed", "freeplay_bed", "bed",
		Vector2(1280.0 - BED_WIDTH + 10.0, 254.0))
	bed.autoplay = ""
	bed.frame = 2
	bed.z_index = 2

	# shadowsOnBed es un funkin.graphics.framebuffer.FlxLayerGroup (buildBg 1216): un grupo
	# que dibuja a sus miembros a un framebuffer y compone ese framebuffer de una vez, con
	# color 0x1C1A2F, alphaMultiplier 0.8, blend OVERLAY y un GaussianBlurShader(2.0). Y sus
	# miembros son los personajes MISMOS -initCharacters 1405, 1412 y 1423 hacen
	# `shadowsOnBed.add(...)` ADEMAS del `add()` que los pone en pantalla-, asi que cada uno
	# se dibuja dos veces: normal en su zIndex y otra por la capa, en el 3, borroso y
	# aplanado a silueta. Eso es la sombra sobre la cama.
	#
	# En Godot eso es un SubViewport: los personajes viven dentro, se dibujan UNA vez, y su
	# textura se pinta dos -en el 3 con el shader de sombra y en el 5 tal cual-. El
	# alternativo, duplicar los nodos, obligaria a mantener dos animaciones en sincronia.
	#
	# El SubViewport no hereda la transformada de camara del padre. Aqui da igual porque la
	# camara del puerto esta clavada en (960, 540) -medido con cam_probe- y no deriva como
	# la del mod; el dia que se mueva, esto hay que mirarlo.
	var chars_vp := SubViewport.new()
	chars_vp.name = "CharsViewport"
	chars_vp.size = Vector2i(int(SCREEN.x), int(SCREEN.y))
	chars_vp.transparent_bg = true
	chars_vp.disable_3d = true
	chars_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_add(chars_vp)

	# El grupo, en el zIndex 3 de la linea 1220. Nace invisible como en la 1219.
	var shadows := Sprite2D.new()
	shadows.name = "ShadowsOnBed"
	shadows.centered = false
	shadows.z_index = 3
	shadows.visible = false          # buildBg 1219
	shadows.material = ShaderMaterial.new()
	(shadows.material as ShaderMaterial).shader = load(
		"res://animania_mod/menus/freeplay/freeplay_shadows.gdshader")
	_add(shadows)

	# Y los personajes tal cual, en el zIndex del jugador. La novia va en el 4 y el
	# telefono en el 6, pero entre el 4 y el 6 no se dibuja nada mas en esa zona, asi que
	# aplanarlos en uno no cambia el orden de nada.
	var chars_view := Sprite2D.new()
	chars_view.name = "CharsView"
	chars_view.centered = false
	chars_view.z_index = 5
	chars_view.visible = false
	_add(chars_view)

	# Los dos miran a la MISMA textura del SubViewport, que es lo que hace que los
	# personajes se dibujen una sola vez. `resource_local_to_scene` es obligatorio: sin el,
	# la ruta no se resuelve al cargar la escena y la textura sale vacia.
	for target: Sprite2D in [shadows, chars_view]:
		var vp_tex := ViewportTexture.new()
		vp_tex.resource_local_to_scene = true
		vp_tex.viewport_path = _root.get_path_to(chars_vp)
		target.texture = vp_tex

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
	chars_vp.add_child(phone)
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
		sym.scale = Vector2.ONE * FUNKIN_TO_RUBICON * CHAR_SCALE
		sym.z_index = who[3] as int
		sym.z_as_relative = false
		# initCharacters construye a los dos con la skin 'none', que no dibuja nada. Quien
		# los enciende es `_change_character` cuando llega una skin de verdad.
		sym.visible = false
		chars_vp.add_child(sym)
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
	# Suelto, NO dentro del grupo: este telefono es del HScript de la pantalla (createPost),
	# no de initCharacters, asi que no entra en la capa de sombra ni se dibuja dos veces.
	_add(call_phone)

	# Only tv glow's y is a constant; its x is worked out from something buildBg computes
	# earlier, and the TV's placement is not a constant at all - it is created through
	# Paths.imageGraphic and positioned by setters that read other sprites. So both x's are
	# placed rather than read, and the arithmetic says where: the wall is 912 wide in a
	# 1280 screen, which leaves 368 of nothing to the right, and the TV is 727 wide. Put
	# its right edge on the screen's, at x = 553, and it covers that gap exactly while
	# overlapping the wall by the rest. The glow is 997 wide and lands the same way.
	# buildBg deja media pantalla invisible y doIntroAnim la va encendiendo; el numero de
	# linea de cada set_visible(false) va al lado.
	# buildBg 1233: `FunkinSprite.create(FlxG.width - 800, 493, 'bg/tv glow')`. El 800 es el
	# `sub $0x320,%eax` de 0x34cf9f0 sobre FlxG.width y el 493 el doble en 0x59fb658, o sea
	# (480, 493). Aqui ponia 283, 197 px a la izquierda, y con el brillo midiendo 997 de
	# ancho eso dejaba su nucleo en mitad de la pantalla en vez de sobre la cama: la esquina
	# de abajo a la derecha se quedaba sin el resplandor que la captura del mod si tiene.
	var tv_glow: Sprite2D = _sprite("TvGlow", "bg/tv glow.png", Vector2(480.0, 493.0))
	tv_glow.z_index = 7
	tv_glow.material = _add_blend()  # buildBg 1234
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
	noise_forward.material = _add_blend()   # buildBg 1335
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
	# halo azul, y dos pares huecos de 451x473 y 466x457. buildBg 1279 hace
	# `addByPrefix('y', 'freeplay tv образец 1', 24, false)` -el prefijo casa con los seis-
	# y luego finish() (linea 1281), que deja la animacion en el ULTIMO: el 466x457, cuya
	# pantalla es un agujero transparente. El puerto se quedaba en el primero, con la
	# pantalla tapada, y por eso nada de lo de dentro se veia.
	#
	# Esos seis fotogramas SON la animacion del encendido: doIntroAnim la relanza a los
	# 0.5 s (linea 1604) y de su onFinish cuelga introDone. El cuarto argumento de
	# addByPrefix va explicito a false, asi que no cicla; freeplay_tv_frames.tres y
	# freeplay_player_frames.tres estan a `loop: 0` por eso, y no los genera este builder
	# -son recursos versionados-, asi que si alguien los rehace hay que volver a bajarlo.
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

	# El carrusel NO empieza en la primera cancion: empieza en el disco ALEATORIO.
	#
	# generateDisksList tiene dos bloques que crean un DiskSpr, y cual es cual lo dicen sus
	# cierres, no el orden en que estan escritos: el de las lineas 519-527 cuelga el
	# `_hx_Closure_0`, cuyo `__run` llama a `capsuleOnConfirmRandom` (0x34c9d80 ->
	# 0x34c9790), y el de las 535-548 cuelga el `_hx_Closure_1`, que llama a
	# `capsuleOnConfirmDefault`. O sea: el PRIMERO es el aleatorio, creado una sola vez, y
	# el segundo es el cuerpo del bucle de canciones.
	#
	# De ahi salen los indices. La linea 523 hace `disk.ID = 0` con un inmediato -es el
	# aleatorio- y el bucle hace `disk.ID = <contador>` en 0x34d49f0 con el contador que
	# se incrementa DESPUES de meter el disco en selectableDisks. Asi que la fila es
	# [aleatorio, cancion0, cancion1, ...] y `updateDisks` -que compara `disk.ID` con
	# `curSelectedFloat`- da al aleatorio el hueco 0.
	#
	# Esto tambien explica una rama que el puerto tenia escrita y nunca ejecutaba: la de
	# updateDataStuff sin cancion (lineas 1165-1173, la que deja la cabecera en alfa
	# 0.0001). No es un caso raro, es el disco aleatorio.
	#
	# El aleatorio no lleva `songData` -init(null, null, null)-, y changeDisk con null se
	# va a su rama de la linea 117 y carga 'animania-freeplay/disks/random'.
	var songs: Array = _root.get_script().get_script_constant_map()["SONGS"]
	var carousel: Array = [{"disk": "random"}]
	carousel.append_array(songs)
	for i: int in carousel.size():
		var song: Dictionary = carousel[i]
		var disk := Sprite2D.new()
		disk.name = "DiskRandom" if i == 0 else "Disk%d" % (i - 1)
		disk.texture = load("%s/disks/%s.png" % [ART, song["disk"]])
		# CENTRADO, y no por gusto: updateDisks escribe `disk.x`, que en flixel es el borde
		# izquierdo, pero el GIRO y la ESCALA de updateDiskPos van sobre `origin`, que en
		# FlxSprite nace en el centro del fotograma. Un Sprite2D con `centered = false`
		# gira y encoge sobre su esquina, y eso desplaza el arte tanto mas cuanto mas
		# lejos este el disco del elegido -que es exactamente lo que se midio contra la
		# captura: el disco elegido clavado y los demas desviados sin que su TAMAÑO
		# cambie-. Centrando el sprite el pivote vuelve a ser el centro; a cambio la
		# posicion que se le da tiene que ser la del centro, o sea la x de flixel mas
		# medio fotograma SIN escalar, que es lo que guarda el meta `half`.
		disk.centered = true
		disk.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		disk.set_meta(&"half", disk.texture.get_size() * 0.5)
		# The rect a tap has to land in, around the disk's own middle - the sprite is
		# centred, so this is too. Kept in the disk's LOCAL space so the carousel can move
		# it without the hitbox drifting.
		var size: Vector2 = disk.texture.get_size() * FUNKIN_TO_RUBICON
		disk.set_meta(&"hitbox", Rect2(-size * 0.5, size))
		disk.set_meta(&"index", i)
		disk.set_meta(&"target", Vector2.ZERO)
		disk.set_meta(&"scale", 1.0)
		disk.set_meta(&"alpha", 1.0)
		disks.add_child(disk)
		disk.owner = _root

		# generateDisksList 535-542: `if (songData.isLocked) disk.initLock()`. initLock
		# (0x2009bc0) carga 'animania-freeplay/songs lock' y lo CENTRA sobre el disco -sus
		# lineas 69 y 70 son `x = ancho*0.5 - candado.ancho*0.5` y lo mismo con el alto-.
		if bool(song.get("locked", false)):
			var lock := Sprite2D.new()
			lock.name = "Lock"
			lock.texture = load("%s/songs lock.png" % ART)
			lock.centered = false
			# En LOCAL del disco, sin FUNKIN_TO_RUBICON: el candado es hijo suyo y la
			# escala del padre ya se la aplica Godot. Con el factor puesto el
			# desplazamiento salia 1.5 veces mayor y el candado se iba 43 px a la derecha
			# del centro, que es donde se veia el agujero rosa del disco asomando.
			#
			# Y ahora el origen del disco es su CENTRO, no su esquina, asi que centrar el
			# candado es dejarlo en menos medio candado y ya.
			lock.position = -lock.texture.get_size() * 0.5
			disk.add_child(lock)
			lock.owner = _root

		print("OUT disco %d: %s %dx%d%s" % [i, song["disk"], size.x, size.y,
			"  bloqueado" if song.get("locked", false) else ""])

	# The UI layer. These are the placeholders the script's _resolve_nodes() looks up; they
	# were hand-added to the scene once and this builder did not know about them, so a
	# rebuild wiped them. Anything the script resolves has to be built HERE.
	# La capa de arriba. Los zIndex ya no son una eleccion mia y las POSICIONES tampoco:
	# initHeader esta leida entera (lineas 1427-1543) y coloca cada pieza a partir de la
	# ANCHURA de la anterior, encadenadas de derecha a izquierda sobre una franja de 76.
	#
	#   1428-1438  <franja> makeGraphic(1,1,0xFF000000); scale.set(FlxG.width, 76);
	#              updateHitbox(); screenCenter(); y = 0; scrollFactor.set(0,0); z 50
	#   1450       helpButton.x        = FlxG.width - helpButton.width - 7
	#   1451       helpButton.y        = 76 - helpButton.height - 1
	#   1494       charactersButtons.x = helpButton.x - charactersButtons.width - 13
	#   1495       charactersButtons.y = 76 - charactersButtons.height - 3
	#   1506       clearBoxSprite      = FunkinSprite.create(0, 76, '.../bg/clearBox')
	#   1510       clearBoxSprite.x    = FlxG.width - clearBoxSprite.width
	#   1514       completionText      = new AtlasText(clearBox.x + 12, clearBox.y + 22,
	#                                                  '100', 'freeplay-clear')
	#   1516       completionText.zoomFactor = 0        1517  z 53
	#   1529       highScoreSpr.x      = clearBox.x - highScoreSpr.width - 5
	#   1530       highScoreSpr.y      = clearBox.y + clearBox.height * 0.5
	#                                    - highScoreSpr.height * 0.5
	#   1540-1543  freeplayScore = new FreeplayScore(..., 61, ...);
	#              freeplayScore.x = FlxG.width - freeplayScore.width + 5
	#
	# El 76 de las lineas 1430/1451/1495 es el MISMO numero: la altura de la franja negra.
	# Los "widths" son los del sparrow ya cargado, asi que aqui se miden de la textura en
	# vez de escribirse a mano; `_frame_size` es eso.
	#
	# Antes decia que estas cuentas no se podian evaluar "mientras albumRoll no exista".
	# Eso era un error de lectura: initHeader no menciona albumRoll ni una vez.
	const HEADER_HEIGHT := 76.0
	var ui := Node2D.new()
	ui.name = "UI"
	_add(ui)

	# Lineas 1428-1438. Una franja negra opaca de 1280x76 pegada arriba, y todo lo demas
	# de la cabecera va encima (z 52 a 55 contra su 50).
	var header_bar := ColorRect.new()
	header_bar.name = "HeaderBar"
	header_bar.set(&"layout_mode", 0)
	header_bar.offset_left = 0.0
	header_bar.offset_top = 0.0
	header_bar.offset_right = 1280.0 * FUNKIN_TO_RUBICON
	header_bar.offset_bottom = HEADER_HEIGHT * FUNKIN_TO_RUBICON
	header_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_bar.color = Color(0.0, 0.0, 0.0, 1.0)
	header_bar.z_index = 50
	ui.add_child(header_bar)
	header_bar.owner = _root

	# Los siete digitos del marcador. Ver SCORE_DIGITS / SCORE_DIGIT_SCALE arriba.
	var digit_frames: SpriteFrames = load("%s/freeplay_digits_frames.tres" % DIR)
	var digit_w: float = _frame_size("freeplay_digits").x * SCORE_DIGIT_SCALE
	var score_width: float = (SCORE_DIGITS - 1) * SCORE_STEP_X + digit_w
	var score := Node2D.new()
	score.name = "FreeplayScore"
	score.position = Vector2(1280.0 - score_width + 5.0, SCORE_Y) * FUNKIN_TO_RUBICON
	score.z_index = 54
	ui.add_child(score)
	score.owner = _root
	for i: int in SCORE_DIGITS:
		var d := AnimatedSprite2D.new()
		d.name = "Digit%d" % i
		d.sprite_frames = digit_frames
		d.animation = StringName("%s DIGITAL" % DIGIT_WORDS[0])
		d.centered = false
		d.scale = Vector2.ONE * FUNKIN_TO_RUBICON * SCORE_DIGIT_SCALE
		d.modulate = SCORE_COLOR
		d.position = Vector2(float(i) * SCORE_STEP_X, 0.0) * FUNKIN_TO_RUBICON
		d.autoplay = d.animation
		score.add_child(d)
		d.owner = _root
	print("OUT marcador: digito %.1f  ancho %.1f  x %.1f"
		% [digit_w, score_width, 1280.0 - score_width + 5.0])
	# Lineas 1506-1510: la caja de CLEARED. Su y sale del constructor -76, o sea justo
	# debajo de la franja- y su x del borde derecho menos su propia anchura.
	var clear_box := Sprite2D.new()
	clear_box.name = "ClearBox"
	clear_box.texture = load("%s/bg/clearBox.png" % ART)
	var clear_size: Vector2 = clear_box.texture.get_size()
	var clear_at := Vector2(1280.0 - clear_size.x, HEADER_HEIGHT)
	clear_box.centered = false
	clear_box.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	clear_box.position = clear_at * FUNKIN_TO_RUBICON
	clear_box.z_index = 52
	ui.add_child(clear_box)
	clear_box.owner = _root

	# Lineas 1514-1517: el porcentaje. No es una etiqueta: es un AtlasText sobre
	# 'freeplay-clear', que son diez glifos de digito de unos 25x24 y NADA MAS -no hay
	# signo de porcentaje ni letras en ese atlas-. Tres huecos, que es lo que cabe en
	# 0-100, colocados por su propia anchura en tiempo de ejecucion.
	#
	# `?` El avance entre glifos de un AtlasText de Funkin sale de una tabla que vive en
	# el codigo del juego base, no en ningun dato del build. Aqui cada digito avanza su
	# propia anchura mas COMPLETION_KERNING, que es una eleccion.
	var completion := Node2D.new()
	completion.name = "CompletionText"
	completion.position = (clear_at + COMPLETION_OFFSET) * FUNKIN_TO_RUBICON
	completion.z_index = 53
	ui.add_child(completion)
	completion.owner = _root
	# Los diez glifos se llaman "00000".."90000" y el importador los nombra por el prefijo
	# sin los digitos finales, o sea "" para los diez: salen como UNA animacion de diez
	# fotogramas en orden. Eso deja el indice de fotograma igual al digito, que es justo
	# lo que hace falta.
	var clear_frames: SpriteFrames = load("%s/freeplay_clear_frames.tres" % DIR)
	var clear_names: PackedStringArray = clear_frames.get_animation_names()
	for i: int in COMPLETION_DIGITS:
		var d := AnimatedSprite2D.new()
		d.name = "Digit%d" % i
		d.sprite_frames = clear_frames
		d.animation = StringName(clear_names[0])
		d.autoplay = ""
		d.frame = 0
		d.centered = false
		d.visible = false
		d.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		completion.add_child(d)
		d.owner = _root
	print("OUT clearBox %dx%d en (%d, %d)  glifos=%s"
		% [clear_size.x, clear_size.y, clear_at.x, clear_at.y, str(clear_names)])
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

	# Los banners de dificultad, apilados y centrados sobre el televisor. buildBg 1378
	# recorre `totalDiffs`, asi que son tantos como dificultades ofrezca el catalogo.
	var banners := Node2D.new()
	banners.name = "DifficultyBanners"
	ui.add_child(banners)
	banners.owner = _root
	for id: String in _diff_ids():
		var b := Sprite2D.new()
		b.name = "Diff_%s" % id
		b.texture = load("%s/diffs/%stext.png" % [ART, id])
		b.centered = false
		b.scale = Vector2.ONE * FUNKIN_TO_RUBICON * DIFF_BANNER_SCALE
		# buildBg 1384: `banner.x = tvSprite.x + tvSprite.width * 0.5 - banner.width * 0.5`.
		# El `tvSprite.x` es el -60 literal de la linea 1277, no el TV_AT_X de -40 que se
		# usa para colocar la capsula y los puntos: aquello es una medida del arte, esto es
		# la x del sprite. Con -40 el banner salia 20 px a la derecha.
		var w: float = b.texture.get_width() * DIFF_BANNER_SCALE
		b.position = Vector2(
			TV_SPRITE_X + TV_WIDTH * 0.5 - w * 0.5, DIFF_BANNER_Y) * FUNKIN_TO_RUBICON
		b.z_index = DIFF_BANNER_Z
		b.z_as_relative = false
		b.modulate.a = 0.0
		b.set_meta(&"diff", id)
		banners.add_child(b)
		b.owner = _root

	# El grupo de puntos. Nace invisible (linea 1554); lo enciende doIntroAnim.
	var dots := Node2D.new()
	dots.name = "DotsGrp"
	dots.position = DOTS_AT * FUNKIN_TO_RUBICON
	dots.z_index = 70
	dots.visible = false
	ui.add_child(dots)
	dots.owner = _root
	var dot_texture: Texture2D = load("%s/dot.png" % ART)
	var dot_ids: PackedStringArray = _diff_ids()
	for i: int in dot_ids.size():
		var dot := Sprite2D.new()
		dot.name = "Dot%d" % i
		dot.texture = dot_texture
		dot.centered = false
		dot.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		# repositionDots lineas 87-91, en local al grupo.
		dot.position = Vector2(
			(float(i) - dot_ids.size() * 0.5) * DOT_DISTANCE, 0.0) * FUNKIN_TO_RUBICON
		# Nacen todos apagados; updateDataStuff enciende el que toque.
		dot.modulate = Color(DIFF_COLORS[dot_ids[i]] * DOT_DARKEN, DOT_DIM_ALPHA)
		dot.set_meta(&"diff", dot_ids[i])
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
		# La DS-DIGIB.TTF del mod, sacada del ejecutable. Ver TEXT_FONT.
		label.add_theme_font_override("font", load(TEXT_FONT))
		label.add_theme_font_size_override("font_size",
			int(TEXT_SIZE * FUNKIN_TO_RUBICON))
		label.add_theme_color_override("font_color", TEXT_COLOR)
	# `CompletionText` ya no se crea aqui: la etiqueta inventada de (1500, 140) se ha ido y
	# en su sitio esta el AtlasText de tres digitos que cuelga de la caja de CLEARED, con
	# la posicion que da initHeader 1514. Dos nodos con el mismo nombre y Godot renombra
	# uno en silencio, que es como esta etiqueta seguia pintando su "100" en blanco.
	var stars := Node2D.new()
	stars.name = "DifficultyStars"
	# EJES CAMBIADOS. Esto decia (525, 120) y era invencion del builder viejo que nunca
	# comprobe. buildBg linea 1340 hace `new DifficultyStars(120, 525)`: el 120.0 esta en
	# 0x59faf28 y va en xmm0 (la x), el 525.0 en 0x59fb1f8 y va en xmm1 (la y). O sea que
	# la fila va ABAJO A LA IZQUIERDA, sobre el cuerpo del televisor y bajo su pantalla,
	# que es donde sale en el mod. Con los ejes cambiados aparecia arriba del todo.
	stars.position = Vector2(120.0, 525.0) * FUNKIN_TO_RUBICON
	stars.z_index = 35
	ui.add_child(stars)
	stars.owner = _root
	# Los diez huecos. Nacen todos en `dot`; set_difficulty enciende los que toquen.
	var star_frames: SpriteFrames = load("%s/freeplay_stars_frames.tres" % DIR)
	for i: int in STAR_COUNT:
		var star := AnimatedSprite2D.new()
		star.name = "Star%d" % i
		star.sprite_frames = star_frames
		star.animation = &"difficulty dot"
		# Centrado, no anclado por la esquina: ver STAR_SLOT_HALF. El punto y la estrella
		# tienen fotogramas de distinto tamaño y en el mod comparten centro.
		star.centered = true
		star.scale = Vector2.ONE * FUNKIN_TO_RUBICON * STAR_SCALE
		star.position = (Vector2(
			float(i) * STAR_STEP_X,
			sin(float(i + 1) / STAR_WAVE_PERIOD) * STAR_WAVE_AMPLITUDE - STAR_WAVE_AMPLITUDE
		) + STAR_SLOT_HALF) * FUNKIN_TO_RUBICON
		stars.add_child(star)
		star.owner = _root
	# ─── La caratula del televisor: funkin.ui.freeplay.AlbumRoll ────────────────
	#
	# El mod NO trae copia propia de esta clase -grep de `animania::...::AlbumRoll_obj`
	# da cero-, asi que la que corre es la del juego base con las lineas que Animania le
	# metio encima. buildBg 1319-1325 la coloca:
	#
	#   1319  albumRoll = new AlbumRoll()
	#   1320  albumRoll.y = -100            <- solo la y; la x se queda en 0
	#   1321  albumRoll.albumId = 'animania05'
	#   1322  albumRoll.zIndex = 27
	#   1323  albumRoll.scrollFactor.set(0, 0)
	#   1324  albumRoll.<blur>.amount = 0.1
	#   1325  add(albumRoll)
	#
	# Y el constructor de AlbumRoll (lineas 50-56):
	#
	#   52  albumArt = FunkinSprite.createTextureAtlas('animania-freeplay/albumRoll/roll')
	#   53  albumArt.visible = false
	#   54  albumArt.onAnimationFinish.add(onAlbumFinish)
	#   55  albumArt.offset.set(-190, -250)
	#   56  add(albumArt)
	#
	# Flixel dibuja en `x - offset.x`, o sea que ese offset negativo EMPUJA la caratula
	# 190 a la derecha y 250 abajo dentro del grupo. Aqui va como posicion local, que es
	# lo mismo con un solo sprite dentro.
	#
	# updateAlbum (lineas 78-94) es lo que hace que la caratula sea la de este mod:
	# lee assets/data/ui/freeplay/albums/animania05.json, saca `albumArtAsset` y hace
	# `albumArt.replaceFrameGraphic('mini album', Paths.imageGraphic(...))`. El atlas
	# `roll` trae UN simbolo, `mini album`, y su spritemap es la portada de OTRO album
	# -"MINI EXPANSION VOL.1"-, que en el juego no se ve nunca porque se sustituye al
	# vuelo por animania05.png. El vendorizado hace esa sustitucion de una vez: el
	# spritemap1.png del puerto ES animania05.png pegado en (1,1), que es donde el
	# spritemap1.json pone su unico recorte.
	var album := Node2D.new()
	album.name = "AlbumRoll"
	album.position = Vector2(0.0, -100.0) * FUNKIN_TO_RUBICON
	album.z_index = 27
	ui.add_child(album)
	album.owner = _root

	# La composicion `ALBUM ALL4` son nueve fotogramas con tres etiquetas en su linea de
	# tiempo -intro 0-2, switch 3-5, idle 6-8-, no tres simbolos. Por eso la libreria se
	# genera con tramos (ver build_adobe_character.gd). Nace invisible: la enciende
	# playIntro al final de doIntroAnim.
	var art := AnimateSymbol.new()
	art.name = "AlbumArt"
	art.atlases = [load("%s/freeplay_album_atlas.tres" % DIR)] as Array[AnimateAtlas]
	art.position = Vector2(190.0, 250.0) * FUNKIN_TO_RUBICON
	art.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	art.visible = false              # AlbumRoll 53
	album.add_child(art)
	art.owner = _root
	var art_anims := AnimationPlayer.new()
	art_anims.name = "Anims"
	art_anims.add_animation_library(&"", load("%s/freeplay_album_library.tres" % DIR))
	art.add_child(art_anims)
	art_anims.owner = _root
	art_anims.root_node = art_anims.get_path_to(art)

	# buildAlbumTitle (lineas 181-187): createSparrow(425, 200, <albumTitleAsset>),
	# visible = false, las dos animaciones, scale.set(0.75, 0.75) y updateHitbox(). Ese
	# updateHitbox es lo que deja la esquina quieta: recoloca el offset justo lo que el
	# origen centrado encoge, asi que el arte sigue empezando en (425, 200) y no hay que
	# compensar nada al portarlo.
	var title := AnimatedSprite2D.new()
	title.name = "AlbumTitle"
	title.sprite_frames = load("%s/freeplay_album_title_frames.tres" % DIR)
	title.animation = &"idle"
	title.autoplay = &"idle"          # buildAlbumTitle 194
	title.centered = false
	title.position = Vector2(425.0, 200.0) * FUNKIN_TO_RUBICON
	title.scale = Vector2.ONE * FUNKIN_TO_RUBICON * ALBUM_TITLE_SCALE
	title.visible = false            # buildAlbumTitle 182
	# buildAlbumTitle 196: `movl $0x3e8,0x28(%r13)` -> zIndex 1000, y en la misma linea el
	# shader de desenfoque. Ese 1000 ordena DENTRO del grupo -refresh() ordena sus
	# miembros por zIndex- y no saca la caratula del zIndex 27 del grupo, asi que el
	# frontal del televisor (zIndex 30) le sigue pasando por delante. Aqui el orden de
	# hermanos hace lo mismo: el titulo despues del arte.
	album.add_child(title)
	title.owner = _root

	# helpButton: addByIndices idle/pressed sobre `help button`, play('idle'), finish(),
	# zIndex 52 y alpha 0.4 (initHeader 1440-1453). Su sitio son las lineas 1450-1451:
	# pegado al borde derecho menos 7, y apoyado en la base de la franja menos 1.
	var help_size: Vector2 = _frame_size("freeplay_help")
	var help_at := Vector2(1280.0 - help_size.x - 7.0,
		HEADER_HEIGHT - help_size.y - 1.0)
	var help := _ui_sparrow(ui, "HelpButton", "freeplay_help",
		help_at * FUNKIN_TO_RUBICON)
	help.z_index = 52
	help.modulate.a = 0.4

	# charactersButtons: lo mismo sobre `character button` (1485-1497). Lineas 1494-1495:
	# a la IZQUIERDA del boton de ayuda, 13 de hueco, y 3 sobre la base en vez de 1.
	var chars_size: Vector2 = _frame_size("freeplay_characters")
	var chars_at := Vector2(help_at.x - chars_size.x - 13.0,
		HEADER_HEIGHT - chars_size.y - 3.0)
	var chars := _ui_sparrow(ui, "CharactersButtons", "freeplay_characters",
		chars_at * FUNKIN_TO_RUBICON)
	chars.z_index = 52
	# Y NO SE VE. Esto no sale del binario, sale de dos capturas del mod: en la del disco
	# aleatorio y en la de tutorial la esquina de arriba a la derecha tiene el boton de
	# ayuda -gris, con su alfa 0.4 de la linea 1449- y a su izquierda, donde este boton
	# tendria que estar, negro.
	#
	# Lo comprobado, y ninguno lo explica: initHeader 1485-1497 lo crea con zIndex 52 -el
	# mismo que el de ayuda- y en esas lineas no hay ni un `set_alpha` (hueco 0x3a8) ni un
	# `set_visible` (0x128); su hoja `characters.png` tiene las seis poses dibujadas, o sea
	# que el fotograma no esta en blanco; su x sale de `helpButton.x - ancho - 13`, que cae
	# dentro de la pantalla; y todas las lecturas del campo 0x1a8 en la clase estan en
	# initHeader o en los metodos de reflexion.
	#
	# Asi que se deja construido -con su sitio y su animacion, para el dia que se entienda-
	# pero apagado, porque la captura manda sobre una lectura incompleta del codigo.
	chars.visible = false

	# highScoreSpr: addByPrefix('y', 'highscore small instance 1') y finish(), que lo deja
	# en el ultimo fotograma (1521-1532). Lineas 1529-1530: a la izquierda de la caja de
	# CLEARED con 5 de hueco, y CENTRADO en vertical contra esa caja.
	var spr_size: Vector2 = _frame_size("freeplay_highscore")
	var spr_at := Vector2(clear_at.x - spr_size.x - 5.0,
		clear_at.y + clear_size.y * 0.5 - spr_size.y * 0.5)
	var score_spr := _ui_sparrow(ui, "HighScoreSpr", "freeplay_highscore",
		spr_at * FUNKIN_TO_RUBICON)
	score_spr.z_index = 55
	score_spr.frame = score_spr.sprite_frames.get_frame_count(score_spr.animation) - 1
	print("OUT cabecera: help %s  chars %s  highscore %s (%dx%d)"
		% [str(help_at), str(chars_at), str(spr_at), spr_size.x, spr_size.y])

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
## El tamano LOGICO de un fotograma de un sparrow ya generado. initHeader coloca media
## cabecera restando `sprite.width`, y en Flixel eso es el fotograma con su recorte
## deshecho; el importador de sparrow rellena cada fotograma hasta ese lienzo, asi que la
## textura mide justo lo que mide el `width` del mod.
## `totalDiffs`: la union de las dificultades de todas las canciones, en el orden en que
## SONGS las lista. La regla vive en freeplay_screen.gd y aqui solo se le pregunta.
func _diff_ids() -> PackedStringArray:
	var script: Script = _root.get_script()
	var songs: Array = script.get_script_constant_map()["SONGS"]
	return script.total_diffs_of(songs)


## `set_blend` es el hueco 0x3b8 de la vtabla de FlxSprite -resuelto leyendo la vtabla de
## FunkinSprite y mirando a donde apunta ese hueco-, y buildBg lo llama TRES veces:
##
##   1234  tvGlow.blend         = Dynamic(0)     -> ADD
##   1242  darkOverlay.blend    = Dynamic(11)    -> OVERLAY   (negro, zIndex 8)
##   1335  tvNoiseForward.blend = Dynamic(0)     -> ADD
##
## El indice sale del abstract `openfl.display.BlendMode`, que numera sus valores por orden
## alfabetico: ADD 0, ALPHA 1, ... NORMAL 10, OVERLAY 11. Y no se queda en la deduccion: con
## el ruido de delante en aditivo el tubo del puerto pasa de 105.3 a 129.3 de luma, y la
## captura del mod sobre el disco aleatorio mide 122.5. Eso cierra un hilo que llevaba
## abierto desde 8s -"el tubo del puerto sale unos 27 de luma mas oscuro"- y de paso
## confirma el 0.
##
## El de darkOverlay no se portea: Godot no trae mezcla OVERLAY en CanvasItemMaterial y
## haria falta un shader, y esa capa solo pinta durante el encendido -doIntroAnim 1639 la
## lleva a alfa 0 en 0.65 s- asi que no cambia nada de lo que se ve en reposo. Anotado.
static func _add_blend() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func _frame_size(basename: String) -> Vector2:
	var frames: SpriteFrames = load("%s/%s_frames.tres" % [DIR, basename])
	var anim: StringName = StringName(frames.get_animation_names()[0])
	return frames.get_frame_texture(anim, 0).get_size()


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
