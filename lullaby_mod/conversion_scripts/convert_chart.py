#!/usr/bin/env python3
"""
Script para convertir charts de Codename Engine (Lullaby) al formato de Rubicon Android.
"""

import json
import os

def convert_codename_to_rubicon(codename_chart_path, output_path):
    """
    Convierte un chart de Codename Engine al formato de Rubicon Android.
    
    Formato Codename:
    {
        "events": [...],
        "stage": "stage_name",
        "scrollSpeed": 2.5,
        "strumLines": [
            {"keyCount": 4, "position": "dad", "notes": [...]},
            {"keyCount": 4, "position": "boyfriend", "notes": [...]}
        ]
    }
    
    Formato Rubicon Android:
    {
        "song": {
            "speed": 2.5,
            "player1": "dad",
            "player2": "boyfriend", 
            "notes": [
                {"sectionNotes": [[time, id, sLen], ...], "lengthInSteps": 16, ...},
                ...
            ]
        }
    }
    """
    with open(codename_chart_path, 'r') as f:
        codename = json.load(f)
    
    # Extraer información
    scroll_speed = codename.get('scrollSpeed', 1.0)
    stage = codename.get('stage', 'unknown')
    strum_lines = codename.get('strumLines', [])
    
    # Encontrar player1 (dad) y player2 (boyfriend)
    player1_notes = []
    player2_notes = []
    
    for line in strum_lines:
        position = line.get('position', '').lower()
        notes = line.get('notes', [])
        
        if 'dad' in position or 'opponent' in position:
            player1_notes = notes
        elif 'boyfriend' in position or 'player' in position:
            player2_notes = notes
    
    # Convertir notas a formato Rubicon
    # Agrupar por secciones de 2000ms (aproximadamente)
    def convert_notes(notes):
        sections = {}
        for note in notes:
            time_ms = note.get('time', 0)
            section_index = int(time_ms // 2000)  # Secciones de ~2 segundos
            note_id = note.get('id', 0)
            s_len = note.get('sLen', 0)
            
            if section_index not in sections:
                sections[section_index] = []
            sections[section_index].append([time_ms, note_id, s_len])
        
        # Crear array de secciones
        result = []
        max_section = max(sections.keys()) if sections else 0
        for i in range(max_section + 1):
            section_notes = sections.get(i, [])
            result.append({
                "sectionNotes": section_notes,
                "lengthInSteps": 16,
                "altAnim": False,
                "bpm": 120,
                "sectionBeats": 4,
                "changeBPM": False,
                "mustHitSection": i >= (max_section // 2)
            })
        
        return result
    
    rubicon_chart = {
        "song": {
            "speed": scroll_speed,
            "player1": "dad",
            "player2": "boyfriend",
            "stage": stage,
            "notes": convert_notes(player1_notes + player2_notes)
        }
    }
    
    # Guardar
    with open(output_path, 'w') as f:
        json.dump(rubicon_chart, f, indent=2)
    
    print(f"Convertido: {codename_chart_path} -> {output_path}")

# Uso:
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        input_file = sys.argv[1]
        output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.json', '_converted.json')
        convert_codename_to_rubicon(input_file, output_file)
    else:
        # Convertir todos los charts
        base_dir = "../extracted_full/songs"
        for song in ['chimera', 'monochrome', 'safety_lullaby']:
            chart_path = f"{base_dir}/{song}/data/codename_{song}_chart.json"
            if os.path.exists(chart_path):
                output_path = f"../charts/{song}.json"
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                convert_codename_to_rubicon(chart_path, output_path)
