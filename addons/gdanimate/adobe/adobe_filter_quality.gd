@tool
extends RefCounted
class_name AdobeFilterQuality


## Port de FilterQuality (maru FlxAnimateFrames.hx:679-707).
## Nivel de calidad de los filtros bakeados. Solo afecta al radio del blur
## (los demas filtros no tienen parametro de calidad).
enum Quality { HIGH = 0, MEDIUM = 1, LOW = 2, RUDY = 3 }


## Port de FilterQuality.getQualityFactor().
static func quality_factor(q: int) -> float:
	match q:
		Quality.MEDIUM: return 1.75
		Quality.LOW: return 2.0
		Quality.RUDY: return 2.25
		_: return 1.0


## Port de FilterQuality.getPixelFactor().
static func pixel_factor(q: int) -> float:
	match q:
		Quality.MEDIUM: return 16.0
		Quality.LOW: return 12.0
		Quality.RUDY: return 8.0
		_: return 1.0


## Factor de calidad que maru usa para el blur aplicado
## (MovieClipInstance.hx:148: `(quality == HIGH) ? 1.25 : quality.getQualityFactor()`).
static func applied_blur_factor(q: int) -> float:
	if q == Quality.HIGH:
		return 1.25
	return quality_factor(q)
