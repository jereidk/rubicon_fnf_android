#!/usr/bin/env bash
# Corre TODOS los guards que corre CI, localmente, en el mismo orden.
#
# Por que existe
# -------------
# El workflow tiene 107 invocaciones de guard y la unica lista de cuales son
# vive dentro del propio YAML. Eso hace muy facil - y me ha pasado dos veces -
# tocar algo, correr "los guards" (los que uno acaba de escribir, o recuerda), y
# descubrir en CI que existia otro que describia lo que acabas de cambiar.
#
# La segunda vez fue `tools/test_gpu_split.gd`: comprueba el ORDEN textual
# dentro de `_step_gpu_split()` - base antes de la sonda, sonda antes de la
# lectura, lectura antes de restaurar - y al sacar la restauracion a
# `_gpu_split_restore()` los tres marcadores que buscaba dejaron de estar en esa
# funcion. El guard tenia razon en lo que protege y estaba escrito contra la
# forma vieja, que es exactamente el caso que una corrida local habria cazado en
# treinta segundos en vez de en una build.
#
# La lista se LEE del workflow, no se copia aqui. Una copia se desincroniza el
# dia que alguien anada un guard, y entonces este script miente con la misma
# confianza que antes.
#
# Uso:
#   tools/run_guards.sh [patron]
#
#   patron   opcional, substring: `tools/run_guards.sh gpu` corre solo los que
#            lo contienen. Sin patron los corre todos, que tarda un rato.
#
# Necesita GODOT apuntando al binario, o uno en el PATH.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

GODOT="${GODOT:-$(command -v godot || echo /tmp/Godot_v4.7.1-stable_linux.x86_64)}"
if [ ! -x "$GODOT" ]; then
	echo "no encuentro Godot: ponlo en GODOT=" >&2
	exit 2
fi

FILTER="${1:-}"

# La lista, leida del workflow. `guard_godot`, `guard_godot_exit` y
# `guard_python` son las tres formas que el YAML usa.
mapfile -t GUARDS < <(
	grep -oE "guard_(godot|godot_exit|python) +tools/[A-Za-z_0-9]+\.(gd|py)" \
		.github/workflows/android-build.yml \
	| awk '{print $2}' | sort -u
)

if [ "${#GUARDS[@]}" -eq 0 ]; then
	echo "no pude leer la lista de guards del workflow - cambio el formato?" >&2
	exit 2
fi

pass=0
fail=0
failed=()
skipped=0

for g in "${GUARDS[@]}"; do
	if [ -n "$FILTER" ] && [[ "$g" != *"$FILTER"* ]]; then
		continue
	fi
	if [ ! -f "$g" ]; then
		echo "  SALTADO  $g (no existe)"
		skipped=$((skipped + 1))
		continue
	fi

	if [[ "$g" == *.py ]]; then
		out="$(python3 "$g" 2>&1)"
		rc=$?
	else
		out="$("$GODOT" --headless --path . --script "$g" 2>&1)"
		rc=$?
	fi

	# Dos auditorias de imagen necesitan Pillow y numpy, y el workflow tiene un
	# paso que los instala. Aqui no tienen por que estar, y contarlas como
	# fallo haria que la señal local no coincidiera con la de CI - que es todo
	# el motivo de este script. Se distinguen por lo que ellas mismas dicen, no
	# por una lista de nombres que se quedaria vieja.
	# El patron cubre las dos redacciones que hay hoy - "necesita Pillow" y
	# "hace falta Pillow" - mas el ModuleNotFoundError crudo, porque cada
	# auditoria escribe el suyo a mano y una tercera lo dira de otra forma.
	if [ "$rc" -ne 0 ] && echo "$out" | grep -qiE "(necesita|hace falta|requires|install).*(pillow|numpy)|No module named .(PIL|numpy)."; then
		printf '  SALTADO %s (falta Pillow/numpy; CI los instala)\n' "$g"
		skipped=$((skipped + 1))
		continue
	fi

	# Mismo criterio que el workflow para la forma "todo OK": el marcador NO
	# basta, tambien tiene que salir con codigo cero.
	if [ "$rc" -eq 0 ]; then
		pass=$((pass + 1))
		printf '  ok    %s\n' "$g"
	else
		fail=$((fail + 1))
		failed+=("$g")
		printf '  FALLO %s\n' "$g"
		echo "$out" | grep -E "FALLO|FAIL|ERROR:|comprobaciones|checks passed" \
			| grep -v "invalid UID" | tail -6 | sed 's/^/          /'
	fi
done

echo
echo "$pass correctos, $fail fallidos, $skipped saltados"
if [ "$fail" -gt 0 ]; then
	printf 'fallan: %s\n' "${failed[*]}"
	exit 1
fi
