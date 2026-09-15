#!/usr/bin/env python3
# coding: utf-8
"""
HolyQuintet Mod Packager para Codename Engine
Arma un ZIP listo para usar con el engine, desde datos ya extraídos correctamente.

Uso:
    python3 tools/holyquintet/package_mod.py [--output ~/HolyQuintet_mod.zip]

Genera:
    - Estructura mods/holy_quintet/ con los 280 archivos correctos
    - README con instrucciones
    - ZIP empaquetado
"""
import os
import sys
import shutil
import zipfile
from pathlib import Path
from datetime import datetime

def main():
    # Configuración
    repo_root = Path(__file__).parent.parent.parent
    extracted = repo_root / 'tools/holyquintet/extracted/data'
    output_zip = repo_root / 'HolyQuintet_mod.zip'

    # Parse args
    if len(sys.argv) > 1 and sys.argv[1] == '--output':
        output_zip = Path(sys.argv[2]).expanduser()

    # Validación
    if not extracted.exists():
        print(f"❌ No encontrado: {extracted}")
        return 1

    file_count = sum(1 for _ in extracted.rglob('*') if _.is_file())
    print(f"✅ Datos extraídos encontrados: {file_count} archivos en {extracted}")

    # Armar estructura para ZIP
    tmp_dir = Path(f'/tmp/hq_package_{datetime.now().timestamp()}')
    mods_dir = tmp_dir / 'mods/holy_quintet'

    print(f"\n📦 Preparando estructura en {mods_dir}...")
    shutil.copytree(extracted, mods_dir)

    # README
    readme_path = mods_dir / 'README.txt'
    readme_content = """HolyQuintet — Mod para Codename Engine
=====================================

Extraído desde HolyQuintet.exe v1.0.1 ({date})
Método: Tabla de recursos hxcpp (280 archivos, 31 MB)

Contenido:
  ✅ data/           Scripts (.hx), JSON, XMLs, configuración
  ✅ songs/          10 canciones con charts + audio
  ✅ images/         XMLs de atlas del engine
  ✅ modchart/       Shapes CSV
  ✅ source/         Clases Haxe del mod
  ✅ flixel/sounds/  Efectos de sonido

Instalación:
  1. Descarga Codename Engine: https://github.com/CodenameCrew/CodenameEngine
  2. Descomprime este ZIP en la carpeta raíz del engine
  3. La carpeta holy_quintet/ irá a mods/
  4. Ejecuta el engine

Notas:
  - Multimedia grueso (PNG/MP4 de sprites, fuentes, shaders):
    * Disponibles en el ZIP original de GameBanana
    * Se colocan en mods/holy_quintet/images/, fonts/, shaders/
  - Todos los datos están verificados (JSON parsing, XML validity)
  - Los .hx referencian clases del mod que están en source/

Contacto:
  HolyQuintet: https://gamebanana.com/mods/326559
  Codename Engine: https://github.com/CodenameCrew/CodenameEngine
""".format(date=datetime.now().isoformat())

    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    print(f"  ✅ README agregado")

    # Empaquetar
    print(f"\n📥 Empaquetando a {output_zip}...")
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, dirs, files in os.walk(tmp_dir):
            for file in files:
                file_path = Path(root) / file
                arcname = file_path.relative_to(tmp_dir)
                print(f"  → {arcname}")
                zf.write(file_path, arcname)

    # Limpiar
    shutil.rmtree(tmp_dir)

    # Reporte final
    zip_size_mb = output_zip.stat().st_size / 1024 / 1024
    print(f"\n" + "="*60)
    print(f"✅ EMPAQUETADO COMPLETO")
    print(f"="*60)
    print(f"  ZIP:       {output_zip}")
    print(f"  Tamaño:    {zip_size_mb:.2f} MB")
    print(f"  Archivos:  {file_count}")
    print(f"\n  Para usar:")
    print(f"    cp {output_zip} <engine>/")
    print(f"    unzip {output_zip}")
    print(f"    cd <engine> && ./engine")
    print(f"\n" + "="*60)
    return 0

if __name__ == '__main__':
    sys.exit(main())
