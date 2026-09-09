// Not the best but I wrote it just for me lol

var curModulo:Int = 16;
var camStrength:Float = 1.0;
var waitTilNextStep:Bool = false;
var lastStepBoppedOn:Float = 0;
var curOffset:Float = 0;

function update(elapsed:Float)
{
	if (FlxG.keys.justPressed.SPACE)
	{
		charterBG.scale.set(1.5, 1.5);

		for (e in rightEventsGroup.members)
		{
			for (event in e.events)
			{
				if (event.name == "Camera Modulo Change")
				{
					if (Math.round(Conductor.getStepForTime(Conductor.songPosition)) > Math.round(Conductor.getStepForTime(event.time)))
					{
						curModulo = event.params[0];
						camStrength = event.params[1];
						curOffset = event.params[3];
					}
				}
			}
		}
	}

	for (e in rightEventsGroup.members)
	{
		for (event in e.events)
		{
			if (event.name == "Camera Modulo Change")
			{
				if (Math.round(Conductor.getStepForTime(Conductor.songPosition)) == Math.round(Conductor.getStepForTime(event.time)))
				{
					curModulo = event.params[0];
					camStrength = event.params[1];
					curOffset = event.params[3];
				}
			}
		}
	}

	if (waitTilNextStep && (curStep + curOffset) != lastStepBoppedOn)
	{
		waitTilNextStep = false;
	}

	if ((((curStep + curOffset) % curModulo) == 0) && !waitTilNextStep)
	{
		charterBG.scale.set(charterBG.scale.x + (0.03 * camStrength), charterBG.scale.y + (0.03 * camStrength));
		waitTilNextStep = true;
		lastStepBoppedOn = curStep + curOffset;
	}

	charterBG.scale.x = lerp(charterBG.scale.x, 1.5, 0.05);
	charterBG.scale.y = lerp(charterBG.scale.y, 1.5, 0.05);
}
