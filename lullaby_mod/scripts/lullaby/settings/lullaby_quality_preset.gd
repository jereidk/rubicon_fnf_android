class_name LullabyQualityPreset extends Resource

@export var name: String = "Default"

@export var scaling_3d_mode: Viewport.Scaling3DMode = Viewport.Scaling3DMode.SCALING_3D_MODE_BILINEAR
@export var render_scale: float = 1.0
@export var shadows_enabled: bool = true
@export var positional_shadow_atlas_size: int = 4096
@export var positional_shadow_filter_quality: int = 2
@export var msaa_3d_quality: Viewport.MSAA = Viewport.MSAA.MSAA_DISABLED
@export var screen_space_aa_quality: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA
@export var post_processing: LullabySettings.PostProcessing = LullabySettings.PostProcessing.HIGH
@export var ssao: bool = true
@export var ssil: bool = true

## Texture sampling quality, as Viewport.AnisotropicFiltering
## (0 = 1x/off, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x).
##
## The project was leaving this at the engine default of 4x everywhere. It is a
## per-sample bandwidth cost on every textured pixel, and this device is bound
## on exactly that - Chimera's GPU time tracks how much of the screen is
## covered, not how many objects or primitives there are. At Low's 0.65 render
## scale on a 720p phone the difference between 4x and off is not visible;
## the bandwidth is.
@export_enum("Off (1x)", "2x", "4x", "8x", "16x")
var anisotropic_filtering: int = 2

## Viewport.mesh_lod_threshold, in pixels: how small a mesh's detail has to get
## before the engine swaps in a cheaper LOD.
##
## Also left at the engine default of 1.0, which effectively means LODs never
## kick in. Raising it makes distant geometry drop detail sooner, which cuts
## both vertex work and the fragments those triangles cover. Godot generates
## the LODs at import time, so this costs nothing to turn on.
@export_range(0.0, 16.0, 0.5) var mesh_lod_threshold: float = 1.0

## Multiplier on each light's own range, past which the light stops being
## rendered - see lullaby_light_budget_applier.gd. 0 disables the pass.
##
## The mobile renderer evaluates every omni/spot light that reaches a fragment,
## and Chimera's cost tracks screen coverage at a constant light count, so
## fewer lights per pixel is the lever that matches the measurement. Deriving
## the distance from the light's own range means small local lights (candles, a
## phone glow) drop out when the camera leaves them while scene-wide lights
## never do, without tuning a number per scene.
@export_range(0.0, 12.0, 0.5) var light_distance_fade: float = 0.0

## Engine.physics_ticks_per_second.
##
## Nothing in this project's gameplay runs on the physics tick: a sweep for
## _physics_process/_integrate_forces across the whole repo finds exactly
## three users, and none of them is timing-critical - Safety Lullaby's
## lamp_flicker.gd accumulates delta (so it is tick-rate independent), and
## the shop's mouse_controller.gd only re-aims the hover raycast. Rubicon
## drives notes off the audio clock in _process. So halving the rate halves
## a cost that buys nothing here: the Collector's Shop logs phys=3-6ms of a
## 24ms frame on 19 Area3Ds and 31 collision pairs, with p3d_objs=0 - there
## is not a single active rigid body in it.
##
## It also breaks a feedback loop. Godot runs up to max_physics_steps_per_frame
## catch-up ticks after a slow frame, so a 141ms shop spike was asking for
## eight physics steps inside the frame that was already late.
@export var physics_ticks_per_second: int = 60

## Frame rate cap, as LullabySettings.display_target_fps.
##
## **Every preset ships TARGET_FPS_NATIVE (-1): follow whatever the panel is
## running at, and never pin a number.** A preset that hard-caps to 30 throws
## away every frame the device could have delivered on the cheap shots - and
## Chimera has shots at 13ms next to shots at 60 - while a preset that pins 60
## is wrong on the first 90Hz or 120Hz phone this runs on. The row still exists
## for the player, who can pick a fixed rate in the console; the presets just
## stop having an opinion about the panel.
@export var target_fps: int = -1

## Only Very Low sets this - strips every decorative/post-processing shader
## effect in the project (see LullabySettings.EFFECT_SHADER_PATHS) while
## leaving shaders that are a node's actual base material untouched (e.g.
## the shop console's toon shading, the cartridge dissolve-in animation).
@export var disable_shader_effects: bool = false

## Hide every BAKE_STATIC light in a scene that has a working LightmapGI.
##
## Chimera is the reason. Its frame is 90% the 3D pass (gpu = 5.7ms + 90.8ms
## per Mpx of 3D on a moto g53), and 90.8 ms/Mpx is what six lights per
## fragment cost on this exact path - the isolated bench measures 6 full-screen
## omnis at 108.6ms over 1.152 Mpx, i.e. 94 ms/Mpx. It is lights, not geometry:
## the cheapest frame of the song draws 32960 primitives and the most expensive
## draws 9862.
##
## The song's own log does the A/B without being asked. The camera in the
## closet has three lights reaching it and costs 33.5ms; the wide shots of the
## house have four and cost 57-59ms. The fourth is MoonSpotlight - authored
## BAKE_STATIC, energy 0.37, and therefore already inside chimera_base.lmbake.
## One light that the bake already contains is worth 24ms of a 57ms frame.
##
## Six of Chimera's lights are BAKE_STATIC and **no animation track in the
## scene touches any of them** - checked, all 27 sequences: they are static for
## the whole song, so the bake carries their entire contribution to the 60-64
## meshes that ship GI_MODE_STATIC. What hiding them costs is the light they
## throw on what the bake does not cover: the characters. Serena's own light is
## excluded for exactly that reason (see the applier).
##
## Low and Very Low. Not Medium, which is meant to look right.
@export var hide_baked_lights: bool = false

## Drop the two most expensive terms of the lighting shader.
##
## Every 3D material in this project ships Godot's defaults - 89 of 93 declare
## no `specular_mode` and 89 no `diffuse_mode` - so all of them run Burley
## diffuse plus Schlick-GGX specular once per light per fragment. Nobody chose
## that; it is what a StandardMaterial3D is out of the box.
##
## Measured on the phone's path (Vulkan, Forward Mobile, 880x396, three
## overlapping full-screen layers):
##
##     2 lights  base 21.43ms  ->  LAMBERT + specular off  13.33ms   -38%
##     4 lights  base 34.63ms  ->  LAMBERT + specular off  18.47ms   -47%
##
## Both terms run per light, so the saving grows with the light count. Metallic
## materials keep their specular - for a metal that lobe IS the material, and
## disabling it renders the surface nearly black.
##
## Low and Very Low, alongside hide_baked_lights: the two together are what
## puts 60fps back on the table without lowering render scale.
@export var cheap_shading: bool = false

## Switch off the 2D lights a scene has marked optional.
##
## The 3D presets above never touched Safety Lullaby, because the song has no
## 3D at all: `rend=[3d=0/0/0]`, 592 primitives, 38 draw calls - and 32.48ms of
## GPU against Chimera's 15.27ms on 15645 primitives. The render scale does not
## reach it either; `scaling_3d_scale` scales the 3D buffer and nothing else,
## so every pixel of that song is drawn at the full 1600x720.
##
## What is left is 2D fill, and the multiplier on it is lights. Godot's canvas
## renderer draws each affected CanvasItem **again, once per light**, so the
## cost is roughly `items x (1 + lights touching them)` and `over=` - which
## counts items once - cannot see any of it. The alley authors four
## PointLight2D. Measured through the census's new helper, `BG/BgLight` covers
## **1.000** of the frame (1049x480 texture at `texture_scale = 4.0`, i.e.
## 4196x1920 over a 1920x1080 stage) and the two lamp lights about 0.29 and
## 0.42 of it. Nine of the eleven parallax sprites carried `light_mask = 3`
## against `range_item_cull_mask = 257`, so they shared bit 1 and every one of
## those nine was redrawn per overlapping light.
##
## Seven of those nine are one sprite now (8a27dc1) and it ships
## `light_mask = 0` with BgLight baked in (df7a353), so what is left sharing
## bit 1 with that light is `Parallax3/Mountain` and `Parallax/FrontTree`.
##
## It also explains the one number that never fitted: the two pure-2D scenes in
## log d67addb8 are 2.5x apart in items (`over=` 2.0x against 5.0x) and 4.4x
## apart in GPU (7.41ms against 32.48ms). Items alone do not do that.
##
## Marked per scene rather than guessed at, with the
## `Settings.OPTIONAL_2D_LIGHT_GROUP` group - the same shape as
## SUBVIEWPORT_NATIVE_GROUP, and for the same reason: which lights are mood and
## which are decoration is an authoring decision, not something a walk can
## infer. The alley's three lamp lights are in it, and since df7a353 so is
## `BgLight`: its effect on the static background is baked into
## `back_merged.png` and `MergedBack` ships `light_mask = 0`, so the darkness
## the song reads through is in the texture now and switching the light off no
## longer takes it away. The live light only redraws the characters and
## `FrontTree`.
##
## Very Low only, alongside everything else that preset already drops.
@export var disable_optional_2d_lights: bool = false

## How many atlas frames pass between gdanimate symbol updates. 1 is stock.
##
## The only lever on gdanimate's cost that does not require rewriting the
## addon, and it is measured rather than reasoned: with Gold's real atlas in an
## isolated project the rebuild-per-frame-advance ratio is 0.99, so halving the
## advances halves the rebuilds. Playback speed is untouched - after six
## seconds the symbols sit on frame 140 / 139 / 143 at step 1 / 2 / 3, all
## against an expected ~144 - because the advance is still `floori(t * fps)`
## atlas frames, only the gate that lets it run is coarser.
##
## Why it is worth a preset row: Monochrome is CPU-bound on both devices
## measured (13-15ms of GPU at 42-49fps) and gdanimate is its biggest single
## item - anim2d p50 56.80 ms/s on a Mali-G57, 112.80 ms/s on a Mali-G52, with
## rebuild at 87% of it. Chimera reads anim2d=0.00, which is why every earlier
## measurement in this project missed it: they were all taken on the one song
## with no Adobe atlas on stage.
##
## What it costs is how the animation reads: at 2 the atlas plays at 12fps
## instead of 24 - same duration, half the distinct drawings.
##
## **Very Low only.** How much that is noticed depends on whether the source
## was animated on twos, and counting the layer-frame durations in Monochrome's
## atlases says it mostly was - Gold, the character on screen all song, is
## 83.8% of layer frames at DU >= 2, and his turnaround 85.2%. But DU is per
## layer and Gold's busiest symbol has 47 of them, so a composite can still
## change every frame even when each layer holds two; the honest claim is that
## the source is far friendlier to this than something drawn on ones, not that
## it is invisible.
##
## So it goes only on the preset that already exists to make the game run at
## all - no shadows, no post-processing, render at 50%, LOD at 8. Low still
## means to look right and keeps 1.
@export_range(1, 4, 1) var atlas_frame_step: int = 1

## Cambiar una cutscene viva por su vídeo pre-renderizado, donde lo haya.
##
## Es el único lever de esta lista que no degrada nada de lo que el jugador ve:
## el vídeo se renderiza desde la escena real, así que la imagen es la misma
## salvo por la compresión. Lo que cambia es de dónde sale.
##
## La intro de Safety Lullaby, medida en el dispositivo el 2026-08-24: 31.5
## segundos con `draw=3-7`, `prims=68-76`, `over=0.6x` y `cpu_render=0.6-1.7ms`
## - o sea que no es relleno ni es el renderizador - y aun así un tercio de sus
## frames pasan de 28ms, con picos de 50-86ms en cada transición de plano. El
## gasto es CPU de animación: la escena entera de la canción corre detrás de una
## cutscene de 22 nodos, con `trees=15(active=15)` y hasta 105 pistas.
##
## El vídeo lo cambia por un coste plano y conocido. Sobre el decodificador real
## del motor, `ms = 1.32 + 3.49 x Mpx`, o sea ~2.8ms/frame a 960x432 en el Xeon
## de referencia; libtheora va en C genérico en todas las plataformas (el
## SConstruct de Godot fija `x86_libtheora_opt_gcc` a False y la carpeta `arm/`
## ni está vendorizada), así que el teléfono corre ese mismo código y la
## diferencia es solo de microarquitectura.
##
## Va en TODOS los presets. Antes solo en los bajos, con este argumento: "en un
## dispositivo que aguanta la escena viva, la escena viva es mejor". Se retira a
## propósito, y conviene separar qué parte de aquello era cierta.
##
## Lo que NO era cierto: que la escena viva se viese mejor por definición. El
## arte de las cutscenes está authoreado a 1280x720 - medido sobre los propios
## PNG, `beginning_fence`, `closeup`, `ending_bg` y el resto son todos
## 1280x720 - así que ese es el techo de detalle real, no la resolución de la
## pantalla. Un vídeo entregado a esa anchura no pierde nada contra la escena
## viva; a 960 pierde un 25% lineal, y de ahí venía la impresión de que el vídeo
## era el camino pobre. La respuesta era subir la anchura de entrega, no
## reservar el vídeo para los teléfonos malos.
##
## Lo que SÍ era cierto, y ahora es el precio: la escena viva se puede editar
## sin re-renderizar. Con esto encendido en todas partes, cambiar un fotograma
## de una cutscene obliga a pasar por CI y por un render que hoy cuesta horas.
## Es una decisión de producto tomada a sabiendas.
##
## El interruptor NO desaparece aunque los cuatro presets lo pidan. Sigue siendo
## lo que `render_cutscene.gd` apaga para poder grabar la escena viva - sin él
## no habría forma de generar un vídeo nuevo - y sigue siendo la vía por la que
## un checkout sin `.ogv` cae de vuelta a la escena viva en vez de no dibujar
## nada.
@export var prefer_cutscene_video: bool = true

func is_matching(settings: LullabySettings) -> bool:
	return (settings.graphics_scaling_mode == scaling_3d_mode and
		settings.graphics_render_scale == render_scale and
		settings.graphics_shadows_enabled == shadows_enabled and
		settings.graphics_positional_shadow_atlas_size == positional_shadow_atlas_size and
		settings.graphics_positional_shadow_filter_quality == positional_shadow_filter_quality and
		settings.graphics_msaa_3d_quality == msaa_3d_quality and
		settings.graphics_screen_space_aa_quality == screen_space_aa_quality and
		settings.graphics_post_processing == post_processing and
		settings.graphics_ssao == ssao and
		settings.graphics_ssil == ssil and
		settings.graphics_anisotropic_filtering == anisotropic_filtering and
		settings.graphics_mesh_lod_threshold == mesh_lod_threshold and
		settings.graphics_light_distance_fade == light_distance_fade and
		settings.graphics_physics_ticks_per_second == physics_ticks_per_second and
		settings.display_target_fps == target_fps and
		settings.graphics_disable_shader_effects == disable_shader_effects and
		settings.graphics_hide_baked_lights == hide_baked_lights and
		settings.graphics_disable_optional_2d_lights == disable_optional_2d_lights and
		settings.graphics_cheap_shading == cheap_shading and
		settings.graphics_prefer_cutscene_video == prefer_cutscene_video and
		settings.graphics_atlas_frame_step == atlas_frame_step
	)

func apply(settings: LullabySettings) -> void :
	settings.graphics_scaling_mode = scaling_3d_mode
	settings.graphics_render_scale = render_scale
	settings.graphics_shadows_enabled = shadows_enabled
	settings.graphics_positional_shadow_atlas_size = positional_shadow_atlas_size
	settings.graphics_positional_shadow_filter_quality = positional_shadow_filter_quality
	settings.graphics_msaa_3d_quality = msaa_3d_quality
	settings.graphics_screen_space_aa_quality = screen_space_aa_quality
	settings.graphics_post_processing = post_processing
	settings.graphics_ssao = ssao
	settings.graphics_ssil = ssil
	settings.graphics_anisotropic_filtering = anisotropic_filtering
	settings.graphics_mesh_lod_threshold = mesh_lod_threshold
	settings.graphics_light_distance_fade = light_distance_fade
	settings.graphics_physics_ticks_per_second = physics_ticks_per_second
	settings.display_target_fps = target_fps
	settings.graphics_disable_shader_effects = disable_shader_effects
	settings.graphics_hide_baked_lights = hide_baked_lights
	settings.graphics_disable_optional_2d_lights = disable_optional_2d_lights
	settings.graphics_cheap_shading = cheap_shading
	settings.graphics_prefer_cutscene_video = prefer_cutscene_video
	settings.graphics_atlas_frame_step = atlas_frame_step
