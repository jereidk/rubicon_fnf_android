extends RefCounted
## Referenced via preload(), not class_name: the global script class cache
## only updates after the editor rescans the project, which headless test
## runs don't trigger, causing "Identifier not declared" false negatives.
## Ports funkin/backend/utils/CoolUtil.hx — a base CodenameEngine class
## (confirmed against its public source, github.com/CodenameCrew/
## CodenameEngine, since it's not something the Holy Quintet mod itself
## overrides and so was never part of this port's own mod-source
## extraction). Only fpsLerp/getFPSRatio are ported: the only pieces this
## port currently needs (this screen's own camera-zoom-style pulse decay).
## The real file is ~1500 lines of general grab-bag utilities — porting
## all of it with nothing yet calling most of it would be speculative.
## Add more functions here only when a real call site needs them, each
## confirmed against the same source rather than guessed.

static func get_fps_ratio(ratio: float, delta: float) -> float:
	return 1.0 - pow(1.0 - ratio, delta * 60.0)


static func fps_lerp(v1: float, v2: float, ratio: float, delta: float) -> float:
	return lerpf(v1, v2, get_fps_ratio(ratio, delta))
