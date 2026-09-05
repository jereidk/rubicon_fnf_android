import openfl.display.BlendMode;
import util.GenUtil;

FlxG.sound.load(Paths.sound("game/perfect_popup"));
FlxG.sound.load(Paths.sound("gf/gfvo_perfect"));
function postCreate()
{
	perfectText = new FunkinSprite().loadGraphic(Paths.image("game/perfect"));
	add(perfectText);
	perfectText.cameras = [camUI];
	perfectText.screenCenter();
	perfectText.scale.set(1.5, 1.5);
	perfectText.alpha = 0.0;
	perfectText.angle = FlxG.random.bool(50) ? -10 : 10;
}

function onEvent(e)
{
	if (e.event.name == "Perfect")
	{
		if (misses == 0)
		{
			FlxG.sound.play(Paths.sound("game/perfect_popup"), 1.0 * Options.volumeSFX);
			FlxG.sound.play(Paths.sound("gf/gfvo_perfect"), 1.0 * Options.volumeSFX);

			FlxTween.tween(perfectText, {
				alpha: 1.0,
				'scale.x': 0.8,
				'scale.y': 0.8,
				angle: 0
			}, 0.3, {
				ease: FlxEase.quadIn,
				onComplete: function(twn:FlxTween)
				{
					add(GenUtil.glowPulse(perfectText, 1.0, 0.5, 0.5)).cameras = [camUI];

					FlxTween.tween(perfectText, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {
						ease: FlxEase.expoOut,
						onComplete: function(twn:FlxTween)
						{
							new FlxTimer().start(Conductor.stepCrochet * 2 / 1000, function(tmr:FlxTimer)
							{
								FlxTween.tween(perfectText, {alpha: 0.0}, 1.5, {
									ease: FlxEase.quadIn,
									onComplete: function(twn:FlxTween)
									{
									}
								});
							});
						}
					});
				}
			});
		}
	}
}
