# Rubicon Mobile Controls

Este addon añade controles táctiles para jugar a Rubicon FNF en dispositivos Android.

## Instalación

1. **Habilitar el addon:**
   - Abre Godot Engine
   - Ve a `Project` > `Project Settings` > `Plugins`
   - Encuentra `Rubicon Mobile Controls` y ponlo en `Enabled`

2. **Añadir los controles a tu nivel:**
   - Añade la escena `res://addons/rubicon_mobile_controls/mobile_controls.tscn` a tu nivel
   - O instanciarla programáticamente:
   ```gdscript
   var mobile_controls = load("res://addons/rubicon_mobile_controls/mobile_controls.tscn").instantiate()
   add_child(mobile_controls)
   ```

3. **Conectar las señales:**
   ```gdscript
   var touch_handler = $TouchInputHandler  # o usa el autoload
   var mobile_controls = $MobileControls
   
   mobile_controls.lane_pressed.connect(touch_handler._on_mobile_controls_lane_pressed)
   mobile_controls.lane_released.connect(touch_handler._on_mobile_controls_lane_released)
   ```

## Configuración

En el nodo `MobileControls` puedes ajustar:

- **lane_count**: Número de lanes (4 por defecto para FNF)
- **button_size**: Tamaño de los botones
- **spacing**: Espacio entre botones
- **opacity**: Opacidad de los botones

## Compilación para Android

### Requisitos

1. Godot Engine 4.6
2. Android SDK con:
   - Platform SDK 34
   - Build Tools 34
   - NDK (cualquier versión reciente)
3. JDK 17+

### Pasos

1. **Configurar Godot:**
   - Descarga Godot 4.6 desde https://godotengine.org
   - Instala los export templates de Android desde `Editor` > `Manage Export Templates`

2. **Configurar Android SDK en Godot:**
   - Ve a `Editor` > `Editor Settings` > `Export` > `Android`
   - Configura la ruta al Android SDK

3. **Exportar:**
   - Ve a `Project` > `Export`
   - Selecciona `Android Debug`
   - Click en `Export Project`

### Solución de problemas

**Error: "Cannot export project with preset..."**
- Asegúrate de que el Android SDK está configurado correctamente en Godot
- Verifica que tienes los export templates instalados

**Error de compilación Gradle**
- Asegúrate de tener Gradle instalado (versión 7.0+)
- Verifica que JAVA_HOME está configurado

## assets Preparados

El proyecto está preparado con:
- ✅ Controles táctiles básicos
- ✅ Mapeo de lanes a teclas (D, F, J, K)
- ✅ Soporte para multi-touch
- ✅ Configuración de opacity

## Próximos pasos

Para una experiencia móvil completa, considera:
- Añadir botón de pausa
- Añadir botón de restart
- Implementar feedback háptico (vibración)
- Optimizar sprites para móvil
- Ajustar la UI para diferentes resoluciones
