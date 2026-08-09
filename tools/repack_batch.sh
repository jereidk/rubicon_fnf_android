#!/usr/bin/env bash
# Repacks a list of atlas resources, one at a time, and only keeps a result
# that verifies.
#
# Each resource is backed up first, repacked, and then every frame is sampled
# out of the old and new atlases and compared pixel for pixel. The original
# sheets are deleted only after that passes; if anything fails the backup goes
# straight back and the script stops, so a bad one cannot be followed by
# twenty more on top of it.
#
# Usage: tools/repack_batch.sh <lista-de-recursos.txt>
set -uo pipefail

LIST="${1:?falta el fichero con la lista de recursos}"
BACKUP="$(mktemp -d)"
ok=0; skipped=0; failed=0

while IFS= read -r res; do
    [ -z "$res" ] && continue
    case "$res" in \#*) continue ;; esac
    [ -f "$res" ] || { echo "  no existe: $res"; continue; }

    dir="$(dirname "$res")"
    stem="$(basename "$res")"
    safe="${res//\//_}"
    mkdir -p "$BACKUP/$safe"
    cp "$res" "$BACKUP/$safe/"

    # The sheets this resource points at, so they can be restored or removed.
    mapfile -t sheets < <(grep -o 'path="res://[^"]*\.png"' "$res" \
        | sed 's/path="res:\/\///; s/"$//')
    for s in "${sheets[@]}"; do
        [ -f "$s" ] && cp "$s" "$s.import" "$BACKUP/$safe/" 2>/dev/null
    done

    out="$(python3 tools/repack_atlas.py "$res" --apply 2>&1)"
    rc=$?
    if [ $rc -eq 2 ]; then
        echo "SALTADA  $res"
        echo "$out" | sed -n '2,6p' | sed 's/^/    /'
        skipped=$((skipped+1))
        continue
    fi
    if [ $rc -ne 0 ]; then
        echo "ERROR    $res"; echo "$out" | tail -3 | sed 's/^/    /'
        cp "$BACKUP/$safe/$stem" "$res"
        failed=$((failed+1)); break
    fi

    if python3 tools/verify_repack.py "$BACKUP/$safe/$stem" "$res" >/dev/null 2>&1; then
        for s in "${sheets[@]}"; do rm -f "$s" "$s.import"; done
        echo "OK       $res"
        echo "$out" | grep -E "ahorro|hojas repaquetadas" | sed 's/^/    /'
        ok=$((ok+1))
    else
        echo "FALLA LA VERIFICACION  $res  - restaurando"
        cp "$BACKUP/$safe/"* "$dir/" 2>/dev/null
        rm -f "$dir"/*_packed_*.png "$dir"/*_packed_*.png.import
        python3 tools/verify_repack.py "$BACKUP/$safe/$stem" "$res" | sed 's/^/    /'
        failed=$((failed+1)); break
    fi
done < "$LIST"

echo
echo "repaquetados $ok, saltados $skipped, fallidos $failed"
echo "copias de seguridad en $BACKUP"
[ $failed -eq 0 ]
