# Multiplayer

Red P2P 1v1 para escenas basadas en `RubiconLevel`. Sincroniza los hits de
notas entre dos instancias por ENet (UDP), permitiendo que dos jugadores
toquen la misma cancion en la misma sesion.

## Instalacion

El addon vive en `res://addons/multiplayer/`. No hay que activar ningun
plugin en el editor: solo se usa como script (`MultiplayerModule`).

## Uso en una escena

1. Copia tu `.tscn` de single player (por ejemplo `test.tscn`) a
   `test_multiplayer.tscn`.
2. En el `AnimationPlayer` del `RubiconLevelClock`, deja `autoplay = ""`.
   El modulo arranca la cancion explicitamente cuando los dos clientes
   estan listos.
3. Agrega un nodo hijo al root de la escena, script
   `res://addons/multiplayer/multiplayer_module.gd`.
4. Asigna los dos controllers (o deja que el modulo los auto-detecte por
   nombre: `Player` para el local, `Opponent` para el remoto).

Los `note_controller` deben tener `disable_inputs = true` en la escena; el
modulo lo fuerza igual en `_ready()`, pero dejarlo explicito ayuda a leer
la escena.

## Correr dos instancias locales

En PC:

    godot --path . -- --host    # instancia 1
    godot --path . -- --client  # instancia 2

Los dos leen `is_host` de `OS.get_cmdline_user_args()`. Si no pasas args,
usa el valor exportado en la escena.

En Android:

- Dos celus en la misma WiFi. Uno lanza con `--host`, el otro con
  `--client host_ip=192.168.1.X`.
- O un celu (cliente) contra una PC (host) en la misma red.

Ver `tools/multiplayer_local.sh` para el caso PC.

## Protocolo

- **Sincronizacion de arranque**: el host manda un timestamp absoluto de
  unix time (`Time.get_unix_time_from_system()`) por `@rpc`. Los dos lados
  esperan hasta ese timestamp y llaman `animation_player.play("scene")`.
- **Hits**: cuando apretas una tecla, el modulo llama `handler._press(event)`
  localmente y manda un RPC con el `lane` al otro extremo. El otro
  reconstruye un `InputEventAction` sintetico y llama `handler._press()`.

El indice de nota (`note_hit_index`) no viaja por RPC: cada lado lo
recalcula con su propio clock. Funciona mientras los AnimationPlayers
esten arrancados al mismo tiempo.

## Limitaciones conocidas

- Solo 1vs1 (un host, un cliente).
- Sin reconexion: si un peer se desconecta a mitad de cancion, no hay
  recovery.
- Sin NAT traversal: los peers tienen que estar en la misma red local, o
  el host tiene que estar accesible en internet (port forwarding).
- El drift entre los AnimationPlayers depende del jitter de la red. Para
  LAN local es <5ms. Para internet puede llegar a 50-100ms.

## Todo / Roadmap

- [ ] Menu de sala con codigo de 4 digitos
- [ ] Relay para NAT traversal (WebSocket/WS, o Nakama)
- [ ] Reconexion
- [ ] Mas de 2 jugadores
- [ ] Sincronizar pausa
