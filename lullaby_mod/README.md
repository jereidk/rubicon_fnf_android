# 🎵 Lullaby Mod - Extracción para Rubicon Android

## Información
- **Origen**: [CabinetOfNovelteam/lullaby_public](https://github.com/CabinetOfNovelteam/lullaby_public/releases/tag/demo)
- **Engine Original**: Godot 4.7.1.2
- **Extraído**: 2026-07-30

## 📁 Estructura Completa

```
lullaby_mod/
├── audio/                     # 205 archivos .ogg
│   ├── mus_*.ogg             # Música
│   ├── sfx_*.ogg             # Efectos de sonido
│   └── vox_*.ogg             # Voces
├── charts/                    # Charts JSON de Codename Engine
│   ├── chimera/data/         # Chimera chart
│   ├── monochrome/data/       # Monochrome chart
│   └── safety_lullaby/data/  # Safety Lullaby chart
├── conversion_scripts/         # Scripts de conversión
│   ├── convert_chart.py      # Convierte charts a formato Rubicon
│   ├── extract_ctex_to_png.py # Extrae PNGs de .ctex
│   └── organize_assets.py    # Organiza assets
├── docs/                     # Documentación
├── engine_scripts/            # Scripts del engine Rubicon
│   ├── rubicon_character.gdc
│   ├── rubicon_level*.gdc
│   └── rubicon_level_note*.gdc
├── rubicon_mania_scripts/     # Scripts modo mania
├── scenes/                    # Escenas de las canciones
│   ├── chimera/              # step_0-4.tscn
│   └── safety_lullaby/       # gameover, intro
├── songs_scripts/             # Scripts específicos de canciones
│   └── chimera/              # Scripts de Chimera
├── sprites/                   # Sprites Godot (.import files)
├── sprites_data/              # Datos de sprites
│   ├── blood/
│   ├── gf/
│   ├── goldp1/, goldp2/
│   ├── hypno_end/, hypno_world/
│   └── smileychrome/
└── original_pck/              # (vacío - requiere Lullaby.pck)
```

## 🎵 Canciones

| ID | Nombre | Personaje | Scroll Speed |
|----|--------|-----------|--------------|
| chimera | Chimera | Serena | 1.0 |
| monochrome | Monochrome | Smiley Chrome | ? |
| safety_lullaby | Safety Lullaby | Hypno | 2.5 |

## 📊 Contenido Extraído

| Tipo | Cantidad | Formato |
|------|----------|---------|
| Audio | 205 | .ogg Vorbis |
| Charts | 3 | JSON (Codename Engine) |
| Scripts Engine | 6 | .gdc (GDScript compilado) |
| Scripts Mania | 4 | .gdc |
| Scripts Songs | 7+ | .gdc |
| Escenas | 7 | .tscn.remap |
| Personajes | 7+ | JSON + recursos |

## 🔧 Scripts de Conversión

```bash
# Convertir charts al formato Rubicon
python3 conversion_scripts/convert_chart.py <input.json> [output.json]

# Extraer PNGs de .ctex (formato Godot 4)
python3 conversion_scripts/extract_ctex_to_png.py <carpeta_ctex> <salida>

# Organizar assets
python3 conversion_scripts/organize_assets.py <source> <output>
```

## 📱 Para Agregar al Proyecto

```bash
# Copiar canciones
cp -r charts/* ../songs/
cp -r audio/* ../assets/audio/
cp -r sprites_data/* ../assets/levels/characters/
```

## ⚠️ Notas Importantes

1. **Sprites**: Están en formato `.png.import` de Godot - requieren conversión
2. **Charts**: Usan formato Codename Engine (diferente a FNF estándar)
3. **Scripts**: Son `.gdc` (GDScript compilado) - no editables directamente
4. **Texturas .ctex**: 603 archivos, formato propietario Godot 4

## 📚 Documentación
Ver `docs/README.md` para información completa.
