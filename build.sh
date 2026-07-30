#!/bin/bash
# Script de compilación para Rubicon FNF Android
# Uso: ./build.sh [debug|release]

set -e

BUILD_TYPE="${1:-debug}"

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

# Crear directorio de builds
mkdir -p builds

if [ "$BUILD_TYPE" = "debug" ]; then
    echo "Exportando APK Debug..."
    godot --headless --export-debug "Android Debug" builds/rubicon_fnf_debug.apk
else
    echo "Exportando APK Release..."
    godot --headless --export-release "Android Release" builds/rubicon_fnf_release.apk
fi

echo ""
echo "=========================================="
echo "  Build completado!"
echo "=========================================="
echo ""
echo "APK generado en: builds/"
ls -la builds/
