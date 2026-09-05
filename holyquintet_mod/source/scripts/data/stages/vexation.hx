dd(gauntletMod);
		gauntletMod.group.setPosition(1400, 300 + i * 65);
		gauntletSelectorGrp.push(gauntletMod);
		gauntletMod.group.cameras = [uiCam];
		gauntletMod.group.alpha = 0.0;

		gauntletMod.doEffect = false;
		gauntletMod.enabled = curGauntletMods.contains(gauntletMod.data.nameKey);
		scrollOriginalY.push(gauntletMod.group.y);
	}

	modeButton = new FunkinSprite(1455, 195).loadGraphic(Paths.image('ui/gauntlet/modeselector'));
	add(modeButton);

	modeButtonTxt = new FlxText(modeButton.x, modeButton.y, modeButton.width, i18n.tr('Gauntlet/ModeSelector/Leaderboards'));
	modeButtonTxt.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	modeButtonTxt.borderSize = 3.0;
	add(modeButtonTxt);
	GenUtil.alignToCenter(modeButtonTxt, modeButton);

	gauntletStart_Button = new ButtonUI(1435, 910, 'basic');
	gauntletStart_Button.text = i18n.tr('Gauntlet/Start/Start');
	add(gauntletStart_Button);

	gauntletMeterBG = new FunkinSprite(19, 29).loadGraphic(Paths.image('ui/gauntlet/meter'));
	add(gauntletMeterBG);
	gauntletMeterBG.alpha = 0.5;
	gauntletMeterBG.blend = BlendMode.ADD;

	gauntletMeter = new FunkinSprite(19 + 87, 29 + 34).loadGraphic(Paths.image('ui/gauntlet/meter_bar'));
	add(gauntletMeter);
	gauntletMeter.clipRect = new FlxRect(0, 0, Std.int(gauntletMeter.width), Std.int(gauntletMeter.height));
	gauntletMeter.clipRect.width = (curGauntletMultiplier / 10) * gauntletMeter.width;
	gauntletMeter.clipRect = gauntletMeter.clipRect;
	gauntletMeter.alpha = 0.5;
	gauntletMeter.blend = BlendMode.ADD;

	bestScoreDisplay = new GauntletStatDisplay('BestScore', 'LEFT');
	add(bestScoreDisplay);
	bestScoreDisplay.group.setPosition(-1575, 910);

	for (spr in [
		backing_Spr,
		modeButton,
		modeButtonTxt,
		gauntletMeterBG,
		gauntletMeter,
		multiDisplay.group,
		gauntletStart_Button.group,
		bestScoreDisplay.group
	])
		spr.cameras = [uiCam];

	changeSelection(0);
	switchGameModeType();
	updateBackgrounds(true);
	updateModDiffSelections(true);

	lbgroup = new FlxSpriteGroup();
	add(lbgroup);

	fadeoutSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	fadeoutSprite.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(fadeoutSprite).cameras = [uiCam];
	fadeoutSprite.alpha = 0.0;

	var grabScore:GJRequest = new GJRequest(RequestType.SCORES_FETCH(false, 1069472, 10, false));
	grabScore.onComplete.add(function(res)
	{
		if (res.success == 'true')
		{
			lbData = res;

			var pfps:Array<Dynamic> = [];
			for (i in 0...lbData.scores.length)
			{
				pfps.push(RequestType.USER_FETCH('${lbData.scores[i].user_id}'));
			}

			var grabpfp:GJRequest = new GJRequest(RequestType.BATCH(false, false, pfps));
			grabpfp.onComplete.add(function(res2)
			{
				for (i in 0...lbData.scores.length)
				{
					var bitmap = BitmapData.loadFromFile(StringTools.replace(res2.responses[i].users[0].avatar_url, '/1000/', '/64/'));
					bitmap.onComplete(function(bitmap)
					{
						pfp = new FunkinSprite(483, 193 + (85 * i)).loadGraphic(bitmap);
						add(pfp).cameras = [lbuiCam];
						profilePictures.push(pfp);
						pfp.visible = false;
					});
				}
			});
			grabpfp.send(false);
		}
	});
	grabScore.onError.add(e -> {});
	grabScore.send(false);

	blur = new BlurFilter(0.0);
	for (cam in FlxG.cameras.list)
	{
		if (cam != lbuiCam && cam != uiCam)
			blur.apply(cam);
	}

	if (FlxG.save.data.viewedMenu.contains(2))
	{
		FlxG.save.data.viewedMenu.remove(2);
		FlxG.save.flush();
	}
}

function update(elapsed)
{
	if (canControl)
	{
		if (controls.UP_P || controls.DOWN_P)
			changeSelection(controls.UP_P ? -1 : 1);

		if (controls.ACCEPT)
			confirmSelection();

		if (controls.BACK && !showingLeaderboards)
		{
			FlxG.switchState(new ModState("HQMainMenu"));
		}
		else if (controls.BACK && showingLeaderboards)
		{
			showingLeaderboards = false;
			exitLeaderboards();
		}
	}

	// FlxG.switchState(new ModState("HQMainMenu"));
}

function changeSelection(change:Int, ?skipSound:Bool = false)
{
	if (showingLeaderboards)
		return;

	var wrapped:Bool = false;

	if (change != 0 && !skipSound)
		GenUtil.playUISound('move');

	if (gm_curSel + change > gauntletSelectorGrp.length + 1)
		wrapped = true;
	if (gm_curSel + change < 0)
		wrapped = true;

	if (curGauntletGamemode == 'Endless' && change != 0)
	{
		if (gm_curSel == 0)
		{
			gm_curSel = gauntletSelectorGrp.length + 1;
			if (change > 0)
				wrapped = true;
		}
		else if (gm_curSel == gauntletSelectorGrp.length + 1)
		{
			gm_curSel = 0;
			if (change < 0)
				wrapped = true;
		}

		change = 0;
	}

	gm_curSel = FlxMath.wrap(gm_curSel + change, 0, gauntletSelectorGrp.length + 1);

	modeButton.color = curGauntletGamemode == 'Standard' ? 0xFF2E588C : 0xFF8B0647;
	modeButtonTxt.color = FlxColor.GRAY;

	for (gauntletMod in gauntletSelectorGrp)
		gauntletMod.selected = false;

	gauntletStart_Button.selected = false;

	if (gm_curSel == 0)
	{
		modeButton.color = curGauntletGamemode == 'Standard' ? 0xFF55C5EF : 0xFFFF0F7B;
		modeButtonTxt.color = FlxColor.WHITE;
	}
	else if (gm_curSel > 0 && gm_curSel <= gauntletSelectorGrp.length)
	{
		for (gauntletMod in gauntletSelectorGrp)
		{
			if (gauntletMod.ID == gm_curSel)
				gauntletMod.selected = true;
		}
	}
	else
	{
		gauntletStart_Button.selected = true;
	}

	if (!wrapped)
	{
		var scroll_OffsetY:Int = gm_curSel - 5;
		var targetAlpha:Float = 1.0;

		for (twn in scrollTweens)
			twn.cancel();

		for (i in 0...gauntletSelectorGrp.length)
		{
			if (i - FlxMath.bound(scroll_OffsetY, 0, 10) <= 8 && i - FlxMath.bound(scroll_OffsetY, 0, 8) >= 0)
				targetAlpha = 1.0;
			else
				targetAlpha = 0.0;

			scrollTweens.push(FlxTween.tween(gauntletSelectorGrp[i].group,
				{y: scrollOriginalY[i] - (65 * FlxMath.bound(scroll_OffsetY, 0, 8)), alpha: targetAlpha}, 0.5, {ease: FlxEase.expoOut}));
		}
	}
}

function confirmSelection()
{
	if (showingLeaderboards)
		return;
	if (gm_curSel == 0 && !showingLeaderboards)
	{
		GenUtil.playUISound('confirm');
		showingLeaderboards = true;
		showLeaderboards();
		/*

			if (curGauntletGamemode == 'Standard')
				curGauntletGamemode = 'Endless';
			else
				curGauntletGamemode = 'Standard';
			switchGameModeType(true);
		 */
	}
	else if (gm_curSel > 0 && gm_curSel <= gauntletSelectorGrp.length)
	{
		updateModDiffSelections();
	}
	else if (!switchingBackgrounds)
	{
		beginGauntletMode('hard');
	}
}

var barTween:FlxTween;
var barLastNum:Float = -1;

function updateModDiffSelections(?setup:Bool = false)
{
	var doCounting:Bool = true;
	var oldMulti:Float = curGauntletMultiplier;
	if (barLastNum == -1)
		barLastNum = oldMulti;

	curGauntletMods = [];
	curGauntletMultiplier = 1.0;
	for (gauntletMod in gauntletSelectorGrp)
	{
		if (gauntletMod.selected && !gauntletMod.locked && !setup)
		{
			gauntletMod.enabled = !gauntletMod.enabled;
			FlxG.sound.play(Paths.sound(gauntletMod.enabled ? 'ui/gauntlet/mod_selected' : 'ui/gauntlet/mod_unselected'), 1.0 * Options.volumeSFX);
		}
		else if (gauntletMod.selected && gauntletMod.locked && !setup)
		{
			GenUtil.playUISound('error');
			doCounting = false;
		}

		if (gauntletMod.enabled)
		{
			curGauntletMods.push(gauntletMod.data.nameKey);
			if (!gauntletMod.data.affectTotalMulti)
				curGauntletMultiplier += gauntletMod.data.multiplier;
		}
	}

	pairStatus('HarderMechanics', 'InstantKillMechanics', 1.0);

	for (gauntletMod in gauntletSelectorGrp)
	{
		if (gauntletMod.enabled && gauntletMod.data.affectTotalMulti)
		{
			curGauntletMultiplier *= gauntletMod.data.multiplier;
		}
	}

	for (gauntletMod in gauntletSelectorGrp)
	{
		var lockMod:Bool = false;
		var theConfliction:String = '';

		for (i in 0...gauntletMod.data.conflictions.length)
		{
			gauntletMod.additionalConflicts = 0;
			if (curGauntletMods.contains(gauntletMod.data.conflictions[i]))
			{
				if (theConfliction == '')
				{
					theConfliction = gauntletMod.data.conflictions[i];
					gauntletMod.conflictedMod = theConfliction;
				}
				else if (theConfliction != '')
				{
					gauntletMod.additionalConflicts += 1;
					gauntletMod.conflictedMod = gauntletMod.conflictedMod;
				}
				lockMod = true;
			}

			if (lockMod)
				gauntletMod.locked = true;
			else
				gauntletMod.locked = false;
		}
	}

	if (setup)
		doCounting = false;

	if (doCounting)
	{
		multiDisplay.count(curGauntletMultiplier);
		updateBackgrounds();

		if (barTween != null)
			barTween?.cancel();
		barTween = FlxTween.num(barLastNum, curGauntletMultiplier, 1.0, {
			ease: FlxEase.sineOut
		}, function(num:Float)
		{
			gauntletMeter.clipRect.width = (num / 10) * gauntletMeter.width;
			gauntletMeter.clipRect = gauntletMeter.clipRect;
			barLastNum = num;
		});
	}
}

var switchTimer:FlxTimer;
var curGauntletBG:String = 'peaceful';

function updateBackgrounds(?skipDelay:Bool = false)
{
	var targetBG:String = 'peaceful';
	var targetColor:FlxColor = FlxColor.WHITE;

	switchingBackgrounds = true;

	var timeToWait:Float = 1.5;

	if (curGauntletMultiplier >= gauntletBackgroundThresholds[1])
	{
		targetBG = 'hopeless';
		targetColor = FlxColor.BLACK;
		timeToWait = 1.5;
	}
	else if (curGauntletMultiplier >= gauntletBackgroundThresholds[0])
	{
		targetBG = 'stressed';
		targetColor = FlxColor.GRAY;
	}

	if (switchTimer != null)
		switchTimer.cancel();

	if (skipDelay)
		timeToWait = 0.0;

	switchTimer = new FlxTimer().start(timeToWait, function(tmr:FlxTimer)
	{
		if (targetBG == 'peaceful' && curGauntletBG == 'stressed')
			FlxG.sound.play(Paths.sound('ui/gauntlet/stage_decrease'), 1.0 * Options.volumeSFX);
		if (curGauntletBG == 'peaceful' && targetBG == 'stressed')
			FlxG.sound.play(Paths.sound('ui/gauntlet/stage_increase'), 1.0 * Options.volumeSFX);
		if (curGauntletBG == 'peaceful' && targetBG == 'hopeless' || curGauntletBG == 'stressed' && targetBG == 'hopeless')
			new FlxTimer().start(0.15, function(tmr:FlxTimer)
			{
				FlxG.sound.play(Paths.sound('ui/gauntlet/stage_increasetofinal'), 1.0 * Options.volumeSFX);
			});

		if ((curGauntletBG == 'hopeless' && targetBG == 'peaceful') || curGauntletBG == 'hopeless' && targetBG == 'stressed')
			FlxG.sound.play(Paths.sound('ui/gauntlet/stage_decreasefromfinal'), 1.0 * Options.volumeSFX);

		if (skipDelay && targetBG == curGauntletBG)
		{
			skipDelay = false;
			curGauntletBG = 'stressed';
			targetBG = 'peaceful';
			switchTimer?.reset(timeToWait);
			FlxG.sound.play(Paths.sound('ui/gauntlet/stage_increase'), 1.0 * Options.volumeSFX);
		}

		if (targetBG != curGauntletBG)
		{
			if (targetBG == 'peaceful' || targetBG == 'stressed')
			{
				switchingBackgrounds = false;

				if (Options.gameplayShaders)
				{
					FlxTween.num(-0.75, 0.0, 1.5, {
						ease: FlxEase.cubeOut
					}, function(num:Float)
					{
						bloomShader.amt = num;
					});
				}
			}
			else
			{
				new FlxTimer().start(0.45, function(tmr:FlxTimer)
				{
					switchingBackgrounds = false;

					FlxG.camera.zoom = 2.5;
					FlxTween.tween(FlxG.camera, {zoom: 1.0}, 0.5, {ease: FlxEase.expoOut});

					if (Options.gameplayShaders)
					{
						FlxTween.num(-2.0, 0.0, 1.5, {
							ease: FlxEase.quadOut
						}, function(num:Float)
						{
							bloomShader.amt = num;
						});
					}
				});
			}

			var fadeOutTime:Float = 0.5;
			if (targetBG == 'hopeless')
				fadeOutTime = 0.15;

			for (bg in gauntletBGs)
				bg.fadeOut(fadeOutTime);

			for (bg in gauntletBGs)
			{
				if (bg.background == targetBG)
					bg.fadeIn(skipDelay);
			}

			if (skipDelay)
				bg_frontFog.color = targetColor;
			else
				FlxTween.color(bg_frontFog, 0.15, bg_frontFog.color, targetColor, {ease: FlxEase.cubeOut});
		}
		else
		{
			switchingBackgrounds = false;
		}

		curGauntletBG = targetBG;
	});
}

function switchGameModeType(?doDiffCheck:Bool = false)
{
	return;
	modeButton.color = curGauntletGamemode == 'Standard' ? 0xFF2E588C : 0xFF8B0647;
	modeButtonTxt.color = FlxColor.GRAY;
	modeButtonTxt.text = i18n.tr('Gauntlet/ModeSelector/Leaderboards');

	if (gm_curSel == 0)
	{
		modeButton.color = curGauntletGamemode == 'Standard' ? 0xFF55C5EF : 0xFFFF0F7B;
		modeButtonTxt.color = FlxColor.WHITE;
	}

	if (curGauntletGamemode == 'Standard')
	{
		// disableModsOverlay.alpha = 0.0;
		// endlessInfoText.alpha = 0.0;
	}
	else if (curGauntletGamemode == 'Endless')
	{
		// disableModsOverlay.alpha = 1.0;
		// endlessInfoText.alpha = 1.0;
		for (gauntletMod in gauntletSelectorGrp)
			gauntletMod.enabled = false;
		// updateScoreMutli();
	}

	if (doDiffCheck && curGauntletMultiplier != 1)
	{
		updateModDiffSelections();
	}

	if (doDiffCheck)
	{
		bestScoreDisplay.count(curGauntletGamemode == 'Standard' ? FlxG.save.data.bestGauntletScoreStandard : FlxG.save.data.bestGauntletScoreEndless);
	}
}

function beginGauntletMode(diff:String)
{
	canControl = false;
	/*
		gauntletLives = 5;
		if (getMod('OneLife').enabled)
			gauntletLives = 1;

		if (getMod('OneSongSkip').enabled)
			gauntletSkipAvaliable = true;
		else
			gauntletSkipAvaliable = false;

		gauntletChartDiff = diff;
	 */

	for (bg in gauntletBGs)
	{
		bg?.slideIn();
		bg.ambienceSnd?.stop();
	}

	FlxG.sound.play(Paths.sound('ui/gauntlet/start_$curGauntletBG'), 1.0 * Options.volumeSFX).persist = true;
	FlxG.sound.music?.fadeOut(1.5, 0.0);

	FlxG.camera.filters ??= [];
	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		FlxTween.num(-0.25, 0.0, 1.5, {
			ease: FlxEase.quadOut
		}, function(num:Float)
		{
			bloomShader.amt = num;
		});

		transverse = new CustomShader("Transverse");
		transverse.falloff = 10;
		transverse.blur = 0.05;
		FlxG.camera.addShader(transverse);
		FlxTween.num(10, 0.5, 2.5, {
			ease: FlxEase.quadOut
		}, function(num:Float)
		{
			transverse.falloff = num;
		});
	}

	FlxTween.tween(gauntletMeterBG, {x: gauntletMeterBG.x - 800}, 1.0, {ease: FlxEase.cubeOut});
	FlxTween.tween(gauntletMeter, {x: gauntletMeterBG.x - 800}, 1.0, {ease: FlxEase.cubeOut});
	FlxTween.tween(gauntletMeterBG, {y: gauntletMeterBG.y - 200}, 0.5, {ease: FlxEase.cubeOut});
	FlxTween.tween(gauntletMeter, {y: gauntletMeterBG.y - 200}, 0.5, {ease: FlxEase.cubeOut});

	FlxTween.num(0, -800, 1.0, {
		ease: FlxEase.cubeOut
	}, function(num:Float)
	{
		uiCam.scroll.x = num;
	});

	FlxTween.num(0, 50, 2.0, {
		ease: FlxEase.quadIn
	}, function(num:Float)
	{
		FlxG.camera.scroll.y = num;
	});

	FlxTween.tween(bestScoreDisplay.group, {x: bestScoreDisplay.group.x - 1600}, 1.0, {ease: FlxEase.cubeOut});

	FlxTween.num(FlxG.camera.zoom + 0.05, 1.0, 0.5, {
		ease: FlxEase.expoOut,
		onComplete: function(twn:FlxTween)
		{
			FlxTween.num(FlxG.camera.zoom, 5.0, 1.5, {
				ease: FlxEase.expoIn,
				onComplete: function(twn:FlxTween)
				{
					var songsList:Array<Dynamic> = [
						{name: "resonance", hide: false},
						{name: "partea", hide: false},
						// {name: "eternal star", hide: false},
						{name: "vexation