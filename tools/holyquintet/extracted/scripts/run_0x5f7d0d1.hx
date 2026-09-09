');
		firstText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER);
		firstText.borderSize = 3.0;
		add(firstText);
		firstText.cameras = [camUI];
		FlxTween.tween(firstText, {y: firstText.y - 10}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	}

	if (Options.middleScroll)
	{
		firstText.screenCenter(FlxAxes.X);
	}

	if (!Options.lowMemoryMode)
	{
		reflectionPlayer = new Character(bf.x, bf.y + 1175, 'gf-base', true);
		insert(members.indexOf(vexBGReflection), reflectionPlayer);
		reflectionPlayer.alpha = 0.5;
		reflectionPlayer.flipY = true;
		reflectionPlayer.useRenderTexture = true;

		reflectionOpponent = new Character(dad.x, dad.y + 660, 'kyoko-base', false);
		insert(members.indexOf(vexBGReflection), reflectionOpponent);
		reflectionOpponent.alpha = 0.5;
		reflectionOpponent.flipY = true;
		reflectionOpponent.useRenderTexture = true;
	}
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	if (!Options.lowMemoryMode)
	{
		reflectionPlayer.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);
		reflectionOpponent.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
	}

	if (camFX.visible)
	{
		kyubeySilo.playAnim(kyubey.getAnimName(), true, null, false, kyubey.globalCurFrame);
		kyokoSilo.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
		gfSilo.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);

		kyokoCutIn.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
		gfCutIn.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);

		if (camFXuseHUDzoom)
			camFX.zoom = camHUD.zoom * camHUD.zoomMultiplier;
	}
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		kyubeySpeaker.playAnim('bop', true);
		vexBG_sayaka.playAnim('bop', true);
		vexBG_mami.playAnim('bop', true);
		vexBG_madoka.playAnim('bop', true);
	}
}

function stepHit(curStep:Int)
{
}

function onGamePause(event)
{
}

function onSubstateClose(event)
{
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Light":
				switch (params[1])
				{
					case "Dim":
						for (spr in vexBGSprs)
							spr.color = 0xFF141414;

						vexBG_multi.visible = false;
						vexBG_add.visible = false;
						vexBG_rays.visible = false;
						vexBG_dust.visible = false;
						vexBG_pipes.visible = false;

					case "Bright":
						for (spr in vexBGSprs)
							spr.color = FlxColor.WHITE;

						vexBG_multi.alpha = 0.25;
						vexBG_add.alpha = 0.25;
						vexBG_rays.alpha = 1.0;
						vexBG_dust.alpha = 1.0;
						vexBG_pipes.alpha = 1.0;
						vexBG_multi.visible = true;
						vexBG_add.visible = true;
						vexBG_rays.visible = true;
						vexBG_dust.visible = true;
						vexBG_pipes.visible = true;

						if (!Options.lowMemoryMode)
						{
							if (sparksVideo.visible)
							{
								sparksVideo.alpha = 1.0;
								sparksVideo.resume();
							}
						}

					case "Tween Dim":
						for (spr in [
							vexBG,
							kyubeySpeaker,
							kyubey,
							vexBG_sayaka,
							vexBG_mami,
							vexBG_madoka,
							vexBG_pipes
						])
							FlxTween.color(spr, Conductor.stepCrochet * params[2] / 1000, spr.color, 0xFF141414, {ease: FlxEase.quadInOut});

						if (!Options.lowMemoryMode)
							FlxTween.color(vexBGReflection, Conductor.stepCrochet * params[2] / 1000, vexBGReflection.color, 0xFF141414,
								{ease: FlxEase.quadInOut});

						for (spr in [vexBG_multi, vexBG_add, vexBG_rays, vexBG_dust, vexBG_pipes])
							FlxTween.tween(spr, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});

						if (!Options.lowMemoryMode) FlxTween.tween(sparksVideo, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000,
							{ease: FlxEase.quadInOut});
				}
			case "FX 1":
				switch (params[1])
				{
					case "Start":
						camFX.visible = true;
						kyokoSilo.x = 1000;
						gfSilo.x = 400;

					case "Kyoko Show":
						FlxTween.tween(kyokoSilo, {x: 300, alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});

					case "Girlfriend Show":
						FlxTween.tween(gfSilo, {x: 1000, alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});

					case "Kyubey Show":
						FlxTween.tween(kyubeySilo, {alpha: 0.25}, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadOut});

					case "Slow Zoom":
						camFXuseHUDzoom = false;
						FlxTween.tween(kyubeySilo, {alpha: 0.75}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(kyokoSilo, {alpha: 0.5}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(gfSilo, {alpha: 0.5}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(camFX, {zoom: 1.5, 'scroll.y': 50}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});

					case "End FX":
						FlxTween.tween(camFX, {zoom: 2.5, 'scroll.y': 75}, Conductor.stepCrochet * 8 / 1000, {
							ease: FlxEase.expoIn,
							onComplete: function(twn:FlxTween)
							{
								camFXuseHUDzoom = true;
								camFX.visible = false;
								kyubeySilo.visible = false;
								kyokoSilo.visible = false;
								gfSilo.visible = false;
							}
						});
				}

			case "FX 2":
				switch (params[1])
				{
					case "Start":
						camFX.zoom = 1.0;
						camFX.scroll.y = 0;
						camFX.visible = true;
						gfCutIn.x = 1400;
						kyokoCutIn.x = 50;

						FlxTween.tween(cutinBG, {alpha: 0.75}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});

						FlxTween.tween(gfCutIn, {x: 1000}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.expoOut});
						FlxTween.tween(kyokoCutIn, {x: 400}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.expoOut});

						for (spr in [cutinBlue, cutinRed, gfCutIn, kyokoCutIn])
						{
							spr.alpha = 0.0;
							spr.scale.y = 0.0;
							FlxTween.tween(spr, {'scale.y': 1.0, alpha: 1.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						}
					case "End":
						camFX.zoom = 1.0;
						camFX.scroll.y = 0;
						camFX.visible = true;
						gfCutIn.x = 1000;
						kyokoCutIn.x = 400;

						FlxTween.tween(cutinBG, {alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});

						FlxTween.tween(gfCutIn, {x: 400}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						FlxTween.tween(kyokoCutIn, {x: 1400}, Conductor.stepCrochet * 8 / 1000, {
							ease: FlxEase.expoOut,
							onComplete: function(twn:FlxTween)
							{
								camFX.visible = false;
							}
						});

						for (spr in [cutinBlue, cutinRed, gfCutIn, kyokoCutIn])
						{
							spr.alpha = 1.0;
							spr.scale.y = 1.0;
							FlxTween.tween(spr, {'scale.y': 0.0, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						}
				}

			case "Sparks":
				switch (params[1])
				{
					case "Start":
						if (!Options.lowMemoryMode)
						{
							sparksVideo.play();
							sparksVideo.visible = true;
							FlxTween.tween(sparksVideo, {alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadInOut});
						}

					case "End":
						if (!Options.lowMemoryMode)
						{
							sparksVideo.pause();
							sparksVideo.alpha = 0.0;
							sparksVideo.visible = false;
						}
				}
			case "Hide Text":
				FlxTween.tween(firstText, {alpha: 0.0}, Conductor.stepCrochet * params[1] / 1000, {ease: FlxEase.sineInOut});
		}
	}
}

function onGamePause(e)
{
	if (!Options.lowMemoryMode)
	{
		if (sparksVideo.visible)
			sparksVideo.pause();
	}
}

function onSubstateClose(e)
{
	if (paused)
	{
		if (!Options.lowMemoryMode)
		{
			if (sparksVideo.visible)
				sparksVideo.resume();
		}
	}
}
