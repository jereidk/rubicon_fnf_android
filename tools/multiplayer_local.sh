#!/usr/bin/env bash
# Lanza dos instancias locales del juego para probar multiplayer.
# Uso:
#   tools/multiplayer_local.sh /ruta/al/binario/godot /ruta/al/proyecto
#
# Corre la instancia host primero, espera 2s, y lanza el cliente.
# Los dos usan -- --host / -- --client para override de is_host.

set -euo pipefail

GODOT="${1:-godot}"
PROJECT="${2:-.}"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
    echo "godot no encontrado: $GODOT" >&2
    exit 1
fi

echo "Lanzando host en $PROJECT..."
"$GODOT" --path "$PROJECT" -- --host &
HOST_PID=$!

sleep 2

echo "Lanzando cliente..."
"$GODOT" --path "$PROJECT" -- --client &
CLIENT_PID=$!

echo "Host PID=$HOST_PID  Cliente PID=$CLIENT_PID"
echo "Ctrl+C para matar los dos."

trap "kill $HOST_PID $CLIENT_PID 2>/dev/null || true" EXIT
wait
