# Precompiled lightmap imports

This directory holds pre-run output of Godot's own stock `2d_array_texture`
importer for the project's baked `LightmapGI` HDR textures (`.exr` files
compressed into BPTC + ASTC `Texture2DArray` variants): the `.ctexarray`
files Godot produces, plus a `.md5` sidecar per source file.

## Why this exists

These few `.exr` files are individually disproportionate: `chimera_base.exr`
alone took ~103s of a ~950s "Import Godot project" CI step (about 11% of
the whole step, for one file) - it gets compressed to *two* full-quality
formats (BPTC for desktop, ASTC for mobile) from an uncompressed HDR
source. Same idea as `precompiled_astc_imports/` next to this directory
(see its README for the fuller rationale on why the workflow's import
cache can't just absorb this): the GitHub Actions cache key for
`.godot/imported` is a hash of every tracked asset in the project, so any
commit touching any of them forces a full reimport, and committing the
actual output sidesteps that.

This is a separate directory from `precompiled_astc_imports/` on purpose -
different importer (Godot's built-in `2d_array_texture`, not either of the
two custom `EditorImportPlugin`s in `addons/`), and a much smaller,
narrowly-scoped set of files (currently 1 source `.exr` file) that's not
worth folding into the same regeneration script/README.

This originally covered 3 source `.exr` files: this one plus two
duplicates (`songs/chimera/chimera_base.exr` and
`resources/collector_shop/env_collector_shop.exr`) that turned out to be
dead weight left over from early porting work, referenced by nothing -
see the "Remove 2 orphaned duplicate .exr lightmaps" commit for how that
was confirmed (ResourceLoader.get_dependencies() across every .tscn/.tres/
.res in the project, not a plain-text grep - grep is exactly what missed
a similar case before, see 8878770). Deleting those source files was a
better fix than precompiling around them, so they're gone instead.

Godot's reimport-skip decision is content-hash based, not timestamp based
(`_test_for_reimport` in `editor/file_system/editor_file_system.cpp`
compares the current source file's MD5 against `source_md5` in the `.md5`
sidecar, and the current compiled output's MD5 against `dest_md5`) - a
fresh `git checkout` resets every file's mtime, which would defeat a
timestamp-based cache, but not a content-hash one. Confirmed by restoring
this into a clean `.godot/imported` and running `--import`: the source
filename produces no `reimport |` line.

Unlike the ASTC plugins (which compute their own `source_md5`/`dest_md5`
inside the importer script), this `.md5` sidecar is one Godot's core
importer already writes to `.godot/imported/` itself for every resource -
these are copied verbatim from there, not hand-computed. A
`2d_array_texture` import produces multiple dest files (one per target
compression format) sharing a single `.md5` sidecar named after the
source file's own hash, not one `.md5` per dest file - copy the whole set
together.

## Regenerating

Needed whenever `lullaby_mod/songs/chimera/chimera_base.exr` changes, or
Godot's own `2d_array_texture` importer/compression settings on it
change.

Run the actual import locally (or via a throwaway CI run), then find its
`dest_files` entries in `lullaby_mod/songs/chimera/chimera_base.exr.import`,
and the shared `<source_basename>-<hash>.md5` sidecar (same hash that
appears in every one of that file's `dest_files`) - copy all of them into
this directory verbatim from `.godot/imported/`:

```
godot --headless --import   # run twice; see the workflow's own comment on why
```

Verify from a *clean* `.godot/` (delete it first) that a subsequent
`--headless --import` reports no `reimport |` line for the source
filename before committing.
