# Pendientes del engine

Cosas investigadas, decididas a medias, o a hacer que quedaron anotadas
para no perderlas. Ordenado por prioridad real, no por cuando se
descubrieron.

---

## 1. Multijugador online (investigado, no implementado)

### Objetivo

Que dos jugadores en **ciudades distintas** puedan jugar una misma cancion
de un mod, cada uno en su dispositivo, con sus hits visibles en la pantalla
del otro.

### Lo que ya existe en el repo

- `addons/multiplayer/multiplayer_module.gd`: sincroniza hits entre dos
  `RubiconLevelNoteController` por ENet (UDP). Funciona en LAN.
- `songs/test/test_multiplayer.tscn`: copia del test single player con
  `autoplay = ""` en el AnimationPlayer y el modulo agregado.
- `tools/multiplayer_local.sh`: script para lanzar dos instancias en PC.
- `addons/multiplayer/README.md`: protocolo, uso, limitaciones.

**Problema**: ENet no funciona entre redes distintas (NAT bloquea
conexiones entrantes). Solo sirve en LAN, y solo para desarrollo en PC.

### Lo que trae Godot 4.7.1 nativo

Verificado en /godot-src/modules/:

- `webrtc/`: habilitado para todas las plataformas (incluido Android).
  `WebRTCPeerConnection` + `WebRTCMultiplayerPeer`. El segundo hereda de
  `MultiplayerPeer`, es drop-in replacement de `ENetMultiplayerPeer`.
- `websocket/`: habilitado para todas las plataformas. `WebSocketPeer`
  (con soporte `wss://` via mbedTLS) y `WebSocketMultiplayerPeer`.
- `upnp/`: habilitado. Abre puertos en el router (falla en movil, pero
  sirve en desktop).
- `mbedtls/`: DTLS + TLS.

**Conclusion**: no hace falta ningun addon externo. El engine ya tiene
P2P directo con NAT traversal (WebRTC) y canal cifrado (WebSocket TLS).

### Arquitectura propuesta

1. **Signaling** (intercambio inicial de SDP + ICE candidates):
   - Broker MQTT publico de HiveMQ: `wss://broker.hivemq.com:8884/mqtt`
   - Gratis, sin cuenta, sin API key, mantenido por HiveMQ.
   - NO pasa datos del juego por aca, solo el handshake (pocos KB).
2. **Conexion de juego**: WebRTC P2P directo entre los dos celulares
   una vez completado el handshake.
3. **Fallback**: si el broker publico falla, conexion manual por
   copy/paste (host muestra SDP offer, amigo lo pega, devuelve answer).

### Seguridad

El broker publico **no cifra los mensajes**. Cualquiera puede suscribirse
a un topic y leer lo que pasa. La solucion es:

- Topic con UUID aleatorio en vez de codigo de 4 letras.
- Cifrar el contenido (SDP + ICE) con clave derivada del codigo de sala
  compartido.

**Alternativa mas simple**: usar el addon Freelay
(github.com/freelay), que ya implementa MQTT + cifrado E2E con Ed25519
y X25519 + presence. Se integra en ~20 lineas.

### Estado

- [x] Investigacion de opciones (LAN, relay propio, WebRTC nativo, addons)
- [x] Decision: WebRTC nativo + signaling por MQTT
- [ ] Elegir entre broker crudo (~150 lineas) o Freelay (~20 lineas)
- [ ] Implementar signaling
- [ ] Integrar WebRTCMultiplayerPeer en multiplayer_module.gd
- [ ] UI de lobby (crear sala / unirse con codigo)
- [ ] Test end-to-end con dos dispositivos en redes distintas

### Alternativas descartadas y por que

- **NodeTunnel**: requiere registrar app_id, pero es la alternativa
  mas solida si WebRTC falla. Relay siempre conecta.
- **Tube**: cero deploy, WebRTC P2P, pero falla en NATs simetricos
  (que es lo que tiene Claro/Movistar/Entel movil). No viable.
- **Easy Lobby**: NAT punchthrough + relay, pero requiere hostear
  una instancia de noray.
- **VPS propio**: pide tarjeta, cuesta ~3 USD/mes. Descartado.

---

## 2. PerfProbe: interpretar los logs

`engine/perf_probe.gd` escribe a
`/storage/emulated/0/Android/data/com.washos.engine/files/logs/washos_perf_*.log`.

**Pendiente**: no hay un parser / visor. Para leer un log de una sesion
larga hay que ir a mano. Ideas:

- Script Python (`tools/parse_perf_log.py`) que agrupe por tipo de
  evento y muestre summary: cuantos HEARTBEAT, cuantos SPIKE, top 10
  spikes por duracion, cuantos MEMLEAP, etc.
- Integrar con el CI para que un test futuro pueda fallar si hay >N
  spikes en un run.

---

## 3. GC en GDScript: aclaracion

No hay garbage collector como en C#. GDScript usa:

- **Refcounting** para objetos derivados de `RefCounted`.
- **Deteccion ciclica** para referencias circulares.

No hay "GC pauses" medibles. Lo que se mide y sigue en el log de
PerfProbe es `orphans=` (nodos huerfanos, que si son una senal de leak
real). Si un mod quiere trackear allocs, no hay una API directa:
habria que usar `Performance.MEMORY_STATIC` y mirar los deltas.

---

## 4. Fidelidad de Holy Quintet

Varias cosas del mod que no se portaron por completo y quedaron como
PENDING en la carpeta del mod
(`/storage/emulated/0/.WashosEngine/mods/holyquintet/holyquintet_mod/PENDING.md`).
Nada de eso bloquea el engine.

---

## 5. ModBubble: opciones por mod

`engine/mod_bubble.gd` ya tiene `register_option()` y
`register_dev_code()` para que los mods agreguen sus propias opciones al
bubble flotante.

**Pendiente**: documentar la API en `MODS.md` (formato del mod.json y
API de scripting). Actualmente la unica referencia son los comentarios
del propio archivo.

---

## 6. GameJolt: leaderboards

`engine/gamejolt/gamejolt.gd` expone todos los endpoints
(`scores_fetch`, `scores_add`, `scores_get_rank`,
`trophies_add_achieved`, `batch`, etc.) pero **nada en el juego los usa
todavia**.

Falta:

- Pantalla de leaderboard en Gauntlet (top 10 con `scores_fetch`).
- Leaderboard por cancion en Freeplay (`scores_fetch` con `table_id`).
- Envio de score al terminar una cancion (`scores_add`).

**Bloqueado por**: no hay gameplay. `PlayState` (escena de cancion) no
existe todavia en Holy Quintet. Cuando exista, ahi se conectan los
leaderboards.

---

## 7. Chart loader de FNF / Psych

El engine actual usa `.tres` (Resources de Godot) para los charts
(`RubiChart`, `RubiChartSection`, `RubiChartRow`, `RubiChartNote`).
El formato de FNF/Psych es JSON.

**Pendiente**: un importador que lea JSON de FNF/Psych y genere los
`.tres` correspondientes. Da compatibilidad con charts existentes.

**Bloqueado por**: la mayoria de mods FNF/Psych usan assets y scripts
que el engine no soporta. Tiene sentido solo si alguien quiere portar
un chart puntual.

---

## 8. API Lua para mods

**No implementado**. Investigado en el branch `add-lullaby-mod` y en
Psych Engine, hay dos caminos:

- **Propio**: crear un runtime Lua con `lua-gdextension` (ya esta en
  el home de Termux, `lua-gdextension-luajit.zip`) y exponer una API
  con callbacks (`on_ready`, `on_beat`, `on_scene_change`) y funciones
  (`play_sound`, `tween`, `set_property`, etc.).
- **Compatibilidad Psych**: implementar los callbacks y funciones mas
  usadas de Psych para que mods simples de ese engine corran. Cubre
  ~30% de los mods y no soporta HScript.

**Bloqueado por**: decision de producto. No hay un caso de uso claro
para Lua hoy: los mods actuales son GDScript puro (Holy Quintet,
animania).

---

## 9. Touch back en todas las pantallas

`holyquintet_mod/menus/main/main_menu.gd` maneja
`NOTIFICATION_WM_GO_BACK_REQUEST` (boton atras de Android) sintetizando
un `ui_cancel`. Las demas pantallas del mod no lo hacen. Sin eso, el
boton atras cierra la app en cualquier otra pantalla.

**Pendiente**: replicar el mismo patron en cada pantalla del mod.
Tambien falta documentarlo en `MODS.md` como patron recomendado.

---

## 10. Refactor de layers

`ModBubble` usa `layer = 185`. `DebugDisplay` usa 190. `ErrorToast` usa
200. `HQTransition` usa 4096.

**Pendiente**: verificar que no haya colisiones con mods que usen
`CanvasLayer` en sus propias escenas. Documentar la tabla de layers en
`MODS.md`:

| Layer | Usado por |
|-------|-----------|
| 80 | MobileControls |
| 185 | ModBubble |
| 190 | DebugDisplay |
| 200 | ErrorToast |
| 4096 | HQTransition |

---

## 11. Save data: versionado

`HQSaves` y `HQOptions` escriben JSON sin campo `version`. Si cambia el
formato de algun campo (rename, cambio de tipo), los saves viejos se
leen mal (silenciosamente, con `data.get("x", default)` cayendo al
default).

**Pendiente**: agregar `version` al save y un `_migrate(data)` que corra
en `load_data()`.

---

## 12. Tests automatizados

No hay tests de nada. `tools/` tiene scripts one-off (`audit_*`,
`bench_*`) pero nada que corra en CI.

**Pendiente**: un framework minimo de tests que:

- Cargue el engine
- Verifique que los autoloads existen y responden
- Chequee que `PerfProbe` escribio el log
- Chequee que la escena `test_multiplayer.tscn` carga sin errores

Corre en CI con `godot --headless --script tools/test_runner.gd`.

---

## Como usar este documento

Cuando termines algo de la lista: marcalo con `[x]` y move el item a un
`CHANGELOG.md` o seccion "Done". Si algo deja de tener sentido, borralo:
este archivo es para pendientes vivos, no un historial.
