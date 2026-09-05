var alreadyCreatedSubState:Bool = false;

function postCreate()
{
	if (godukaEnabled)
		inflictStatusEffect('divineProtection', 99, null);
}

function update(elapsed:Float)
{
	if (Options.devMode)
	{
		if (FlxG.keys.justPressed.Z && FlxG.keys.pressed.CONTROL)
		{
			endSong();
		}
	}
}

function onSongEnd(e)
{
	e.cancel();
	persistentUpdate = false;
	paused = true;
	vocals.stop();
	if (FlxG.sound.music != null)
		FlxG.sound.music.stop();
	for (strumLine in strumLines.members)
		strumLine.vocals.stop();

	if (!alreadyCreatedSubState)
	{
		alreadyCreatedSubState = true;
		resultsSubState = new ModSubState("HQResults");
		openSubState(resultsSubState);
	}
}

function onGameOver(e)
{
	e.cancel();

	if (alreadyDied)
		return;

	if (PlayState.SONG.meta.name == 'meguca')
	{
		disablePlayerInput = true;
		canPause = false;
		persistentUpdate = false;
		persistentDraw = false;
		paused = true;

		vocals.stop();
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		for (strumLine in strumLines.members)
			strumLine.vocals.stop();

		camHUD.visible = false;
		camUI.visible = false;

		bf.playAnim('firstDeath', true);
		bf.animation.finishCallback = () ->
		{
			camFadeOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
			camFadeOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
			add(camFadeOverlay);
			camFadeOverlay.scrollFactor.set(0.0, 0.0);
			camFadeOverlay.alpha = 0.0;
			bf.visible = false;

			FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 1.5, {
				ease: FlxEase.quadInOut,
				onComplete: function(twn:FlxTween)
				{
					gameOverSubState = new ModSubState("HQGameoverMeguca");
					openSubState(gameOverSubState);
				}
			});

			bf.animation.finishCallback = null;
		};

		FlxG.sound.play(Paths.sound("meguca_gfdies"));
	}
	else
	{
		disablePlayerInput = true;
		canPause = false;
		persistentUpdate = false;
		persistentDraw = false;
		paused = true;
		gameOverSubState = new ModSubState("HQGameover");
		openSubState(gameOverSubState);

		vocals.stop();
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		for (strumLine in strumLines.members)
			strumLine.vocals.stop();
	}
	alreadyDied = true;

	if (PlayState != null)
		PlayState.deathCounter += 1;
}
