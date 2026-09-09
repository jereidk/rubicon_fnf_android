import ui.ClearConditionUI;

var adjustColorShader:CustomShader;

function create()
{
	if (PlayState.isGauntletMode)
		curMods = curGauntletMods;
	else
		curMods = [];

	// Disable Mechanics
	if (curMods.contains('NoMechanics') || (!PlayState.isGauntletMode && !Options.mechanics))
	{
		for (i in 0...PlayState.SONG.strumLines.length)
		{
			for (note in PlayState.SONG.strumLines[i].notes)
			{
				if (PlayState.SONG.meta.name == 'out-of-time' && (note.type == 1 || note.type == 2))
				{
					note.time = 9999999;
				}
			}
		}
	}

	// Bigger Judgement Windows
	PlayState.instance.ratingManager.ratingData[0].window *= 1.25;
	PlayState.instance.ratingManager.ratingData[1].window *= 1.25;
	PlayState.instance.ratingManager.ratingData[2].window *= 1.25;
	PlayState.instance.ratingManager.ratingData[3].window *= 1.25;

	// Smaller Judgement Windows
	if (curMods.contains('SmallerJudgementWindows'))
	{
		// for (rating in PlayState.instance.ratingManager.ratingData.length)
		// {
		//	rating.window /= 1.25;
		// }
		PlayState.instance.ratingManager.ratingData[0].window /= 1.25;
		PlayState.instance.ratingManager.ratingData[1].window /= 1.25;
		PlayState.instance.ratingManager.ratingData[2].window /= 1.25;
		PlayState.instance.ratingManager.ratingData[3].window /= 1.25;
	}

	// Random Note Colors
	if (curMods.contains('RandomNoteColors'))
	{
		adjustColorShader = new CustomShader("adjustColor");
		adjustColorShader.hue = FlxG.random.float(-255, 255);
		adjustColorShader.saturation = FlxG.random.float(-50, 50);
		adjustColorShader.contrast = 0.0;
	}

	// Combo Count Requirement
	if (curMods.contains('ComboCountRequirement'))
		requiredComboCount = Math.floor(PlayState.SONG.strumLines[1].notes.length / 3);

	if (curMods.contains('IncreasedSongSpeed'))
	{
		FlxG.timeScale = 1.2;
	}
}

function postCreate()
{
	// Combo Count Requirement
	if (curMods.contains('ComboCountRequirement'))
	{
		switch (PlayState.SONG.meta.customValues.uiStyle)
		{
			case 'MegucaUI':
				conditionCombo = new ClearConditionUI('ComboCountRequirement');
				add(conditionCombo.group).cameras = [camHUD];
				if (Options.downscroll)
					conditionCombo.group.y -= 997;
			default:
				conditionCombo = new ClearConditionUI('ComboCountRequirement');
				add(conditionCombo.group).cameras = [camHUD];
				if (Options.downscroll)
					conditionCombo.group.y -= 515;
		}
	}

	if (curMods.contains('ShuffledNoteReceptors'))
	{
		var originalXPositions:Array<Float> = [];
		for (i in 0...playerStrums.length)
			originalXPositions.push(playerStrums.members[i].x);

		FlxG.random.shuffle(originalXPositions);

		for (i in 0...originalXPositions.length)
			playerStrums.members[i].x = originalXPositions[i];
	}
}

function update(elapsed:Float)
{
	// Performance Regen
	if (curMods.contains('PerformanceRegen'))
	{
		if (!startingSong)
		{
			health += 0.020 * elapsed;
		}
	}

	// Stealth Notes
	if (curMods.contains('StealthNotes'))
	{
		var sudoElapsed:Float = elapsed;
		playerStrums.notes.forEachAlive((note) ->
		{
			var revealAt:Float = FlxG.height / 1.5;

			if (note.noteType == 'Bullet Note' || note.noteType == 'Timestop Note')
				revealAt = FlxG.height / 1.25;

			if (note.y <= revealAt)
			{
				if (note.isSustainNote && note.alpha < 0.6)
					note.alpha += 5.0 * sudoElapsed;
				if (!note.isSustainNote && note.alpha < 1.0)
					note.alpha += 10.0 * sudoElapsed;
			}
			else
				note.alpha = 0.0;
		});
	}

	// Zooming Notes
	if (curMods.contains('ZoomingNotes'))
	{
		var sudoElapsed:Float = elapsed;
		playerStrums.notes.forEachAlive((note) ->
		{
			var speedAt:Float = FlxG.height / 1.25;

			if (note.y <= speedAt && note.scrollSpeed != null)
			{
				note.scrollSpeed += 1.75 * sudoElapsed;
			}
			else
				note.scrollSpeed = playerStrums.members[0].getScrollSpeed() / 1;
		});
	}
}

function onStateSwitch(e)
{
	if (curMods.contains('IncreasedSongSpeed'))
	{
		FlxG.timeScale = 1.0;
	}
}

function onPlayerHit(e)
{
	e.cancel();

	if (e == null)
		return;

	if (curMods.contains('ComboCountRequirement'))
		if (combo >= requiredComboCount && !conditionCombo.cleared)
			conditionCombo.cleared = true;

	if (curMods.contains('DivineOrHigher'))
	{
		if (e.rating == 'bad' || e.rating == 'shit')
			killPlayer();
	}
}

function onPlayerMiss(e)
{
	if (curMods.contains('DivineOrHigher'))
	{
		killPlayer();
	}
}

function onDadHit(e)
{
	// Performance Regen
	if (curMods.contains('OpponentPerformanceDrain'))
	{
		if (!e.note.isSustainNote)
			health -= 0.040;
		else
			health -= 0.0050;
	}
}
