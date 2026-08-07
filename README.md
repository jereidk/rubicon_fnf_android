# Rubicon

> **Building the Android APK by hand (when CI is down):** see
> [Building without GitHub Actions](#building-without-github-actions) at the
> bottom of this file.

A Godot project integrating a unification of rhythm game elements, characters, and levels!

This engine is designed to be robust and optimized while still keeping the development workflow as smooth as possible towards developers looking forward to using this engine.

This repository is a sample project for Rubicon users to get started, using assets from the hit indie game [Friday Night Funkin'](https://github.com/FunkinCrew/Funkin).

## Links

### [Discord](https://discord.gg/HMDFMM3ffu)

# Status

This engine is in a very Work-In-Progress state at the moment, so not everything may be functional. The moment we feel like this engine is stable enough to be used in actual fan games is when we will remove the W.I.P and bump up the version to v1.0.

This engine is currently being reformed, so unless you know what you're doing, the engine isn't easily usable at the moment.

# Developing on Rubicon

If you're developing on Rubicon, whether it's contributing to the engine or making your own fan-game, you should be aware that the way this engine handles tasks is nothing like how most other Friday Night Funkin' engines handle them, if the switch to Godot wasn't enough of an indicator.

We plan to have a wiki to help developers better understand the engine more easily, so please bear with us! :pray:

## Obtaining Rubicon

We like to keep Rubicon short in dependencies, all you really need is [Git](https://git-scm.com) and [Godot](https://godotengine.org), preferably v4.5.1 but it will most likely work in similar versions.

After that, all you need to do is clone this repository:
```
git clone https://github.com/RubiconTeam/rubicon_fnf
```

Although this repository is highly recommended to use Rubicon, its mostly a compilation of our engine's plugins. You can get the engine in its basic form from the [Rubicon Addon](https://github.com/RubiconTeam/rubicon) and optionally but highly recommended, the [Mania Addon](https://github.com/RubiconTeam/rubicon_mania)

# Contributing

We would appreciate your guys' help so much! The main way to help us out would be to submit issues or pull requests. It would be a struggle if everyone split off to make their own version of Rubicon when we could all benefit from it!

Keep in mind that this repository is the sample project. For contributing to the actual code base itself, go to the [Rubicon addon repository](https://github.com/RubiconTeam/rubicon).

# License

Rubicon Engine's code is licensed under the [Apache License, Version 2.0](https://opensource.org/license/apache-2-0). Please see [the license file](LICENSE) for more info. If you don't want to read all that, basically you can use our code as long as you credit us properly.

# Credits
## Developers
- [anniebuue](https://twitter.com/i/user/875471004365185024) - Main Developer
- [legole0](https://twitter.com/i/user/3091959774) - Main Developer
## Contributors
- [BeefStarchJello](https://twitter.com/i/user/1155441339246551043) - Made the logo
- [DooDii](https://twitter.com/i/user/1373127588005224455) - Made the banner
## Special Credits
- [firubii](https://github.com/firubii/) - Note system derived from Fantasy Engine ([HoloFunk](https://gamejolt.com/games/holofunk/754195))
- [cherrythecool](https://github.com/cherrythecool) - [GDAnimate](https://github.com/cherrythecool/gdanimate)

---

# Building without GitHub Actions

`.github/workflows/android-build.yml` is the normal way to get an APK. This
section is the same build done by hand, written down after GitHub Actions had a
multi-hour outage and there was no other way to ship a test build. Every step
here was actually run; the timings are real, measured on the session container.

The workflow file remains the source of truth for *what* the build does — if
the two ever disagree, the workflow is right and this section is stale.

## What you need

| | |
|---|---|
| Godot | `Godot_v4.7.1-stable_linux.x86_64` (must match `GODOT_VERSION` in the workflow) |
| Export templates | `~/.local/share/godot/export_templates/4.7.1.stable/` |
| JDK | 21 (`/usr/lib/jvm/java-21-openjdk-amd64`) |
| Android SDK | `platform-tools`, `platforms;android-34`, `build-tools;34.0.0` |
| NDK | **not needed** — `export_presets.cfg` has `gradle_build/use_gradle_build=false`, so the export uses Godot's prebuilt template APK and never invokes Gradle |

```bash
# Godot binary + export templates
wget -q https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip -O /tmp/godot.zip
unzip -q /tmp/godot.zip -d /tmp/godot_bin
chmod +x /tmp/godot_bin/Godot_v4.7.1-stable_linux.x86_64

wget -q https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz -O /tmp/templates.tpz
mkdir -p ~/.local/share/godot/export_templates/4.7.1.stable
unzip -q /tmp/templates.tpz -d /tmp/tpl
mv /tmp/tpl/templates/* ~/.local/share/godot/export_templates/4.7.1.stable/

# Android SDK
mkdir -p ~/.android/sdk/cmdline-tools && cd ~/.android/sdk/cmdline-tools
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O c.zip
unzip -q c.zip && mv cmdline-tools latest && rm c.zip
yes | ~/.android/sdk/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true
~/.android/sdk/cmdline-tools/latest/bin/sdkmanager \
  "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

## Point Godot at the toolchain

This is the step that is easy to miss: the export **fails with no useful
message** if Godot's editor settings do not name the SDK and JDK. They live in
`~/.config/godot/editor_settings-4.7.tres`, not in the project:

```
export/android/java_sdk_path = "/usr/lib/jvm/java-21-openjdk-amd64"
export/android/android_sdk_path = "/root/.android/sdk"
export/android/debug_keystore = "/root/.android/debug.keystore"
export/android/debug_keystore_pass = "android"
```

The debug keystore has to exist. It is throwaway — it signs the local build and
nothing else (see "Signing" below):

```bash
keytool -genkeypair -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
```

## Prepare the project

Same three restore steps the workflow does, and for the same reason: without
them Godot recompresses every ASTC texture at EXHAUSTIVE quality and the import
goes from minutes to **over an hour**.

```bash
cd /path/to/rubicon_fnf_android
mkdir -p .godot/imported
cp precompiled_astc_imports/*.res    precompiled_astc_imports/*.md5    .godot/imported/
cp precompiled_lightmap_imports/*.ctexarray precompiled_lightmap_imports/*.md5 .godot/imported/
cp precompiled_texture_imports/*.ctex precompiled_texture_imports/*.md5 .godot/imported/

# the custom importer shells out to this, so it has to be built first
cd tools/astc_compress
g++ -O2 -std=c++17 -pthread -I thirdparty/astcenc astc_compress.cpp thirdparty/astcenc/astcenc_*.cpp -o astc_compress
cd ../..
```

## Import (twice), then export

```bash
GODOT=/tmp/godot_bin/Godot_v4.7.1-stable_linux.x86_64

nohup bash -c "
  $GODOT --headless --import
  $GODOT --headless --import
" > /tmp/import.log 2>&1 &
```

**Two passes, not one** — a single `--import` can leave resources generated
mid-scan (glTF-embedded materials and textures) on disk but not yet in the UID
cache, and a scene that references them by UID then fails to resolve at export
time. The workflow does the same thing for the same reason.

**Run it detached and poll.** The import takes about **11m30s** with the
precompiled outputs restored, and this repo's shell tooling times out at ~2
minutes. Do not chain `sleep`s; poll the log instead.

Then export (~**95s**):

```bash
mkdir -p builds
$GODOT --headless --export-debug "Android Debug" builds/android_debug.apk
```

`--export-debug`, not `--export-release`: the workflow builds the debug preset
too and re-signs it afterwards. There is no separate release preset.

Expected output for `arm64-v8a` only (the preset disables the other three
architectures): **~393 MB**.

## Signing, and why a local APK cannot update the installed game

The release keystore lives **only** in the repository's GitHub Actions secrets
(`KEYSTORE_FILE`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`). Actions
secrets are write-only: no token and no API can read them back. So a build made
outside CI is signed with the throwaway debug keystore and Android will
**refuse** to install it over the CI build — a package's signing certificate
cannot change across updates.

Do not try to work around this by printing the keystore into a build log or an
artifact. This repository is public.

The practical answer is to ship the local build as a *separate app* so it
installs alongside the real one and touches none of its save data. Edit
`export_presets.cfg` before exporting:

```
package/unique_name="com.rubicon.fnf.test"
package/name="Lullaby (TEST)"
```

Two things follow from the rename and both have bitten this project:

- The diagnostics log writes to
  `/storage/emulated/0/Android/data/<package>/files/logs`. That path is
  per-package, so a renamed build must derive the package at runtime or it
  writes to a directory it has no permission for and silently falls back to
  internal storage, where the log is unreachable without root.
  `lullaby_diagnostics_log.gd:_android_package()` handles this — the log header's
  `dir_used` line always says where it actually ended up.
- Put the original values back before committing.

To check which certificate an APK carries:

```bash
~/.android/sdk/build-tools/34.0.0/apksigner verify --print-certs some.apk
```

The CI release certificate's SHA-256 is
`144462b3e991edbc5bd9ebecebed2ad5c7ca1dbaa07e40173a94d3b69177739f`. An APK
showing that fingerprint will install as an update over the published app; one
showing anything else will not.

## Getting the APK off the build machine

`SendUserFile` caps at 30 MiB, and splitting a 393 MB APK into 13 parts is
miserable to reassemble on a phone. Upload it to a temporary host instead —
[litterbox](https://litterbox.catbox.moe) takes up to 1 GB and up to 72 hours:

```bash
curl -sS -F reqtype=fileupload -F time=72h -F fileToUpload=@builds/android_debug.apk \
  https://litterbox.catbox.moe/resources/internals/api.php
```

Always publish the md5 alongside the link so a truncated download is caught
before it is installed:

```bash
md5sum builds/android_debug.apk
```

## Checking scripts before spending a build on them

A GDScript **type** error fails the whole script to parse, and Godot then runs
the node with no script at all — silently, with no crash. This has shipped:
`lullaby_fps_display.gd` declared `extends Node` while sitting on a
`CanvasLayer`, and one `self as CanvasLayer` took the entire debug overlay out.

GDRE's `--compile` does **not** catch this. It only tokenises; it accepts an
invalid cast happily. Use Godot's own analyser against a throwaway empty
project:

```bash
mkdir -p /tmp/parsecheck && printf 'config_version=5\n[application]\nconfig/name="p"\n' > /tmp/parsecheck/project.godot
$GODOT --headless --path /tmp/parsecheck --check-only --script /abs/path/to/file.gd 2>&1 \
  | grep "Parse Error" | grep -vE 'not declared in the current scope|Could not find type|Preload file'
```

The filter drops the noise an isolated project always produces (autoloads,
`class_name`s and `preload()` targets it cannot see). Anything left is real.
