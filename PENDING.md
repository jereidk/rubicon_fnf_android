# Pendientes — Washos Engine

Notas de trabajo abierto. Se van tachando a medida que se resuelven.

---

## Performance — prewarm de addons (~1.4s Termux / ~3.5s device)

**Estado:** mitigado con prewarm chunked (cede el frame cada 4 scripts).
Sigue sumando al bootstrap total pero ya no congela la UI.

**Idea:** excluir `parser/*` y `tests/*` del prewarm. FIDELITY.md los
marca como código muerto en runtime — se usan solo en tests y en el
editor. Son ~10-12 scripts de los 35 del prewarm de gdanimate.

**Impacto esperado:** ~400-500ms menos de bootstrap.

**Cómo:** filtrar `_addon_prewarm_list` en `_scan_addon_classes` para
saltar paths que matcheen `**/parser/**` y `**/tests/**`. Antes de
aplicarlo, confirmar contra FIDELITY.md que ningún .gd de runtime
importa clases de esas carpetas.

---

## Investigación — unificar addons con mods

Los mods hoy dependen de `mod_all_paths` + `runtime_gd_loader` para
cargar sus `.gd`. Si un mod hace `MiClase.new()` sin preload y la
clase está en su pck, el compiler no la ve (no está en el `.cfg`).

Los addons ya resuelven esto con el `.cfg` sintético + `uid_cache.bin`
combinado. La idea es aplicar el mismo patrón a los mods al montar su
pck en `bake_mod`: escanear sus `.gd`, agregar al acumulador global,
regenerar el `.cfg` combinado. Más trabajo, más robusto.

---

## Mods — soportar `autoloads` desde addons referenciados

`_install_mod_autoloads` existe y funciona. Los addons también pueden
declarar autoloads en `addon.json` (patch aplicado en `9e6c8f59`).

Falta: si un addon declara autoloads y el mod activo también, ambos
conviven sin pisarse. Ya funciona por "first wins", pero no está
testeado el caso de dos autoloads con el mismo nombre entre addon y
mod. Probablemente ya esté cubierto por el guard en
`_install_mod_autoloads` (root.has_node), pero vale verificarlo.

---

## DebugDisplay — overlay de debug

`DebugDisplay` existe y se togglea desde el bubble (opción "Debug").
No está documentado qué muestra ni cómo se usa. Pendiente armar
README o doc en `engine/MODS.md`.

---

## Logging — flag para los ADDON logs

Decisión 2026-09-26: dejar `ADDON compilando / reload OK / reload FALLO`
tal cual (opción B). Son ~70 líneas por arranque pero dan contexto
completo. Si en algún momento molesta, agregar
`const VERBOSE_ADDON_LOGS := false` en `runtime_gd_loader.gd` y
condicionar los dos primeros con el flag.

---

## Bubble — cerrar consola con back de Android

Aplicado en `9e6c8f59`: `_input` maneja `ui_cancel` y cierra consola
y confirm antes de propagar. Pendiente confirmar en device que funciona
(el botón "Cerrar" también está agregado como fallback).
