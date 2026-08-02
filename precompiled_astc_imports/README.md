# Precompiled ASTC imports

This directory holds pre-run output of the two custom `EditorImportPlugin`s
in `addons/astc_sprite_import/` and `addons/astc_normal_import/`: the
`.res` files Godot's importer produces, plus a `.md5` sidecar for each one.

## Why this exists

EXHAUSTIVE-quality ASTC compression across the ~124 large textures these
importers target takes over an hour of CPU time. The workflow already has
a GitHub Actions cache for `.godot/imported`, but its key is a hash of
every tracked `.png`/`.tscn`/`.tres`/etc in the whole project - changing
any one of those files anywhere invalidates it, forcing a full recompress.
Committing the actual output sidesteps that entirely.

This only works because Godot's reimport-skip decision is ultimately
content-hash based, not timestamp based (see
`core/io/resource_importer.cpp` / `editor/file_system/editor_file_system.cpp`
in Godot's source: `_test_for_reimport` compares the current source file's
MD5 against `source_md5` in the `.md5` sidecar, and the current `.res`
output's MD5 against `dest_md5`). A fresh `git checkout` resets every
file's mtime, which would defeat a timestamp-based cache, but not a
content-hash one.

The workflow's "Restore precompiled ASTC imports" step copies these files
into `.godot/imported/` before the import step runs, so Godot sees them as
already up to date and skips recompressing.

## Regenerating

Needed whenever one of the 124 source PNGs changes, or the importer
scripts/`tools/astc_compress` change in a way that changes their output.

**Fast path - extract from a CI build's APK artifact** (this Android
export mode stores imported resources as loose files under
`assets/.godot/imported/` inside the APK, not a single packed `.pck`, so
they can be pulled out directly):

```python
import glob, re, os, hashlib, zipfile

zf = zipfile.ZipFile('rubicon-release.apk')
for imp in glob.glob('lullaby_mod/**/*.png.import', recursive=True):
    content = open(imp).read()
    if 'lullaby.astc_sprite' not in content and 'lullaby.astc_normal_map' not in content:
        continue
    dest_res_path = re.search(r'dest_files=\["(res://[^"]+)"\]', content).group(1)
    apk_internal = 'assets/' + dest_res_path[len('res://'):]
    res_bytes = zf.read(apk_internal)
    base = os.path.basename(dest_res_path)[:-len('.res')]  # foo.png-<hash>
    open(f'precompiled_astc_imports/{base}.res', 'wb').write(res_bytes)
    source_md5 = hashlib.md5(open(imp[:-len('.import')], 'rb').read()).hexdigest()
    dest_md5 = hashlib.md5(res_bytes).hexdigest()
    open(f'precompiled_astc_imports/{base}.md5', 'w').write(
        f'source_md5="{source_md5}"\ndest_md5="{dest_md5}"\n\n')
```

**Authoritative path - run the actual import**, locally or via a
throwaway CI run, then copy the fresh `.res`/`.md5` pairs for the 124
target files out of `.godot/imported/`:

```
godot --headless --import   # run twice; see the workflow's own comment on why
```

Either way, verify from a *clean* `.godot/` (delete it first - a stale
internal scan-state cache from a previous interrupted run can mask
problems) that a subsequent `--headless --import` reports no `reimport |`
line for any of the 124 target filenames before committing.
