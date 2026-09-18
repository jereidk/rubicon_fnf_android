# Mods del Washos Engine

El engine carga mods externos desde el almacenamiento del telefono, sin
necesidad de recompilar el APK.

Estructura
----------

Raices de mods. El engine escanea TODAS las que existan:

  user://mods  (Android/data/com.washos.engine/files/mods/)
    La app puede leer y escribir sin permisos. Es donde el engine
    instala mods que descarga por su cuenta.

  /storage/emulated/0/WashosEngine/mods
    Storage compartido. Requiere el permiso "Acceso a todos los
    archivos" (MANAGE_EXTERNAL_STORAGE), que el engine pide al arrancar
    la primera vez.

  /storage/emulated/0/.WashosEngine/mods
    Ruta historica con punto inicial. En Android 11+ suele ser
    ilegible por scoped storage, pero se intenta igual.

Si un mod con el mismo nombre esta en varias raices, gana el de la
primera raiz en esa lista. La UI avisa con un simbolo cuando hay
duplicados.

Cada mod tiene su carpeta con la estructura espejo de res://:

  WashosEngine/
    mods/
      <nombre-del-mod>/
        mod.json         <- opcional
        <archivos>       <- espejo de res://
    config/
      mods.json          <- estado (enabled/order), gestionado por la UI


Autoloads
---------

Un mod puede declarar autoloads que el engine instala al montar su .pck.
Son scripts que corren siempre, accesibles por nombre desde cualquier
otro script del mod:

  "autoloads": {
    "HQSaves": "res://holyquintet_mod/scripts/hq_saves.gd",
    "HQTransition": "res://holyquintet_mod/menus/transition/hq_transition.gd"
  }

El engine hace dos cosas al montar el .pck:
  1. Registra cada nombre en ProjectSettings (autoload/<Nombre>), para
     que el parser de GDScript acepte el identificador.
  2. Instancia el script y lo agrega a /root/<Nombre>.

Con eso, cualquier script del mod puede usar HQSaves.foo o
HQTransition.bar directo, como si fuera un autoload declarado en
project.godot.

Limitaciones:

- Si otro mod o el engine ya tienen un autoload con el mismo nombre, el
  segundo se omite con un warning. Gana el primero.
- Los autoloads se instalan al cargar el .pck y se remueven al
  desinstalar el mod. Al desactivar (no desinstalar) el .pck sigue
  montado hasta el proximo arranque, porque Godot no expone un
  unload_resource_pack: los autoloads tambien siguen instalados hasta
  reiniciar.
- Los scripts del mod se parsean cuando se carga su main_scene. Si un
  autoload se usa en un script que se preload()ea ANTES de que el .pck
  este montado, falla. En la practica no pasa, porque el .pck se monta
  al arrancar el engine y la escena se carga despues.


Estructura espejo
-----------------

Los archivos dentro de la carpeta del mod se mapean a res://<mismo-path>:

mods/holyquintet/holyquintet_mod/menus/main/main_menu.tscn
  -> res://holyquintet_mod/menus/main/main_menu.tscn

mods/holyquintet/songs/stardom/Inst.ogg
  -> res://songs/stardom/Inst.ogg

Si un archivo del mod tiene el mismo res:// que uno del APK, el del mod
PISA al del APK. Si no existe en el APK, se agrega.


mod.json
--------

El manifiesto del mod. Todos los campos son opcionales: si no existe
ningun mod.json, el engine usa el nombre de la carpeta y busca main.gd
o main.tscn como escena principal.

{
  "name": "Holy Quintet",
  "version": "1.0.7",
  "author": "jereidk",
  "description": "Mod de Madoka Magica para FNF.",
  "icon": "res://icon.png",
  "homepage": "https://github.com/jereidk/rubicon_fnf_android",
  "main_scene": "res://holyquintet_mod/menus/setup/setup_screen.tscn",
  "enabled": true
}

Campos:

- name:         nombre visible en el ModSelector y el ModManager. Si se
                omite, se usa el nombre de la carpeta.
- version:      libre. Se muestra al lado del nombre.
- author:       quien hizo el mod. Se muestra en la sub-linea y en el
                popup de detalles.
- description:  texto corto. Se muestra en una linea debajo del nombre
                (hasta 2 lineas con ellipsis) y completo en el popup.
- icon:         ruta al PNG del icono. Puede ser "res://icon.png" (que
                se resuelve al archivo fisico dentro de la carpeta del
                mod) o un nombre relativo como "icon.png". Si se omite,
                el engine busca icon.png, icon.ktx, icon.webp o icon.svg
                en la raiz de la carpeta del mod. Se carga directo desde
                disco (FileAccess + Image.load_*_from_buffer), no via
                res://, para que funcione tambien con mods desactivados
                que no tienen el .pck montado.
- homepage:     URL del mod. Se muestra en el popup.
- main_scene:   escena que arranca el engine al elegir este mod. Acepta
                .tscn o .gd. Si se omite, se autodetecta main.gd
                (prioridad) o main.tscn.
- enabled:      false para que el engine lo ignore sin borrarlo. La UI
                guarda su propio estado en config/mods.json, que gana
                sobre este campo una vez que el usuario lo toca desde el
                ModManager.


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


Funcionalidades
---------------

- Activar/desactivar mods con checkbox.
- Reordenar con flechas. El ultimo en la lista gana si dos mods pisan el
  mismo archivo.
- Desinstalar con el boton de papelera (borra carpeta + cache + entrada
  en config).
- Aviso de colisiones: dos mods activos que traen el mismo path de
  res://. Se muestra un ⚠ en la fila y un contador en el header.
- Aviso de duplicados: la misma carpeta de mod en dos raices. Se muestra
  ⊕ y se usa el de la primera raiz.
- Hot reload: al volver del background (el usuario edito un mod con el
  gestor de archivos mientras la app estaba suspendida), el ModLoader
  detecta cambios por mtime y recarga los mods automaticamente. Solo
  recarga en ModSelector o ModManager, nunca durante gameplay.
