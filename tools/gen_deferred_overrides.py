#!/usr/bin/env python3
"""Genera *_shop.tscn como una INSTANCIA de su escena fuente con overrides.

Por que existe, y por que reemplaza a tools/extract_console_scene.gd
--------------------------------------------------------------------
La primera version de la consola diferida se saco con `PackedScene.pack()`
sobre el subarbol vivo. Eso produce un fichero APLANADO de 1,26 MB, y sobre una
escena que contiene subescenas instanciadas `pack()` no es fiable. Cuatro clases
de dano silencioso, medidas:

  1. Un NodePath que sale del subarbol no se puede serializar, asi que se
     escribe `NodePath("")` sin avisar. Corto seis cables.
  2. El estado EN VIVO se serializa como si fuera autoria: dos
     `animation = &""` que hacian petar set_animation al instanciar.
  3. Los hijos de cada subescena instanciada se reescriben SIN `index=`, y sin
     `index` Godot no los trata como override sino como hijos NUEVOS. La
     instancia crea los suyos y el fichero anade otros encima:

         console.tscn       382 nodos    0 padres con hijos repetidos
         console_shop.tscn  582 nodos   43 padres,  68 hijos sobrantes

     En la practica, dos marcas de verificacion dibujadas una sobre otra en cada
     toggle de la consola, las dos con autoplay.
  4. Y de ahi 200 nodos de mas, que alimentan el tiron del montaje:
     `console montada en diferido (515 nodos) proc=1757.82ms` en el log del g53.

La verificacion de la herramienta anterior no podia cogerlo: comparaba el arbol
vivo contra si mismo, no contra una reinstanciacion de su propia salida.

Lo que hace esto en su lugar
----------------------------
Nada de aplanar. Escribe el fichero que el .tscn de la tienda ya tenia, menos la
tienda: una instancia de console.tscn con los 21 bloques de override encima, con
su `index=` intacto. Los aplica Godot con su propio mecanismo, que es el unico
que los entiende. Pasa de 1,26 MB a unas 80 lineas.

Los overrides se leen del .tscn de la tienda de ANTES de sacar la consola
(1dcde58b~1), no de la memoria de nadie.

Lo unico que este fichero NO puede llevar son los seis NodePath que apuntan
fuera de la consola - tres en la raiz y tres dentro. Siguen siendo imposibles de
expresar, y siguen siendo trabajo de console_deferred_loader.gd; se quitan aqui
a proposito y la lista esta abajo.

Uso:
  python3 tools/gen_deferred_overrides.py <shop_antes.tscn> console|kollectadex <salida.tscn>
  (shop_antes.tscn = git show 1dcde58b~1:lullaby_mod/rooms/env_collector_shop.tscn,
   que es anterior a las DOS extracciones y por tanto las tiene inline)
"""

import re
import sys

# Las dos escenas diferidas: donde vivian en el .tscn de la tienda, como se
# llamaba su nodo raiz, y de que escena son instancia.
TARGETS = {
    "console": (
        "Viewports/ConsoleSubViewport/Console",
        "Console",
        "res://lullaby_mod/resources/console/console.tscn",
    ),
    "kollectadex": (
        "Viewports/KollectadexSubViewport/Kollectadex",
        "Kollectadex",
        "res://lullaby_mod/resources/kollectadex/kollectadex.tscn",
    ),
}

# Los NodePath que salen de la escena diferida. No se pueden escribir en el
# fichero - apuntan a nodos de la tienda, que aqui no existen - y los pone el
# cargador correspondiente.
CROSS_BOUNDARY = {
    # consola
    "shop", "sequences", "focus_right_area",   # en la raiz
    "bag_area", "handler",                     # TabContainer/Home/FakeButtons/Cartridges
    "collector_shop",                          # TabContainer/Cartridges/EnterLabel
    # kollectadex
    "focus_left_area", "kollectadex_anims",    # PanelContainer/Kollectadex
}


def main() -> int:
    src, which, out = sys.argv[1], sys.argv[2], sys.argv[3]
    prefix, root_name, source_scene = TARGETS[which]
    txt = open(src, encoding="utf-8").read()

    # Las declaraciones ext_resource de la tienda vieja, para poder traer las
    # que un override use. El kollectadex tiene una - `character.texture` - y la
    # primera version de esto la escribia como `ExtResource("191")`, un id de
    # OTRA escena, que aqui no resuelve. No es hipotetico: paso.
    src_ext = {}
    for line in txt.split("\n"):
        if not line.startswith("[ext_resource "):
            break_ok = True
        m = re.match(r'\[ext_resource (.*) id="([^"]+)"\]', line)
        if m:
            src_ext[m.group(2)] = m.group(1).rstrip()

    body_blocks = []
    used_ext = {}          # id viejo -> id nuevo

    kept = dropped = 0
    for block in re.split(r"(?m)^(?=\[node )", txt):
        if not block.startswith("[node "):
            continue
        head = block.split("\n", 1)[0]
        pm = re.search(r'parent="([^"]*)"', head)
        if not pm:
            continue
        parent = pm.group(1)
        is_root = (parent == prefix.rsplit("/", 1)[0]
                   and 'name="%s"' % root_name in head)
        if not (is_root or parent == prefix or parent.startswith(prefix + "/")):
            continue

        name = re.search(r'name="([^"]*)"', head).group(1)
        index = re.search(r'index="(\d+)"', head)

        body = block.split("\n[", 1)[0]
        props = [l for l in body.split("\n")[1:] if l.strip()]

        # Fuera los que cruzan el borde.
        keep_props = []
        for p in props:
            key = p.split(" = ")[0].strip()
            if key in CROSS_BOUNDARY:
                dropped += 1
                continue
            keep_props.append(p)

        # Un bloque que se queda sin propiedades no aporta nada: era solo el
        # portador de un NodePath que ahora pone el cargador.
        if not keep_props and not is_root:
            continue

        # `node_paths` tiene que sobrevivir, menos las entradas que se van.
        #
        # Un @export tipado como Node se escribe en el .tscn como un NodePath, y
        # Godot solo lo RESUELVE a nodo si su nombre esta en esta lista de la
        # cabecera; sin ella guarda el NodePath crudo y la propiedad llega nula.
        # La primera version de este generador reconstruia la cabecera con solo
        # name/parent/index y perdia la lista. El unico caso vivo es
        # `TabContainer.bind_label`, y lo caza verify_console_overrides.gd
        # comparando contra la consola inline - no se habria visto de otro modo,
        # porque no da ningun error.
        npm = re.search(r"node_paths=PackedStringArray\(([^)]*)\)", head)
        node_paths = ""
        if npm:
            names = [x.strip().strip('"') for x in npm.group(1).split(",") if x.strip()]
            names = [x for x in names if x not in CROSS_BOUNDARY]
            if names:
                node_paths = " node_paths=PackedStringArray(%s)" % ", ".join(
                    '"%s"' % x for x in names)

        if is_root:
            new_head = '[node name="%s"%s instance=ExtResource("1")]' % (
                root_name, node_paths)
        else:
            rel = parent[len(prefix):].lstrip("/")
            # `index` es lo que convierte esto en un override en vez de un hijo
            # nuevo. Es exactamente lo que pack() perdia.
            assert index is not None, "%s sin index: seria un hijo nuevo" % name
            new_head = '[node name="%s" parent="%s" index="%s"%s]' % (
                name, rel if rel else ".", index.group(1), node_paths)

        # Remapear cualquier ExtResource que la propiedad use. El id "1" es
        # siempre la escena fuente, asi que estos empiezan en 2.
        remapped = []
        for prop_line in keep_props:
            for old_id in re.findall(r'ExtResource\("([^"]+)"\)', prop_line):
                if old_id not in used_ext:
                    assert old_id in src_ext, "ExtResource(%s) no existe en el origen" % old_id
                    used_ext[old_id] = str(len(used_ext) + 2)
                prop_line = prop_line.replace(
                    'ExtResource("%s")' % old_id,
                    'ExtResource("%s")' % used_ext[old_id])
            assert "SubResource(" not in prop_line, (
                "SubResource en %s: habria que traerlo tambien" % name)
            remapped.append(prop_line)

        body_blocks.append(new_head)
        body_blocks.extend(remapped)
        body_blocks.append("")
        kept += 1

    lines_out = ["[gd_scene load_steps=%d format=3]" % (2 + len(used_ext)), ""]
    lines_out.append('[ext_resource type="PackedScene" path="%s" id="1"]' % source_scene)
    for old_id, new_id in used_ext.items():
        lines_out.append("[ext_resource %s id=\"%s\"]" % (src_ext[old_id], new_id))
    lines_out.append("")
    lines_out.extend(body_blocks)

    open(out, "w", encoding="utf-8").write("\n".join(lines_out))
    print("%s: %d bloques, %d NodePath de cruce quitados, %d ext_resource traidos"
          % (out, kept, dropped, len(used_ext)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
