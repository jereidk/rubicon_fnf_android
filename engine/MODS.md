# Mods del Rubicon Engine

El engine carga mods externos desde el almacenamiento del telefono, sin
necesidad de recompilar el APK.

## Estructura

cd ~/rubicon_fnf_android
cat > engine/MODS.md << 'MDEOF'
Mods del Rubicon Engine
=======================

El engine carga mods externos desde el almacenamiento del telefono, sin
necesidad de recompilar el APK.


Estructura
----------

/storage/emulated/0/.RubiconEngine/
  mods/
    <nombre-del-mod>/
      mod.json         <- manifiesto obligatorio
      <archivos>       <- estructura espejo de res://
  config/
    mods_order.txt     <- opcional


mod.json
--------

{
  "name": "Holy Quintet",
  "version": "1.0.7",
  "main_scene": "res://holyquintet_mod/menus/setup/setup_screen.tscn",
  "enabled": true
}

- name: nombre visible en el selector.
- version: libre, se muestra en logs.
- main_scene: escena que arranca el engine al elegir este mod.
- enabled: false para que el engine lo ignore sin borrarlo.


Estructura espejo
-----------------

Los archivos dentro de la carpeta del mod se mapean a res://<mismo-path>:

mods/holyquintet/holyquintet_mod/menus/main/main_menu.tscn
  -> res://holyquintet_mod/menus/main/main_menu.tscn

mods/holyquintet/songs/stardom/Inst.ogg
  -> res://songs/stardom/Inst.ogg

Si un archivo del mod tiene el mismo res:// que uno del APK, el del mod
PISA al del APK. Si no existe en el APK, se agrega.


mods_order.txt
--------------

Una carpeta por linea. Los mods se cargan en ese orden, y el ULTIMO gana
si dos mods traen el mismo archivo. Los mods que no aparecen en el archivo
se agregan al final en orden alfabetico.

# Orden de carga:
holyquintet
otro_mod


Cache
-----

El engine empaqueta cada mod a user://mods_cache/<nombre>.pck la primera
vez, y solo lo regenera si algun archivo del mod cambio (comparando mtime).
La primera carga de un mod pesado puede tardar unos segundos; las
siguientes son instantaneas.


Sin mods
--------

Si la carpeta esta vacia, el engine arranca songs/test/test.tscn, que es
la demo incluida.

Formatos soportados
-------------------

Los mods pueden incluir:

- Imagenes: PNG, JPG, JPEG, WebP, SVG (crudos, sin .import).
- Imagenes comprimidas: .ktx y .astc (ver nota abajo).
- Modelos 3D: .glb y .gltf (Godot los carga directo, sin editor).
- Fuentes: TTF, OTF.
- Video: OGV (Theora).
- Audio: OGG Vorbis, MP3, WAV.
- JSON, XML, TSCN, TRES, GD.

Los archivos PNG/JPG/WebP/TTF/OTF/OGV que trae un mod se resuelven a
traves de loaders de runtime que registra ModLoader antes de montar
ningun mod. No hace falta importar nada con el editor.

Nota sobre .astc y .ktx
-----------------------

Godot no tiene una funcion load_astc_from_buffer(), pero SI
load_ktx_from_buffer(), y el KTX es el contenedor estandar que puede
llevar ASTC adentro. Por eso:

1. Un mod puede traer texturas ASTC comprimidas con el nombre .astc
   (por comodidad), pero el archivo tiene que ser un KTX real con ASTC
   adentro. El loader acepta .astc y .ktx indistintamente.

2. Para generar el archivo con astcenc:

     astcenc -cl input.png output.ktx 6x6
     mv output.ktx output.astc

   El 6x6 es el block size (menos = mas calidad y mas peso). Los mas
   comunes son 4x4 (maxima calidad), 6x6 (balance), 8x8 (maxima
   compresion).

3. Si el mod no necesita compresion ASTC, use PNG/WebP directo. La
   compresion ASTC es para ahorrar VRAM en runtime, a costa de
   calidad y de un paso extra de build.


Modelos 3D
-----------

Un mod puede traer modelos glTF crudos y cargarlos directo:

    mods/mimod/
      main.gd
      models/
        personaje.glb
        escenario.gltf

En el codigo:

    var scene = load("res://models/personaje.glb")
    var node = scene.instantiate()
    add_child(node)

- .glb empaqueta todo (mallas, texturas, materiales) en un solo archivo.
  Es lo recomendado para mods porque no depende de archivos externos.
- .gltf es texto y referencia texturas externas por ruta relativa. Si tu
  modelo usa .gltf, copia tambien las texturas y respetá las rutas.

NO hace falta importar con el editor. Godot 4 registra GLTFDocument y
GLTFState en runtime (verificado en 4.7.1-stable), asi que el engine los
carga desde el .pck como cualquier otro recurso.


NO soportado:

- MP4: Godot no trae decoder nativo. Convertir a OGV.
- GIF: no hay decoder nativo. Convertir a WebP o a spritesheet.
- .astc crudo (sin contenedor KTX): Godot no expone esa API. Usar
  KTX renombrado a .astc segun la convencion de arriba.
