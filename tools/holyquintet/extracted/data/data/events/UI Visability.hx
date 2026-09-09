import openfl.display.BlendMode;

function postCreate()
{
}

function onEvent(e)
{
	if (e.event.name == "UI Visability")
	{
		var params:Array = e.event.params;

		var targets:Array<String> = [];

		if (params[0])
			targets.push('health');
		if (params[1])
			targets.push('score');
		if (params[2])
			targets.push('soulgem');
		if (params[3])
			targets.push('strums');

		if (!params[6])
			params[7] = 0.0001;

		for (target in targets)
		{
			switch (target)
			{
				case 'health':
					for (spr in healthBarGrp)
					{
						FlxTween.cancelTweensOf(spr, ['alpha']);
						FlxTween.tween(spr, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
							{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
					}
					for (spr in statTxtGrp)
					{
						FlxTween.cancelTweensOf(spr.group, ['alpha']);
						FlxTween.tween(spr.group, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
							{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
					}
				case 'score':
					for (spr in scoreGrp)
					{
						FlxTween.cancelTweensOf(spr, ['alpha']);
						FlxTween.tween(spr, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
							{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
					}
				case 'soulgem':
					for (spr in soulGemGrp)
					{
						FlxTween.cancelTweensOf(spr, ['alpha']);
						FlxTween.tween(spr, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
							{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
					}
				case 'strums':
					if (playerStrums != null)
						for (spr in playerStrums)
						{
							FlxTween.cancelTweensOf(spr, ['alpha']);
							FlxTween.tween(spr, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
								{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
						}
					if (cpuStrums != null)
						for (spr in cpuStrums)
						{
							FlxTween.cancelTweensOf(spr, ['alpha']);
							FlxTween.tween(spr, {alpha: params[5]}, Conductor.stepCrochet * params[7] / 1000,
								{ease: CoolUtil.flxeaseFromString(params[8], params[9])});
						}
			}
		}
	}
}
