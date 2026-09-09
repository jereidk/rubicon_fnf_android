function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Dad Alt Animation":
				dad.altSuffix = '-' + params[1];
		}
	}
}
