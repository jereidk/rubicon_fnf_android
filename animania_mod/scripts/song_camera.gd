extends Node
## The camera work every Funkin song does and no chart has to ask for.
##
## phone-call gets its camera from 97 baked FocusCamera events, because its chart writes
## them. A song whose chart says nothing still moves: Funkin's PlayState points the camera
## at whoever is singing and bumps the zoom on the beat, and without that a song sits dead
## centre for two minutes and reads as broken.
##
## Who is singing is read off the characters' own animation rather than off the note
## controllers' signals, so this works the same whether a side is played or autoplayed and
## does not depend on which Rubicon signal exists in which version.

## Funkin's camera lerps toward the focus point rather than cutting. The interpolated
## camera already eases, so this only has to move the TARGET.
@export var camera: Camera2D
@export var player: Node2D
@export var opponent: Node2D
@export var player_point: Marker2D
@export var opponent_point: Marker2D
@export var clock: Node

## Funkin bumps the camera every four beats, by 0.015, and eases back at 0.95 per frame at
## 60fps - which as a half-life is about 0.0135s per 1% and works out to this. The bump is
## a fraction of the resting zoom so it does not depend on what that zoom is.
@export var bpm: float = 100.0
## Off when the chart authors its own camera events: those are baked onto the clock and
## write the same two properties every frame, so leaving this on has the two of them
## fighting over the camera. dadbattle authors 98 of them.
@export var follows_singer: bool = true
const BUMP := 0.015
## SetCameraBop's `rate` and `intensity`. Baked as value tracks on the clock when the chart
## sets them - dadbattle changes both three times - and these are the defaults for a song
## that never does.
@export var bump_every_beats: int = 4
@export var bump_scale: float = 1.0
const BUMP_DECAY := 6.0

var _rest_zoom: Vector2
var _beat: int = -1


func _ready() -> void:
	if camera != null:
		_rest_zoom = camera.zoom
	# Reset music filters when entering a song
	if MusicFilter.instance:
		MusicFilter.instance.reset()


func _process(delta: float) -> void:
	if camera == null:
		return

	if follows_singer:
		_follow()

	# Back toward the resting zoom, frame-rate independently.
	var fade: float = exp(-BUMP_DECAY * delta)
	camera.zoom = _rest_zoom + (camera.zoom - _rest_zoom) * fade
	camera.set(&"zoom_interpolate_target", camera.zoom)

	if clock == null or clock.animation_player == null:
		return
	var beat: int = floori(
		clock.animation_player.current_animation_position * bpm / 60.0)
	if beat == _beat:
		return
	_beat = beat
	if bump_every_beats > 0 and beat % bump_every_beats == 0:
		camera.zoom = _rest_zoom * (1.0 + BUMP * bump_scale)
		camera.set(&"zoom_interpolate_target", camera.zoom)


## The opponent wins a tie: a note on both sides at once is the opponent's phrase in every
## Funkin song, and cutting to the player for one frame reads as a twitch.
func _follow() -> void:
	var target: Marker2D = null
	if _is_singing(opponent):
		target = opponent_point
	elif _is_singing(player):
		target = player_point
	if target == null:
		return
	camera.set(&"position_interpolate_target", target.position)


func _is_singing(character: Node2D) -> bool:
	if character == null or character.animation_player == null:
		return false
	return String(character.animation_player.current_animation).begins_with("sing_") \
		and character.animation_player.is_playing()
