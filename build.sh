#!/bin/bash
# Script de compilación para Rubicon FNF Android
# Uso: ./build.sh [debug|release]
# 
# Para subir a Google Play, usa release y asegúrate de tener:
#   - Un keystore válido en ~/.android/debug.keystore (debug)
#   - Un keystore de release en ./keys/release.keystore (release)

set -e

BUILD_TYPE="${1:-debug}"
EXPORT_PRESETS="export_presets.cfg"
VERSION_FILE="version.txt"

echo "=========================================="
echo "  Rubicon FNF - Build Script"
echo "=========================================="
echo ""

# Verificar Godot
if ! command -v godot &> /dev/null; then
    echo "ERROR: Godot no está instalado o no está en PATH"
    echo "Descarga Godot 4.6 desde: https://godotengine.org"
    exit 1
fi

# Verificar Android SDK
if [ -z "$ANDROID_HOME" ]; then
    echo "ERROR: ANDROID_HOME no está configurado"
    echo "Configúralo con: export ANDROID_HOME=/ruta/a/android-sdk"
    exit 1
fi

echo "Godot: $(godot --version)"
echo "Android SDK: $ANDROID_HOME"
echo "Build type: $BUILD_TYPE"
echo ""

# Ir al directorio del proyecto
cd "$(dirname "$0")"

# Crear directorio de builds y keys
mkdir -p builds keys

# Función para obtener el siguiente version code
get_next_version_code() {
    if [ -f "$VERSION_FILE" ]; then
        local current=$(grep "^version_code=" "$VERSION_FILE" | cut -d'=' -f2)
        if [ -z "$current" ]; then
            current=1
        fi
        echo $((current + 1))
    else
        echo "1"
    fi
}

# Función para obtener el version name
get_version_name() {
    if [ -f "$VERSION_FILE" ]; then
        local name=$(grep "^version_name=" "$VERSION_FILE" | cut -d'=' -f2)
        if [ -z "$name" ]; then
            name="1.0.0"
        fi
        echo "$name"
    else
        echo "1.0.0"
    fi
}

# Actualizar version.txt
update_version_file() {
    local new_code=$1
    local name=$2
    echo "version_code=$new_code" > "$VERSION_FILE"
    echo "version_name=$name" >> "$VERSION_FILE"
}

# Actualizar export_presets.cfg con las versiones
update_export_presets() {
    local code=$1
    local name=$2
    sed -i "s/__VERSION_CODE__/$code/g" "$EXPORT_PRESETS"
    sed -i "s/__VERSION_NAME__/$name/g" "$EXPORT_PRESETS"
}

# Restaurar export_presets.cfg a marcadores de posición
restore_export_presets() {
    sed -i "s/version_code=[0-9]*/version_code=__VERSION_CODE__/g" "$EXPORT_PRESETS"
    sed -i "s/version_name=[0-9.]*/version_name=__VERSION_NAME__/g" "$EXPORT_PRESETS"
}

# Inicializar version.txt si no existe
if [ ! -f "$VERSION_FILE" ]; then
    echo "version_code=1" > "$VERSION_FILE"
    echo "version_name=1.0.0" >> "$VERSION_FILE"
    echo "Creado $VERSION_FILE con versión inicial"
fi

# Obtener versiones
VERSION_CODE=$(get_next_version_code)
VERSION_NAME=$(get_version_name)

echo "Versión actual:"
echo "  Version Code: $VERSION_CODE"
echo "  Version Name: $VERSION_NAME"
echo ""

# Backup del export_presets original
cp "$EXPORT_PRESETS" "${EXPORT_PRESETS}.backup"

# Actualizar preset con versiones
update_export_presets "$VERSION_CODE" "$VERSION_NAME"

# Compilar
if [ "$BUILD_TYPE" = "debug" ]; then
    echo "Exportando APK Debug..."
    godot --headless --export-debug "Android Debug" builds/rubicon_fnf_debug.apk
    
    # Guardar nueva versión
    update_version_file "$VERSION_CODE" "$VERSION_NAME"
    echo "Version Code actualizado a: $VERSION_CODE"
else
    echo "Exportando APK Release..."
    
    # Verificar si existe keystore de release
    if [ ! -f "keys/release.keystore" ]; then
        echo ""
        echo "⚠️  IMPORTANTE: No se encontró keystore de release"
        echo "   Para subir a Google Play, necesitas crear uno:"
        echo ""
        echo "   keytool -genkey -v -keystore keys/release.keystore \\"
        echo "     -alias rubiconfnf -keyalg RSA -keysize 2048 -validity 10000 \\"
        echo "     -storepass tu_contraseña -keypass tu_contraseña \\"
        echo "     -dname 'CN=Tu Nombre, OU=Tu Organizacion, O=Tu Organizacion, L=Tu Ciudad, ST=Tu Estado, C=XX'"
        echo ""
        echo "   Luego edita export_presets.cfg y añade la ruta del keystore"
        echo "   en application/android/signing"
        echo ""
    fi
    
    godot --headless --export-release "Android Debug" builds/rubicon_fnf_release.apk
    
    # Guardar nueva versión
    update_version_file "$VERSION_CODE" "$VERSION_NAME"
    echo "Version Code actualizado a: $VERSION_CODE"
fi

# Restaurar export_presets original
mv "${EXPORT_PRESETS}.backup" "$EXPORT_PRESETS"

echo ""
echo "=========================================="
echo "  Build completado!"
echo "=========================================="
echo ""
echo "APK generado en: builds/"
ls -la builds/

echo ""
echo "=========================================="
echo "  IMPORTANTE para Google Play:"
echo "=========================================="
echo ""
echo "1. Cada build incrementa el version_code automáticamente"
echo "2. Para release, necesitas un keystore válido en keys/release.keystore"
echo "3. USA SIEMPRE el MISMO keystore para todas las actualizaciones"
echo "   (si pierdes el keystore, NO podrás actualizar tu app)"
echo ""
