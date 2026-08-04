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
narrowly-scoped set of files (currently 3 source `.exr` files) that's not
worth folding into the same regeneration script/README.

Godot's reimport-skip decision is content-hash based, not timestamp based
(`_test_for_reimport` in `editor/file_system/editor_file_system.cpp`
compares the current source file's MD5 against `source_md5` in the `.md5`
sidecar, and the current compiled output's MD5 against `dest_md5`) - a
fresh `git checkout` resets every file's mtime, which would defeat a
timestamp-based cache, but not a content-hash one. Confirmed by restoring
these into a clean `.godot/imported` and running `--import`: none of the
3 source filenames produce a `reimport |` line.

Unlike the ASTC plugins (which compute their own `source_md5`/`dest_md5`
inside the importer script), this `.md5` sidecar is one Godot's core
importer already writes to `.godot/imported/` itself for every resource -
these are copied verbatim from there, not hand-computed. A
`2d_array_texture` import produces multiple dest files (one per target
compression format) sharing a single `.md5` sidecar named after the
source file's own hash, not one `.md5` per dest file - copy the whole set
together.

## Regenerating

Needed whenever one of the source `.exr` files changes, or Godot's own
`2d_array_texture` importer/compression settings on it change.

Run the actual import locally (or via a throwaway CI run), then copy the
fresh files straight out of `.godot/imported/` for each of these `.import`
files' `source_file`:

- `songs/chimera/chimera_base.exr.import`
- `lullaby_mod/songs/chimera/chimera_base.exr.import`
- `resources/collector_shop/env_collector_shop.exr.import`

```
godot --headless --import   # run twice; see the workflow's own comment on why
```

For each one, find its `dest_files` entries in the `.import` file, and the
shared `<source_basename>-<hash>.md5` sidecar (same hash that appears in
every one of that file's `dest_files`) - copy all of them into this
directory verbatim.

Verify from a *clean* `.godot/` (delete it first) that a subsequent
`--headless --import` reports no `reimport |` line for any of the 3
source filenames before committing.
