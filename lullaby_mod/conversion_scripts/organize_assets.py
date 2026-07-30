#!/usr/bin/env python3
"""
Script para organizar los assets extraídos del mod Lullaby
para que sean compatibles con Rubicon Android.
"""

import os
import shutil
import json

def organize_lullaby_for_rubicon(source_dir, output_dir):
    """
    Organiza los assets del mod Lullaby para Rubicon Android.
    
    Estructura Rubicon Android:
    songs/<song_name>/
        data/
            <song_name>.json    # Chart
            Meta.tres           # Metadatos
        resources/
            Inst.ogg           # Instrumental
            Vocals.ogg         # Vocals
        characters/
            <char_name>.png    # Sprite sheets
    """
    
    os.makedirs(output_dir, exist_ok=True)
    
    songs_info = {
        'chimera': {
            'display_name': 'Chimera',
            'player1': 'serena',
            'player2': 'boyfriend',
            'stage': 'chimera_stage'
        },
        'monochrome': {
            'display_name': 'Monochrome',
            'player1': 'smileychrome', 
            'player2': 'boyfriend',
            'stage': 'monochrome_stage'
        },
        'safety_lullaby': {
            'display_name': 'Safety Lullaby',
            'player1': 'hypno',
            'player2': 'boyfriend',
            'stage': 'alley'
        }
    }
    
    # Crear estructura de carpetas
    for song_id, info in songs_info.items():
        song_dir = os.path.join(output_dir, song_id)
        os.makedirs(f"{song_dir}/data", exist_ok=True)
        os.makedirs(f"{song_dir}/resources", exist_ok=True)
        os.makedirs(f"{song_dir}/characters", exist_ok=True)
        
        print(f"\nProcesando canción: {info['display_name']}")
        
        # Copiar chart JSON
        chart_source = os.path.join(source_dir, 'songs', song_id, 'data', f'codename_{song_id}_chart.json')
        chart_dest = os.path.join(song_dir, 'data', f'{song_id}.json')
        if os.path.exists(chart_source):
            shutil.copy2(chart_source, chart_dest)
            print(f"  Chart copiado: {chart_dest}")
        
        # Copiar audio (buscar archivos .ogg)
        resources_dir = os.path.join(source_dir, 'songs', song_id, 'resources')
        if os.path.exists(resources_dir):
            for f in os.listdir(resources_dir):
                if f.endswith('.ogg.import'):
                    # Buscar el archivo .ogg real en .godot/imported
                    ogg_name = f.replace('.ogg.import', '')
                    src_ogg = os.path.join(source_dir, '.godot', 'imported', f'{ogg_name}.ogg*')
                    print(f"  Audio encontrado: {ogg_name}")
        
        # Copiar sprites de personajes
        chars_dir = os.path.join(source_dir, 'assets', 'funkin', song_id, 'characters')
        if os.path.exists(chars_dir):
            for char_folder in os.listdir(chars_dir):
                char_src = os.path.join(chars_dir, char_folder)
                if os.path.isdir(char_src):
                    char_dest = os.path.join(song_dir, 'characters', char_folder)
                    shutil.copytree(char_src, char_dest, dirs_exist_ok=True)
                    print(f"  Personaje copiado: {char_folder}")

    # Copiar assets globales (UI, etc.)
    print("\n\nCopiando assets globales...")
    global_assets = os.path.join(output_dir, 'global')
    os.makedirs(global_assets, exist_ok=True)
    
    # Copiar UI
    ui_source = os.path.join(source_dir, 'assets', 'funkin', 'ui')
    if os.path.exists(ui_source):
        ui_dest = os.path.join(global_assets, 'ui')
        shutil.copytree(ui_source, ui_dest, dirs_exist_ok=True)
        print("  UI copiada")

    print(f"\n\nOrganización completa en: {output_dir}")

if __name__ == "__main__":
    import sys
    source = "../extracted_full" if len(sys.argv) < 2 else sys.argv[1]
    output = "./rubicon_android_ready" if len(sys.argv) < 3 else sys.argv[2]
    
    organize_lullaby_for_rubicon(source, output)
