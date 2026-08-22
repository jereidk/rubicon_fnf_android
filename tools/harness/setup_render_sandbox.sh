#!/usr/bin/env bash
# Builds a throwaway copy of this checkout that can render Chimera with the
# device's own renderer, and imports it.
#
# Why this exists
# ---------------
# Two renderers, and neither one alone can answer a lighting question:
#
#   --rendering-driver opengl3   loads the song, but GL Compatibility has no
#                                LightmapGI, so all of Chimera renders at a
#                                mean luma of 13/255 - always black, whatever
#                                the bug is.
#   --rendering-method mobile    is the device's exact path, lightmap included,
#   --rendering-driver vulkan    but lavapipe has no ASTC: it decompresses ~500
#                                textures to RGBA8 on the CPU and sits inside
#                                load() at 5% CPU indefinitely.
#
# The blocker is the textures, not the scene, and the black-graphic question is
# about light. So this rewrites the sandbox's texture imports to uncompressed
# 128px - which lavapipe takes natively and which does not change lighting at
# all - and Chimera becomes renderable on the real path.
#
# Captures out of it look like mush. That is fine: it measures light, not art.
#
# NEVER point this at the real checkout. It rewrites 503 .import files and
# `--import` also rewrites their uid= lines, which is the class of change that
# has broken this repo before. It refuses to run in place.
#
#   tools/harness/setup_render_sandbox.sh <sandbox-dir> [godot-binary]
#
# then, once it finishes:
#
#   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path <sandbox> \
#     --rendering-method mobile --rendering-driver vulkan \
#     res://tools/harness/scene_shot.tscn \
#     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn /tmp/shots t=100 t=180
#
# Needs a software Vulkan driver: apt-get install -y mesa-vulkan-drivers.
set -euo pipefail

SANDBOX="${1:?uso: setup_render_sandbox.sh <sandbox-dir> [godot]}"
GODOT="${2:-/tmp/Godot_v4.7.1-stable_linux.x86_64}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ "$(readlink -f "$SANDBOX")" = "$SRC" ]; then
	echo "se niega a correr sobre el checkout real: $SRC" >&2
	exit 1
fi

echo "== copiando $SRC -> $SANDBOX"
rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"
cd "$SRC"
# Hardlinks for the bulk. Costs no disk: the assets are 3GB and nothing here
# writes to them.
find . -maxdepth 1 -mindepth 1 ! -name .git ! -name .godot -exec cp -al {} "$SANDBOX/" \;
# Real copies for everything Godot rewrites, so the originals cannot be touched
# through a shared inode.
find . \( -name '*.import' -o -name '*.uid' -o -name '*.tscn' -o -name '*.tres' \
	-o -name '*.gd' -o -name '*.cfg' -o -name '*.godot' -o -name '*.gdshader' \) \
	-type f -not -path './.git/*' -not -path './.godot/*' -print0 \
	| while IFS= read -r -d '' f; do cp --remove-destination "$f" "$SANDBOX/$f"; done

echo "== degradando las texturas del sandbox"
python3 - "$SANDBOX" <<'PY'
import glob, re, sys
sandbox = sys.argv[1]
done = 0
for path in glob.glob(sandbox + '/**/*.import', recursive=True):
	text = open(path).read()
	if 'lullaby.astc_sprite' not in text:
		continue
	uid = re.search(r'^uid="([^"]+)"', text, re.M)
	src = re.search(r'^source_file="([^"]+)"', text, re.M)
	if not src:
		continue
	open(path, 'w').write(
		'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
		+ ('uid="%s"\n' % uid.group(1) if uid else '')
		+ '\n[deps]\n\nsource_file="%s"\n' % src.group(1)
		+ '\n[params]\n\ncompress/mode=0\nmipmaps/generate=false\n'
		  'process/size_limit=128\n')
	done += 1
print("   %d texturas a 128px sin compresion GPU" % done)
PY

echo "== importando (deja que termine; son minutos, no horas)"
"$GODOT" --headless --path "$SANDBOX" --import
echo "== listo: $SANDBOX"
