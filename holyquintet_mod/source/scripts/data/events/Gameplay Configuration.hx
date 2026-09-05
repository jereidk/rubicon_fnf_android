import openfl.display.BlendMode;

function create()
{
}

function postCreate()
{
}

function update(elapsed:Float)
{
}

function onEvent(e)
{
	if (e.event.name == "Gameplay Configuration")
	{
		var params:Array = e.event.params;

		switch (params[0])
		{
			case 'Disable Drain':
				pauseTargetScoreMech = true;

			case 'Enable Drain':
				pauseTargetScoreMech = false;
		}

		switch (params[1])
		{
			case 'Disable Input':
				disablePlayerInput = true;

			case 'Enable Input':
				disablePlayerInput = false;
		}

		switch (params[2])
		{
			case 'No':
				canReset = false;

			case 'Yes':
				if (Options.resetButtonEnabled) canReset = true;
		}
	}
}
