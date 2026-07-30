# Lullaby Mod - Extracción para Reubicon Engine (Android)

## Información General
- **Juego**: Lullaby (Mod de Friday Night Funkin')
- **Engine Original**: Godot 4.7.1.2
- **Repositorio**: https://github.com/CabinetOfNovelteam/lullaby_public
- **Release**: Demo v1.0.0
- **Fecha de extracción**: 2026-07-30

## 📁 Estructura del Proyecto Extraído

```
lullaby_extracted/
├── Lullaby.pck                      # Paquete original de Godot (852 MB)
├── Lullaby.exe                      # Ejecutable de Windows
├── extracted_full/                  # ✅ Recursos completos extraídos
│   ├── songs/
│   │   ├── chimera/                # Canción 1: Chimera
│   │   ├── monochrome/              # Canción 2: Monochrome
│   │   └── safety_lullaby/         # Canción 3: Safety Lullaby
│   ├── assets/funkin/              # Sprites, UI, personajes
│   ├── .godot/imported/            # Archivos de audio .oggvorbisstr
│   ├── resources/                  # Recursos globales
│   └── scripts/                    # Scripts personalizados
├── extracted_sprites/              # 603 archivos .ctex (texturas)
├── reubicon_mod_export/
│   ├── audio/                       # ✅ 205 archivos de audio .ogg
│   ├── charts/                       # ✅ Charts JSON originales
│   ├── scripts/rubicon/             # ✅ Engine Rubicon (37 scripts)
│   ├── conversion_scripts/          # ✅ Scripts de conversión
│   │   ├── convert_chart.py         # Convierte charts al formato Rubicon
│   │   ├── extract_ctex_to_png.py   # Extrae PNGs de .ctex
│   │   └── organize_assets.py       # Organiza assets para Android
│   └── rubicon_android_ready/       # ✅ Assets organizados
└── godotpcktool                    # Herramienta de extracción
```

## 🎵 Canciones Disponibles

| ID | Nombre | Personaje Principal | Personaje Oponente | Scroll Speed |
|----|--------|---------------------|--------------------|--------------|
| chimera | Chimera | Serena | Boyfriend | 1.0 |
| monochrome | Monochrome | Smiley Chrome | Boyfriend | ? |
| safety_lullaby | Safety Lullaby | Hypno | Boyfriend | 2.5 |

## 📊 Contenido Extraído

### Audio (205 archivos .ogg)
- **Música**: `mus_chimera_inst.ogg`, `mus_monochrome_inst.ogg`, `mus_inst.ogg`, etc.
- **Vocals**: `mus_chimera_voc.ogg`, `mus_vocals.ogg`, etc.
- **SFX**: `sfx_step_*.ogg`, `sfx_enter_game.ogg`, etc.
- **Voice Lines**: `vox_collector_*.ogg` (132 archivos)

### Sprites/Texturas (603 archivos .ctex)
- Formato propietario de Godot 4
- Requieren conversión a PNG usando `extract_ctex_to_png.py`
- Localización: `extracted_sprites/.godot/imported/*.ctex`

### Charts (formato Codename Engine JSON)
```json
{
  "events": [...],
  "stage": "alley",
  "scrollSpeed": 2.5,
  "chartVersion": "1.6.0",
  "strumLines": [
    {
      "keyCount": 4,
      "position": "dad",
      "notes": [
        {"id": 3, "sLen": 264.7, "time": 54000, "type": 0}
      ]
    }
  ]
}
```

### Personajes Identificados
- **dad/hypno/serena** - Personajes principales de cada canción
- **boyfriend** - Novio (jugador)
- **gf** - Novia (Girlfriend)
- **smileychrome, goldp1, goldp2** - Personajes de Monochrome

### Scripts del Engine Rubicon (37 archivos .gdc)
- `rubicon_level.gdc` - Controlador de nivel
- `rubicon_character.gdc` - Sistema de personajes
- `rubicon_level_note.gdc` - Notas rítmicas
- `rubicon_level_note_handler.gdc` - Manejador de notas
- `rubicon_level_song.gdc` - Gestión de canciones

## 🔧 Scripts de Conversión Incluidos

### 1. convert_chart.py
Convierte charts de Codename Engine al formato de Rubicon Android.
```bash
python3 convert_chart.py <archivo.json> [salida.json]
```

### 2. extract_ctex_to_png.py
Extrae texturas PNG de archivos .ctex de Godot 4.
```bash
python3 extract_ctex_to_png.py <carpeta_ctex> <carpeta_salida>
```

### 3. organize_assets.py
Organiza los assets para la estructura de Rubicon Android.
```bash
python3 organize_assets.py <source> <output>
```

## 📱 Pasos para Portar a Android

1. **Copiar archivos al proyecto Rubicon Android**:
   ```bash
   cp -r rubicon_android_ready/* /path/to/rubicon_fnf_android/songs/
   ```

2. **Convertir charts**:
   ```bash
   cd conversion_scripts
   python3 convert_chart.py ../../extracted_full/songs/chimera/data/codename_chimera_chart.json ../../rubicon_android_ready/chimera/data/chimera.json
   ```

3. **Extraer sprites PNG** (requiere Godot 4 o herramienta de terceros):
   ```bash
   ./godotpcktool -p Lullaby.pck -a extract -o sprites_raw --include-regex-filter "\\.png"
   ```

4. **Convertir audio** (si es necesario):
   - Los archivos `.oggvorbisstr` ya son compatibles con la mayoría de engines

## ⚠️ Limitaciones Conocidas

1. **Texturas .ctex**: Formato propietario de Godot 4, requiere:
   - Godot 4 para importar y re-exportar
   - O herramientas de terceros como GodotPCKExplorer
   - O conversión manual a PNG

2. **Scripts .gdc**: Son scripts compilados de GDScript, no editables

3. **Formatos de charts diferentes**: Lullaby usa Codename Engine, Rubicon usa formato propio

4. **Animaciones**: Usan sistema de Animación JSON de Godot, no directamente compatible

## 📥 Fuente
https://github.com/CabinetOfNovelteam/lullaby_public/releases/tag/demo

## 🛠️ Herramientas Utilizadas
- **GodotPckTool** (hhyyrylainen/GodotPckTool v2.3) - Extracción de .pck
- **GodotPCKExplorer** (DmitriySalnikov/GodotPCKExplorer v1.6.0) - Extracción completa
