# 🎵 Lullaby Mod - Extracción para Rubicon Android

## Información
- **Origen**: [CabinetOfNovelteam/lullaby_public](https://github.com/CabinetOfNovelteam/lullaby_public/releases/tag/demo)
- **Engine Original**: Godot 4.7.1.2
- **Extraído**: 2026-07-30

## 📁 Estructura

```
lullaby_mod/
├── audio/                 # 205 archivos .ogg (música, SFX, voces)
├── charts/                # Charts JSON de Codename Engine
│   ├── chimera/
│   ├── monochrome/
│   └── safety_lullaby/
├── conversion_scripts/     # Scripts para convertir assets
│   ├── convert_chart.py
│   ├── extract_ctex_to_png.py
│   └── organize_assets.py
├── docs/                  # Documentación completa
├── sprites/              # Sprites y personajes
│   ├── chimera/
│   ├── monochrome/
│   └── safety_lullaby/
└── original_pck/          # (vacío - copiar Lullaby.pck aquí si se desea)
```

## 🎵 Canciones

| ID | Nombre | Personaje | Scroll Speed |
|----|--------|-----------|--------------|
| chimera | Chimera | Serena | 1.0 |
| monochrome | Monochrome | Smiley Chrome | ? |
| safety_lullaby | Safety Lullaby | Hypno | 2.5 |

## 📊 Contenido Extraído

- **205 archivos de audio** (.ogg) - Listos para usar
- **3 charts** - Formato Codename Engine JSON
- **Sprites** - Personajes y fondos

## ⚠️ Notas

- Los sprites están en formato `.png.import` de Godot
- Los charts usan formato Codename Engine (diferente a FNF estándar)
- Para convertir charts, ejecutar `python3 conversion_scripts/convert_chart.py`

## 🔧 Para Agregar al Proyecto

```bash
# Copiar canciones
cp -r charts/* ../songs/
cp -r audio/* ../assets/audio/
```

## 📚 Documentación
Ver `docs/README.md` para información completa.
