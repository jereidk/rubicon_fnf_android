import util.GenUtil;
import flixel.math.FlxRect;
import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import funkin.game.PlayState.ComboRating;
import funkin.savedata.FunkinSave;
import funkin.options.OptionsMenu;
import openfl.display.BlendMode;
import funkin.backend.MusicBeatState;
import ui.ResultJudgementUI;
import flixel.util.FlxStringUtil;
import ui.CurrencyPopupUI;
import ui.MessageWindowUI;
import funkin.backend.utils.DiscordUtil;

using StringTools;

var canControl:Bool = false;
var animationGrade:String = "BAD";
var judgements:Array<ResultJudgementUI> = [];
var curRank:Int = 0;
var comboRatingsList:Array<ComboRating> = [];
var maxBar:Float = 100;
var psi = PlayState.instance;
var zoomTween:FlxTween;
var doEffects:Bool = false;

FlxG.sound.load(Paths.sound('game/results/showresults'));
FlxG.sound.load(Paths.sound('game/results/results_rankup'));
FlxG.sound.load(Paths.sound('game/results/results_increase'));
FlxG.sound.load(Paths.sound('game/results/results_judgementdone'));
function create()
{
	DiscordUtil.changePresenceSince("In Results", null);
	camera = resultsCam = new FlxCamera();
	resultsCam.bgColor = FlxColor.BLACK;
	FlxG.cameras.add(resultsCam, false);

	if (psi.accuracy * 100 >= 99)
		animationGrade = "PERFECT";
	else if (psi.accuracy * 100 >= 90)
		animationGrade = "GREAT";
	else if (psi.accuracy * 100 >= 70)
		animationGrade = "GOOD";
	else
		animationGrade = "BAD";

	for (comborating in psi.comboRatings)
	{
		comboRatingsList.push(comborating);
	}

	switch (animationGrade)
	{
		case "PERFECT":
			FlxG.sound.load(Paths.sound('game/results/result-perfect-intro'));
			FlxG.sound.load(Paths.music('result-perfect-loop'));
		case "GREAT":
			FlxG.sound.load(Paths.sound('game/results/result-great-intro'));
			FlxG.sound.load(Paths.music('result-great-loop'));
		case "GOOD":
			FlxG.sound.load(Paths.sound('game/results/result-good-intro'));
			FlxG.sound.load(Paths.music('result-good-loop'));
		case "BAD":
			FlxG.sound.load(Paths.sound('game/results/result-bad-intro'));
			FlxG.sound.load(Paths.music('result-bad-loop'));
	}

	switch (animationGrade)
	{
		case "BAD":
			camera.zoom = 5.0;
			FlxTween.tween(camera, {zoom: 1.0}, 2.5, {ease: FlxEase.quadOut});
		default:
			backImage = 'ui/common/back';
	}

	bg = new FunkinSprite(0, 0).loadSprite(Paths.image('ui/freeplay/backgrounds/${PlayState.SONG.meta.name}'));
	bg.scale.set(1.5, 1.5);
	add(bg);
	bg.screenCenter();
	bg.color = FlxColor.BLACK;

	switch (animationGrade)
	{
		case "BAD":
			backImage = 'game/results/back-bad';
		default:
			backImage = 'ui/common/back';
	}

	bgGradient = new FunkinSprite().loadGraphic(Paths.image(backImage));
	add(bgGradient);
	bgGradient.flipX = false;
	bgGradient.blend = BlendMode.MULTIPLY;

	switch (animationGrade)
	{
		case "BAD":
			spotsImage = 'game/results/pattern-bad';
		default:
			spotsImage = 'game/results/pattern';
	}

	spotsBottom = new FlxBackdrop(Paths.image(spotsImage), FlxAxes.X, 0, 0);
	spotsBottom.alpha = 0.0;
	spotsBottom.blend = BlendMode.ADD;
	add(spotsBottom);
	spotsBottom.setPosition(0, FlxG.height - spotsBottom.height);

	spotsBottom.velocity.set(15, 0);

	resultCircle = new FunkinSprite().loadSprite(Paths.image('game/results/results-${Options.language}'));
	resultCircle.scale.set(1.5, 1.5);
	resultCircle.updateHitbox();
	resultCircle.setPosition(350, -50);
	insert(members.indexOf(bgGradient), resultCircle);
	resultCircle.alpha = 0.0;
	resultCircle.skew.x = -35;
	resultCircle.skew.y = -10;
	resultCircle.moves = true;
	resultCircle.angularVelocity = 15;

	switch (animationGrade)
	{
		case "BAD":
			cornerImage = 'game/results/corner-bad';
		default:
			cornerImage = 'game/results/corner';
	}

	if (animationGrade == "PERFECT")
	{
		pinkglow = new FunkinSprite(0, 0).loadSprite(Paths.image('game/results/pink'));
		pinkglow.setGraphicSize(pinkglow.width * FlxG.width, FlxG.height);
		add(pinkglow);
		pinkglow.alpha = 0.0;
		pinkglow.screenCenter();
		pinkglow.blend = BlendMode.ADD;

		starsBG = new FlxBackdrop(Paths.image('game/results/star'), FlxAxes.XY, 250, 250);
		starsBG.alpha = 0.0;
		starsBG.blend = BlendMode.ADD;
		add(starsBG);
		starsBG.velocity.set(50, 25);
		starsBG.moves = true;
		starsBG.angularVelocity = 5;
	}

	cornerB = new FunkinSprite(0, 0).loadSprite(Paths.image(cornerImage));
	add(cornerB);
	cornerB.flipX = true;
	cornerB.flipY = true;
	cornerB.setPosition(FlxG.width - cornerB.width, FlxG.height - cornerB.height);
	cornerB.y += 200;

	cornerT = new FunkinSprite(0, 0).loadSprite(Paths.image(cornerImage));
	add(cornerT);
	cornerT.y -= 200;

	switch (animationGrade)
	{
		case "PERFECT":
			gf = new FunkinSprite().loadSprite(Paths.image("game/results/gf_perfect"));
			gf.addAnim('start', 'PERFECT instance 1', 24, false, false, CoolUtil.parseNumberRange("0..72"));
			gf.addAnim('loop', 'PERFECT instance 1', 24, true, false, CoolUtil.parseNumberRange("73..95"));
			gf.scale.set(1.1, 1.1);
			gf.updateHitbox();
			gf.setPosition(-50, -85);
			add(gf);
			gf.animation.finishCallback = () ->
			{
				gf.playAnim('loop');
			};
			gf.visible = false;

		case "GREAT":
			gf = new FunkinSprite().loadSprite(Paths.image("game/results/gf_great"));
			gf.addAnim('start', 'GREAT instance 1', 24, false, false, CoolUtil.parseNumberRange("0..18"));
			gf.addAnim('loop', 'GREAT instance 1', 24, true, false, CoolUtil.parseNumberRange("19..57"));
			gf.scale.set(1.1, 1.1);
			gf.updateHitbox();
			gf.setPosition(175, -600);
			add(gf);
			gf.animation.finishCallback = () ->
			{
				gf.playAnim('loop');
			};
			gf.visible = false;

		case "GOOD":
			gf = new FunkinSprite().loadSprite(Paths.image("game/results/gf_good"));
			gf.addAnim('start', 'GOOD instance 1', 24, false, false, CoolUtil.parseNumberRange("0..81"));
			gf.addAnim('loop', 'GOOD instance 1', 24, true, false, CoolUtil.parseNumberRange("82..93"));
			gf.scale.set(1.3, 1.3);
			gf.updateHitbox();
			gf.setPosition(50, 100);
			add(gf);
			gf.animation.finishCallback = () ->
			{
				gf.playAnim('loop');
			};
			gf.visible = false;

		case "BAD":
			gf = new FunkinSprite().loadSprite(Paths.image("game/results/gf_bad"));
			gf.addAnim('start', 'BAD instance 1', 24, false, false);
			gf.scale.set(1.1, 1.1);
			gf.updateHitbox();
			gf.setPosition(-25, -400);
			add(gf);
			gf.visible = false;
	}

	for (i in 0...5)
	{
		var judgement:String = 'sick';
		switch (i)
		{
			case 0:
				judgement = 'sick';
			case 1:
				judgement = 'good';
			case 2:
				judgement = 'bad';
			case 3:
				judgement = 'shit';
			case 4:
				judgement = 'break';
		}
		var judgementCounter = new ResultJudgementUI(1320, 130 + (i * 100), judgement);
		add(judgementCounter);
		judgements.push(judgementCounter);
		judgementCounter.group.x += 200;
		judgementCounter.group.alpha = 0.0;
	}

	barMeterBack = new FunkinSprite(1820, 0).loadSprite(Paths.image('game/results/barback'));
	add(barMeterBack);
	barMeterBack.screenCenter(FlxAxes.Y);
	barMeterBack.x += 200;

	barMeter = new FunkinSprite(1820, 0).loadSprite(Paths.image('game/results/barfront'));
	add(barMeter);
	barMeter.color = 0xFFFFB2FF;
	barMeter.clipRect = new FlxRect(0, Std.int(barMeter.height), Std.int(barMeter.width), Std.int(barMeter.height));
	barMeter.screenCenter(FlxAxes.Y);
	barMeter.x += 200;

	scoreCount = new FlxText(950, 665, 850, '0 • Score');
	scoreCount.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	scoreCount.borderSize = 2.5;
	add(scoreCount);
	scoreCount.alpha = 0.0;
	scoreCount.color = FlxColor.GRAY;
	scoreCount.x += 200;
	scoreCount.origin.set(scoreCount.width, scoreCount.height);

	gauntletMultiCount = new FlxText(950, 702, 850, '(' + GenUtil.padMultiplier(curGauntletMultiplier) + ')');
	gauntletMultiCount.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	gauntletMultiCount.borderSize = 2.5;
	add(gauntletMultiCount);
	gauntletMultiCount.alpha = 0.0;
	gauntletMultiCount.x += 200;
	gauntletMultiCount.color = FlxColor.GRAY;
	gauntletMultiCount.origin.set(gauntletMultiCount.width, gauntletMultiCount.height / 2);

	accuracyCount = new FlxText(1150, 710, 650, '0.00% • Accuracy');
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
			accuracyCount.text = FlxMath.roundDecimal(num, 2) + '% • Accuracy';

			if (comboRatingsList != null && comboRatingsList.length > 0)
				for (e in comboRatingsList)
					if (((e.percent * 100) <= num))
					{
						increaseRank(e.rating);
						comboRatingsList.shift();
						curRank += 1;
					}

			barMeter.clipRect.y = Std.int(barMeter.height) - ((num / 100) * Std.int(barMeter.height));
			barMeter.clipRect = barMeter.clipRect;
		});
	}

	if (godukaEnabled)
		psi.songScore = Std.int(psi.songScore * 0.9);

	var performLateMulti:Bool = true;

	if (psi.songScore != 0)
	{
		performLateMulti = false;

		FlxTween.tween(scoreCount, {'scale.x': 1.5, 'scale.y': 1.5}, 0.5, {ease: FlxEase.expoOut});
		scoreCount.color = FlxColor.WHITE;

		FlxTween.num(0, psi.songScore, 2.0, {
			ease: FlxEase.quadOut,
			onComplete: function()
			{
				scoreCount.scale.set(1.75, 1.75);
				FlxTween.tween(scoreCount, {'scale.x': 1.50, 'scale.y': 1.5}, 1.0, {ease: FlxEase.expoOut});

				if (PlayState.isGauntletMode)
				{
					psi.songScore = FlxMath.bound(psi.songScore * curGauntletMultiplier, 0, 9999999);
					scoreCount.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(psi.songScore, 0), false) + ' • Score';
				}

				new FlxTimer().start(1.0, function(tmr:FlxTimer)
				{
					FlxTween.tween(scoreCount, {'scale.x': 1.0, 'scale.y': 1.0}, 1.0, {ease: FlxEase.sineInOut});
				});

				lastScoreCount = psi.songScore;
			}
		}, function(num:Float)
		{
			scoreCount.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(num, 0), false) + ' • Score';
		});

		if (PlayState.isGauntletMode)
		{
			if (gauntletMultiCount != null)
				FlxTween.color(gauntletMultiCount, 0.5, FlxColor.CYAN, FlxColor.YELLOW, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
			if (gauntletMultiCount != null)
				FlxTween.tween(gauntletMultiCount, {'scale.x': 1.5, 'scale.y': 1.5}, 0.5, {ease: FlxEase.expoOut});

			FlxTween.tween(gauntletMultiCount, {y: gauntletMultiCount.y - 50}, 1.0, {
				ease: FlxEase.expoIn,
				startDelay: 1.0,
				onComplete: function(twn:FlxTween)
				{
					scoreAddEffect = new FunkinSprite(1300, 610).loadSprite(Paths.image('game/results/scoreadd'));
					scoreAddEffect.blend = BlendMode.ADD;
					scoreAddEffect.scale.x = 1.35;
					add(GenUtil.glowPulse(scoreAddEffect, 1.0, 0.5, 0.75)).cameras = [resultsCam];

					gauntletMultiCount.visible = false;
				}
			});
			if (gauntletMultiCount != null)
				FlxTween.tween(gauntletMultiCount, {y: gauntletMultiCount.y - 50}, 1.0, {ease: FlxEase.expoIn, startDelay: 1.0});
			FlxTween.tween(accuracyCount, {y: accuracyCount.y - 26}, 0.5, {ease: FlxEase.sineOut, startDelay: 2.0});
		}
	}

	if (psi.songScore != 0 || psi.totalAccuracyAmount != 0)
	{
		tickerSnd.play();
		new FlxTimer().start(2.0, function(tmr:FlxTimer)
		{
			FlxG.sound.play(Paths.sound('game/results/results_judgementdone'), 0.75 * Options.volumeSFX).pitch = 1.0;
		});
	}

	for (i in 0...judgements.length)
	{
		new FlxTimer().start(4.0 - (judgements[i].judgementID * 0.35), function(tmr:FlxTimer)
		{
			judgements[i].countJudgement();
		});

		new FlxTimer().start(4.01 - (judgements[i].judgementID * 0.35), function(tmr:FlxTimer)
		{
			FlxTween.num(lastScoreCount, psi.songScore, 0.25, {
				ease: FlxEase.quadOut,
				onComplete: function()
				{
					if (lastScoreCount > 0 && i == 0 && performLateMulti)
					{
						mergeMultiLate();
					}
				},
			}, function(num:Float)
			{
				scoreCount.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(num, 0), false) + ' • Score';
				lastScoreCount = psi.songScore;

				if (lastScoreCount > 0)
				{
					scoreCount.color = FlxColor.WHITE;
					if (gauntletMultiCount.color == FlxColor.GRAY && PlayState.isGauntletMode)
						FlxTween.color(gauntletMultiCount, 0.5, FlxColor.CYAN, FlxColor.YELLOW, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
				}
			});
		});
	}

	new FlxTimer().start(4.75, function(tmr:FlxTimer)
	{
		var earnedCoins:Int = 1;

		earnedCoins += psi.hits.get('sick') * 2;
		earnedCoins += psi.hits.get('good') * 1;
		earnedCoins += Math.ceil(psi.score / 1000);

		var currency:CurrencyPopupUI = new CurrencyPopupUI('kyubeyCoins', earnedCoins);
		add(currency);

		new FlxTimer().start(2.0 + (queuedAchievements.length * 0.25), function(tmr:FlxTimer)
		{
			canControl = true;
		});
	});

	FlxTween.num(0.75, 1.25, 2.0, {
		ease: FlxEase.quadIn,
		onComplete: function(twn:FlxTween)
		{
			tickerSnd.stop();
		}
	}, function(num:Float)
	{
		tickerSnd.pitch = num;
	});
}

function mergeMultiLate()
{
	if (PlayState.isGauntletMode)
	{
		FlxTween.tween(gauntletMultiCount, {y: gauntletMultiCount.y - 50}, 1.0, {
			ease: FlxEase.expoIn,
			onComplete: function(twn:FlxTween)
			{
				scoreAddEffect = new FunkinSprite(1375, 625).loadSprite(Paths.image('game/results/scoreadd'));
				scoreAddEffect.blend = BlendMode.ADD;
				scoreAddEffect.scale.x = 1.1;
				add(GenUtil.glowPulse(scoreAddEffect, 1.0, 0.5, 0.75)).cameras = [resultsCam];

				gauntletMultiCount.visible = false;

				FlxG.sound.play(Paths.sound('game/results/results_judgementdone'), 0.75 * Options.volumeSFX).pitch = 1.0;

				psi.songScore = FlxMath.bound(psi.songScore * curGauntletMultiplier, 0, 9999999);
				scoreCount.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(psi.songScore, 0), false) + ' • Score';
			}
		});
		FlxTween.tween(gauntletMultiCount, {y: gauntletMultiCount.y - 50}, 1.0, {ease: FlxEase.expoIn});
		FlxTween.tween(accuracyCount, {y: accuracyCount.y - 26}, 0.5, {ease: FlxEase.sineOut, startDelay: 1.0});
	}
}

function increaseRank(newRank:String)
{
	if (curRank != 0)
	{
		rankIcon.playAnim(newRank);

		if (animationGrade != "BAD")
		{
			rankIncreaseFX = new FunkinSprite(1327, 723).loadSprite(Paths.image('game/results/rankadd'));
			rankIncreaseFX.blend = BlendMode.ADD;
			if (curRank <= 6)
				rankIncreaseFX.scale.x = 0.5;
			else if (curRank <= 7)
				rankIncreaseFX.scale.x = 0.75;
			else
				rankIncreaseFX.scale.x = 1.0;
			add(GenUtil.glowPulse(rankIncreaseFX, 0.75, 0.5, 0.75)).cameras = [resultsCam];

			FlxG.sound.play(Paths.sound('game/results/results_rankup'), 1.25 * Options.volumeSFX).pitch = 1.25 + (0.1 * curRank);
		}
	}
}

function startGFAnimation()
{
	var introLength:Float = 2.0;
	var songDelay:Float = 0.0;
	switch (animationGrade)
	{
		case "PERFECT":
			introLength = 1.6;
			songDelay = 2.0;

		case "GREAT":
			introLength = 4.5;
			songDelay = 3.0;

		case "GOOD":
			introLength = 1.5;
			songDelay = 1.25;

		case "BAD":
			introLength = 4.75;
	}

	new FlxTimer().start(songDelay, function(tmr:FlxTimer)
	{
		FlxG.sound.play(Paths.sound('game/results/result-${animationGrade.toLowerCase()}-intro')).onComplete = function()
		{
			CoolUtil.playMusic(Paths.music('result-${animationGrade.toLowerCase()}-loop'));
		};
	});

	new FlxTimer().start(introLength, function(tmr:FlxTimer)
	{
		gf.playAnim('start', true);
		gf.visible = true;
	});

	if (animationGrade == 'PERFECT')
	{
		var duration:Float = 3.35;

		new FlxTimer().start(duration, function(tmr:FlxTimer)
		{
			zoomTween?.cancel();
			camera.zoom = 1.0;
			zoomTween = FlxTween.tween(camera, {zoom: 1.2}, 1.0, {ease: FlxEase.expoIn});

			FlxTween.tween(whiteOverlay, {alpha: 0.35}, 0.75, {ease: FlxEase.expoIn, startDelay: 0.25});
		});

		new FlxTimer().start(duration + 1, function(tmr:FlxTimer)
		{
			FlxTween.cancelTweensOf(whiteOverlay);
			FlxTween.tween(whiteOverlay, {alpha: 0.0}, 1.5, {ease: FlxEase.quadOut});

			starsBG.alpha = 0.25;

			if (Options.flashingLights)
			{
				pinkglow.alpha = 1.0;
				FlxTween.tween(pinkglow, {alpha: 0.25}, 1.5, {ease: FlxEase.quadOut});
			}
			else
			{
				pingglow.alpha = 0.25;
			}

			if (!Options.lowMemoryMode)
			{
				var colors:Array<FlxColor> = [0xFFD00D2B, 0xFF72AEDA, 0xFFFFEC76, 0xFFFBA8BC, 0xFFA83658, 0xFF3A3A3A];

				for (i in 0...50)
				{
					var conf = new FunkinSprite(-75, 1080).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.velocity.set(FlxG.random.int(150, 850), -FlxG.random.int(600, 1300));
					conf.acceleration.set(-FlxG.random.int(25, 50), FlxG.random.int(750, 1000));
					conf.angularVelocity = FlxG.random.int(-250, 250);
					conf.color = colors[FlxG.random.int(0, colors.length - 1)];

					conf.moves = true;
				}

				for (i in 0...50)
				{
					var conf = new FunkinSprite(1960, 1080).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.velocity.set(-FlxG.random.int(150, 850), -FlxG.random.int(600, 1300));
					conf.acceleration.set(FlxG.random.int(25, 50), FlxG.random.int(750, 1000));
					conf.angularVelocity = FlxG.random.int(-250, 250);
					conf.color = colors[FlxG.random.int(0, colors.length - 1)];

					conf.moves = true;
				}
			}

			zoomTween?.cancel();
			camera.zoom = 1.10;
			zoomTween = FlxTween.tween(camera, {zoom: 1.0}, 1.0, {
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween)
				{
					doEffects = true;
				}
			});
		});

		/*
			new FlxTimer().start(3.0, function(tmr:FlxTimer)
			{
				new FlxTimer().start(0.05, function(tmr:FlxTimer)
				{
					var conf = new FunkinSprite(500, 500).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.x = FlxG.random.int(-1000, 1000);
					conf.y = FlxG.random.int(-1000, 1000);
					conf.velocity.y += FlxG.random.int(-1000, 1000);
				}, 0);
			});
		 */
	}
}

function update(elapsed:Float)
{
	if (controls.ACCEPT && canControl)
	{
		if (!PlayState.isGauntletMode)
		{
			FunkinSave.setSongHighscore(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation, {
				score: psi.songScore,
				misses: psi.misses,
				accuracy: psi.accuracy,
				hits: psi.hits,
				date: Date.now().toString(),
				customData: {
					rank: psi.curRating.rating,
					fcrank: GenUtil.returnFCStatus()
				}
			}, []);
		}
		canControl = false;

		doEffects = false;

		GenUtil.playUISound('confirm');

		FlxG.sound.music.fadeOut(0.75, 0.0);

		camFadeOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
		camFadeOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
		add(camFadeOverlay);
		camFadeOverlay.scrollFactor.set(0.0, 0.0);
		camFadeOverlay.alpha = 0.0;

		FlxG.save.data.freeplayUnlocked = true;

		godukaEnabled = false;
		godukaCooldown = -1;

		FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 1.5, {
			ease: FlxEase.quadInOut,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(0.5, function(tmr:FlxTimer)
				{
					if (!PlayState.isGauntletMode)
						GenUtil.sendScore(PlayState.SONG.meta.customValues.gjid, psi.songScore, 'null');

					if (!PlayState.isGauntletMode)
					{
						if (PlayState.isStoryMode)
						{
							FlxG.save.data.unlockableSongs.push(PlayState.SONG.meta.name);
							FlxG.save.data.curStoryProgress += 1;
							if (PlayState.SONG.meta.name == 'out-of-time')
							{
								if (!FlxG.save.data.unlockableSongs.contains('meguca') && !FlxG.save.data.viewedMenu.contains(1))
								{
									FlxG.save.data.viewedMenu.push(1);
									FlxG.save.flush();
								}

								FlxG.save.data.unlockableSongs.push('meguca');

								FlxG.save.data.curStoryProgress = 0;

								FlxG.save.data.accoladesUnlocked = true;

								nextact = new FunkinSprite(0, 0).loadSprite(Paths.image('game/results/act1end'));
								add(nextact);
								nextact.alpha = 0.0;
								FlxTween.tween(nextact, {alpha: 1.0}, 3.0, {
									ease: FlxEase.quadIn,
									onComplete: function(twn:FlxTween)
									{
										FlxTween.tween(nextact, {alpha: 0.0}, 1.0, {
											ease: FlxEase.quadIn,
											startDelay: 1.0,
											onComplete: function(twn:FlxTween)
											{
												psi.endingSong = true;
												psi.nextSong();
											}
										});
									}
								});
							}
							else
							{
								psi.endingSong = true;
								psi.nextSong();
							}
						}
						else
						{
							switch (PlayState.SONG.meta.name)
							{
								case 'meguca':
									FlxG.save.data.unlockableSongs.push('reconnect');
								case 'reconnect':
									FlxG.save.data.unlockableSongs.push('stardom');
									FlxG.save.data.gauntletUnlocked = true;
								case 'stardom':
									FlxG.save.data.galleryUnlocked = true;
							}

							psi.endingSong = true;
							psi.nextSong();
						}
					}
					else
					{
						MusicBeatState.skipTransIn = true;
						MusicBeatState.skipTransOut = true;

						// if (curGauntletGamemode == 'Standard')
						// {
						//	psi.endingSong = true;
						///	psi.nextSong();
						// }

						if (PlayState.storyPlaylist.length >= 2)
						{
							MusicBeatState.skipTransIn = true;
							MusicBeatState.skipTransOut = true;
							if (curGauntletGamemode == 'Standard')
							{
								psi.endingSong = true;
								psi.nextSong();
							}
							else
							{
								PlayState.campaignScore += psi.songScore;
								PlayState.campaignMisses += psi.misses;
								FlxG.switchState(new ModState("HQGauntletTransition", {endGauntlet: false}));
							}
						}
						else
						{
							MusicBeatState.skipTransIn = true;
							MusicBeatState.skipTransOut = true;
							PlayState.campaignScore += psi.songScore;
							PlayState.campaignMisses += psi.misses;

							FlxG.switchState(new ModState("HQGauntletTransition", {endGauntlet: true}));
						}
					}
				});
			}
		});
	}
}

function beatHit()
{
	if (doEffects)
	{
		if ((curBeat % 2) == 0)
		{
			zoomTween?.cancel();
			camera.zoom = 1.01;
			zoomTween = FlxTween.tween(camera, {zoom: 1.0}, 0.5, {ease: FlxEase.quadOut});

			if (Options.flashingLights)
			{
				pinkglow.alpha = 0.35;
				FlxTween.tween(pinkglow, {alpha: 0.25}, 0.75, {ease: FlxEase.quadOut});
			}
		}
	}
}
