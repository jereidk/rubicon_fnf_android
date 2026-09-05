var camGameDarkness:FlxSprite;
var camGameDarknessTween:FlxTween;

function postCreate()
{
	camGameDarkness = new FlxSprite(-FlxG.width * 2, -FlxG.height * 2).makeGraphic(1, 1, FlxColor.BLACK);
	camGameDarkness.scale.set(FlxG.width * 8, FlxG.height * 8);
	add(camGameDarkness);
}

function onEvent(e)
{
	if (e.event.name == "Camera Alpha")
	{
		var params:Array = e.event.params;

		if (camGameDarknessTween != null)
			camGameDarknessTween.cancel();

		if (!params[2])
		{
			switch (params[0])
			{
				case 'camGame':
					camGameDarkness.alpha = 1 - params[1];
				case 'camHUD':
					camHUD.alpha = params[1];
				case 'camUI':
					camUI.alpha = params[1];
			}
		}
		else
		{
			switch (params[0])
			{
				case 'camGame':
					camGameDarknessTween = FlxTween.tween(camGameDarkness, {alpha: 1 - params[1]}, (Conductor.stepCrochet * params[3]) / 1000, {
						ease: CoolUtil.flxeaseFromString(params[4], params[5]),
						onComplete: function(twn:FlxTween)
						{
							camGameDarknessTween = null;
						}
					});
				case 'camHUD':
					camGameDarknessTween = FlxTween.tween(camHUD, {alpha: params[1]}, (Conductor.stepCrochet * params[3]) / 1000, {
						ease: CoolUtil.flxeaseFromString(params[4], params[5]),
						onComplete: function(twn:FlxTween)
						{
							camGameDarknessTween = null;
						}
					});
				case 'camUI':
					camGameDarknessTween = FlxTween.tween(camUI, {alpha: params[1]}, (Conductor.stepCrochet * params[3]) / 1000, {
						ease: CoolUtil.flxeaseFromString(params[4], params[5]),
						onComplete: function(twn:FlxTween)
						{
							camGameDarknessTween = null;
						}
					});
			}
		}
	}
}
