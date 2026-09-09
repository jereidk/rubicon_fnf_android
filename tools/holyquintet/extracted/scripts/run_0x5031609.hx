 Accuracy');
	accuracyCount.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	accuracyCount.borderSize = 2.5;
	add(accuracyCount);
	accuracyCount.alpha = 0.0;
	accuracyCount.color = FlxColor.GRAY;
	accuracyCount.x += 200;
	accuracyCount.origin.set(accuracyCount.width, accuracyCount.height);

	rankIcon = new FunkinSprite(1350, 775).loadGraphic(Paths.image('game/results/ranks'), true, 358, 135);
	rankIcon.addAnim('SSS', null, 0, false, false, [0]);
	rankIcon.addAnim('SS', null, 0, false, false, [1]);
	rankIcon.addAnim('S', null, 0, false, false, [2]);
	rankIcon.addAnim('A', null, 0, false, false, [3]);
	rankIcon.addAnim('B', null, 0, false, false, [4]);
	rankIcon.addAnim('C', null, 0, false, false, [5]);
	rankIcon.addAnim('D', null, 0, false, false, [6]);
	rankIcon.addAnim('E', null, 0, false, false, [7]);
	rankIcon.addAnim('F', null, 0, false, false, [8]);
	add(rankIcon);
	rankIcon.alpha = 0.0;
	rankIcon.x += 200;
	rankIcon.playAnim('F');

	if (PlayState.isGauntletMode)
	{
		scoreAddEffect = new FunkinSprite(1300, 610).loadSprite(Paths.image('game/results/scoreadd'));
	}

	tickerSnd = new FlxSound().loadEmbedded(Paths.sound('game/results/results_increase'), true);
	tickerSnd.volume = 1 * Options.volumeSFX;
	FlxG.sound.list.add(tickerSnd);

	if (bg != null)
		FlxTween.color(bg, 2.5, FlxColor.BLACK, FlxColor.GRAY, {ease: FlxEase.quadInOut});

	whiteOverlay = new FlxSprite(-FlxG.width * 2, -FlxG.height * 2).makeGraphic(FlxG.width * 6, FlxG.height * 6, FlxColor.WHITE);
	whiteOverlay.alpha = 0.0001;
	add(whiteOverlay);
	whiteOverlay.blend = BlendMode.ADD;
	whiteOverlay.alpha = 0.0;

	startGFAnimation();

	switch (animationGrade)
	{
		case "PERFECT":
			countDelay = 0.0;
			showDelay = 0.01;
		case "GREAT":
			countDelay = 0.0;
			showDelay = 0.01;
		case "GOOD":
			countDelay = 0.0;
			showDelay = 0.01;
		case "BAD":
			countDelay = 0.3;
			showDelay = 2.0;
		default:
			countDelay = 0.0;
			showDelay = 0.01;
	}

	new FlxTimer().start(showDelay, function(tmr:FlxTimer)
	{
		FlxTween.tween(cornerT, {y: cornerT.y + 200}, 3.0, {ease: FlxEase.expoOut});
		FlxTween.tween(cornerB, {y: cornerB.y - 200}, 3.0, {ease: FlxEase.expoOut});

		FlxTween.tween(spotsBottom, {alpha: 0.1}, 3.0, {ease: FlxEase.expoOut});

		FlxTween.tween(barMeterBack, {x: barMeterBack.x - 200}, 1.0, {ease: FlxEase.expoOut});
		FlxTween.tween(barMeter, {x: barMeter.x - 200}, 1.0, {ease: FlxEase.expoOut});

		FlxTween.tween(accuracyCount, {x: accuracyCount.x - 200, alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});
		FlxTween.tween(scoreCount, {x: scoreCount.x - 200, alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});

		if (PlayState.isGauntletMode)
			FlxTween.tween(gauntletMultiCount, {x: gauntletMultiCount.x - 200, alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});

		FlxTween.tween(rankIcon, {x: rankIcon.x - 200, alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});

		for (judgement in judgements)
			FlxTween.tween(judgement.group, {x: judgement.group.x - 200, alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});

		resultCircle.x += 600;
		FlxTween.tween(resultCircle, {x: resultCircle.x - 600, alpha: 0.5}, 3.0, {ease: FlxEase.expoOut});

		if (PlayState.isGauntletMode)
		{
			accuracyCount.origin.set(accuracyCount.width, 0);
			accuracyCount.y += 26;
		}

		FlxG.sound.play(Paths.sound('game/results/showresults'), 0.75 * Options.volumeSFX);
	});

	new FlxTimer().start(countDelay, function(tmr:FlxTimer)
	{
		startInfoAnimation();
	});
}

function postCreate()
{
}

var lastScoreCount:Int = 0;

function startInfoAnimation()
{
	if (psi.totalAccuracyAmount != 0)
	{
		FlxTween.tween(accuracyCount, {'scale.x': 1.5, 'scale.y': 1.5}, 0.5, {ease: FlxEase.expoOut});
		accuracyCount.color = FlxColor.WHITE;

		FlxTween.num(0, FlxMath.roundDecimal(psi.accuracy * 100, 2), 2.0, {
			ease: FlxEase.quadOut,
			onComplete: function()
			{
				accuracyCount.scale.set(1.75, 1.75);
				FlxTween.tween(accuracyCount, {'scale.x': 1.50, 'scale.y': 1.5}, 1.0, {ease: FlxEase.expoOut});

				new FlxTimer().start(1.0, function(tmr:FlxTimer)
				{
					FlxTween.tween(accuracyCount, {'scale.x': 1.0, 'scale.y': 1.0}, 1.0, {ease: FlxEase.sineInOut});
				});
			}
		}, function(num:Float)
		{
			accuracyCount.text = FlxMath.roundDecimal(num, 2) + '% 