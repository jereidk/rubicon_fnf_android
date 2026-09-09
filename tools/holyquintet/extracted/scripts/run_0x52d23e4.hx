import ui.StatusEffectUI;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import funkin.backend.scripting.events.sprite.PlayAnimEvent;

public var timeStop_Dura:Float = -1;
public var bleed_Dura:Float = -1;
public var bleed_Stack:Int = 0;
public var reducedRecovery_Dura:Float = -1;
public var reducedRecovery_Stack:Int = 0;
public var divineprotection_Dura:Float = -1;
public var divineprotection_Stack:Int = 0;
var statusIcons:Array<StatusEffectUI> = [];

function update(elapsed:Float)
{
	if (Options.devMode)
	{
		if (FlxG.keys.pressed.CONTROL)
		{
			bleed_Dura = 0;
			bleed_Stack = 0;
			reducedRecovery_Dura = 0;
			reducedRecovery_Stack = 0;
		}
	}

	if (timeStop_Dura >= 0)
	{
		timeStop_Dura = FlxMath.bound(timeStop_Dura - (elapsed * 1.0), 0, 1.5);

		for (strum in playerStrums)
		{
			strum.playAnim('static');
			strum.color = FlxColor.GRAY;
		}

		if (timeStop_Dura == 0)
		{
			timeStop_Dura = -1;
			clearStatusEffect('timeStop');
		}
	}

	if (bleed_Dura >= 0)
	{
		bleed_Dura = FlxMath.bound(bleed_Dura - (elapsed * 1.0), 0, 99);
		bleed_Stack = Math.ceil(bleed_Dura / 5);

		if (health >= 0.01)
			health -= (0.085 * bleed_Stack) * elapsed;

		if (bleed_Dura == 0)
		{
			bleed_Dura = -1;
			clearStatusEffect('bleed');
		}
	}

	if (reducedRecovery_Dura >= 0)
	{
		reducedRecovery_Dura = FlxMath.bound(reducedRecovery_Dura - (elapsed * 1.0), 0, 99);
		reducedRecovery_Stack = Math.ceil(reducedRecovery_Dura / 25);

		if (reducedRecovery_Dura == 0)
		{
			reducedRecovery_Dura = -1;
			clearStatusEffect('reducedRecovery');
		}
	}

	if (divineprotection_Dura >= 0)
	{
		divineprotection_Dura = 99;

		if (health <= 0.5)
			health = 0.5;

		purity = 1.0;

		if (divineprotection_Dura == 0)
		{
			divineprotection_Dura = -1;
			clearStatusEffect('divineProtection');
		}
	}
}

public function inflictStatusEffect(statusEffect:String, duration:Float, ?e:Dynamic)
{
	switch (statusEffect)
	{
		case 'timeStop':
			timeStop_Dura = duration;

		case 'bleed':
			if (bleed_Dura >= 0)
				bleed_Dura = FlxMath.bound(bleed_Dura + duration, 0, 99);
			else
				bleed_Dura = duration;

		case 'reducedRecovery':
			if (reducedRecovery_Dura >= 0)
				reducedRecovery_Dura = FlxMath.bound(reducedRecovery_Dura + duration, 0, 99);
			else
				reducedRecovery_Dura = duration;

		case 'divineProtection':
			divineprotection_Dura = 99;
	}

	var addNewStatus:Bool = true;

	for (status in statusIcons)
	{
		if (status.effect == statusEffect)
			addNewStatus = false;
	}

	if (addNewStatus)
		for (status in statusIcons)
		{
			if (Options.downscroll)
				status.group.y += 50;
			else
				status.group.y -= 50;
		}

	if (addNewStatus)
	{
		var newStatus:StatusEffectUI = new StatusEffectUI(statusEffect, 0);
		insert(members.indexOf(soulgem_sanityOverlay) - 1, newStatus);
		statusIcons.push(newStatus);

		newStatus.group.cameras = [camUI];
	}

	for (i in 0...statusIcons.length)
	{
		statusIcons[i].group.y = 0;

		if (Options.downscroll)
			statusIcons[i].group.y += 50 * i;
		else
			statusIcons[i].group.y -= 50 * i;
	}
}

public function clearStatusEffect(statusEffect:String)
{
	PlayState.instance.scripts.call('clearStatusEffect', [statusEffect]);

	switch (statusEffect)
	{
		case 'timeStop':
			for (strum in playerStrums)
			{
				strum.playAnim('static');
				strum.color = FlxColor.WHITE;
			}
	}

	for (status in statusIcons)
	{
		if (status.effect == statusEffect)
		{
			statusIcons.remove(status);
			status.destroy();
			remove(status, true);
		}
	}

	for (i in 0...statusIcons.length)
	{
		statusIcons[i].group.y = 0;

		if (Options.downscroll)
			statusIcons[i].group.y += 50 * i;
		else
			statusIcons[i].group.y -= 50 * i;
	}
}
