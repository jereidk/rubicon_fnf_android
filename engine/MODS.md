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

- Imagenes: PNG, JPG, JPEG, WebP (crudos, sin .import).
- Fuentes: TTF, OTF.
- Video: OGV (Theora).
- JSON, XML, TSCN, TRES, GD.

Los archivos PNG/JPG/WebP/TTF/OTF/OGV que trae un mod se resuelven a
traves de loaders de runtime que registra ModLoader antes de montar
ningun mod. No hace falta importar nada con el editor.

NO soportado:

- MP4: Godot no trae decoder nativo. Convertir a OGV.
- GIF: no hay decoder nativo. Convertir a WebP o a spritesheet.
