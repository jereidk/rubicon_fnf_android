import util.GenUtil;
import flixel.util.FlxStringUtil;
import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import ui.CurrencyPopupUI;
import ui.MessageWindowUI;

var gt_curSel:Int = 0;
var canControl:Bool = false;
var bgGraphic:Int = 1;
var bgSnd:String = 'peaceful';
var failedGauntlet:Bool = false;
var avaliableGauntletMods:Array<String> = [];

FlxG.sound.load(Paths.sound("game/perfect_popup"));
FlxG.sound.load(Paths.sound("ui/gauntlet/stage_decreasefromfinal"));
FlxG.sound.load(Paths.sound('game/results/showresults'));
function create()
{
	gt_curSel = 0;

	if (curGauntletMultiplier > gauntletBackgroundThresholds[1])
	{
		bgGraphic = 3;
		bgSnd = 'hopeless';
	}
	else if (curGauntletMultiplier > gauntletBackgroundThresholds[0])
	{
		bgGraphic = 2;
		bgSnd = 'stressed';
	}

	if (FlxG.sound.music != null)
		FlxG.sound.music.stop();

	gauntletBG = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/transition/bg_stage${bgGraphic}'));
	add(gauntletBG);

	gauntletSound = new FlxSound().loadEmbedded(Paths.sound('ui/gauntlet/${bgSnd}_bg'), true, false);
	gauntletSound.volume = 0.0;
	FlxG.sound.list.add(gauntletSound);
	gauntletSound.fadeIn(1.5, gauntletSound.volume, 0.7 * Options.volumeMusic);

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	scoreBG = new FlxSprite(0, 0).makeGraphic(1, 1, 0xFF403B49);
	scoreBG.scale.set(FlxG.width * 6, FlxG.height * 0.70);
	add(scoreBG);
	scoreBG.alpha = 0.5;
	scoreBG.blend = BlendMode.MULTIPLY;
	scoreBG.screenCenter();

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	if (data.endGauntlet)
	{
		gauntletResultText = new FunkinSprite()
			.loadGraphic(Paths.image(failedGauntlet ? "ui/gauntlet/transition/gauntletfailedtxt" : "ui/gauntlet/transition/gauntletcompletetxt"));
		add(gauntletResultText);
		gauntletResultText.screenCenter();
		gauntletResultText.scale.set(1.5, 1.5);
		gauntletResultText.alpha = 0.0;
		gauntletResultText.angle = FlxG.random.bool(50) ? -10 : 10;

		gauntletScoreStatsText = new FlxText(0, 0, FlxG.width, i18n.tr('Gauntlet/FinalResults'));
		gauntletScoreStatsText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		gauntletScoreStatsText.borderSize = 3.0;
		add(gauntletScoreStatsText);
		gauntletScoreStatsText.alpha = 0.0;
		gauntletScoreStatsText.screenCenter();
		gauntletScoreStatsText.y += 150;

		gauntletScoreStatsText.text += '\n${i18n.tr('Gameplay/Score')}: ${FlxStringUtil.formatMoney(PlayState.campaignScore, false)}\n${i18n.tr('Gameplay/Breaks')}: ${PlayState.campaignMisses}';

		new FlxTimer().start(1.0, function(tmr:FlxTimer)
		{
			FlxG.sound.play(Paths.sound(failedGauntlet ? "ui/gauntlet/stage_decreasefromfinal" : "game/perfect_popup"), 1.0 * Options.volumeSFX);
			FlxTween.tween(gauntletResultText, {
				alpha: 1.0,
				'scale.x': 0.8,
				'scale.y': 0.8,
				angle: 0
			}, 0.3, {
				ease: FlxEase.quadIn,
				onComplete: function(twn:FlxTween)
				{
					add(GenUtil.glowPulse(gauntletResultText, 1.0, 0.5, 0.5));

					FlxTween.tween(gauntletResultText, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {
						ease: FlxEase.expoOut,
						onComplete: function(twn:FlxTween)
						{
							new FlxTimer().start(0.5, function(tmr:FlxTimer)
							{
								FlxTween.tween(gauntletScoreStatsText, {alpha: 1.0}, 0.5, {ease: FlxEase.expoOut, startDelay: 0.50});

								FlxTween.tween(gauntletResultText, {y: gauntletResultText.y - 150}, 1.0, {
									ease: FlxEase.quadInOut,
									onComplete: function(twn:FlxTween)
									{
										var earnedCoins:Int = failedGauntlet ? 50 : 1000;
										earnedCoins += Math.ceil(PlayState.campaignScore / 10000);
										var currency:CurrencyPopupUI = new CurrencyPopupUI('kyubeyCoins', earnedCoins);
										add(currency);

										canControl = true;
									}
								});
							});
						}
					});
				}
			});
		});
	}

	camFadeInOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	camFadeInOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(camFadeInOverlay);
	camFadeInOverlay.scrollFactor.set(0.0, 0.0);
	camFadeInOverlay.alpha = 1.0;

	FlxTween.tween(camFadeInOverlay, {alpha: 0.0}, 0.75, {ease: FlxEase.cubeOut});
}

function postCreate()
{
}

function update(elapsed:Float)
{
	if (FlxG.keys.justPressed.V)
		FlxG.switchState(new ModState("HQGauntlet"));

	if (canControl)
	{
		if (controls.ACCEPT)
		{
			if (data.endGauntlet)
			{
				canControl = false;

				GenUtil.playUISound('confirm');

				var scoreToUse = FlxG.save.data.bestGauntletScoreStandard;

				if (signedIntoGJ)
				{
					if (PlayState.campaignScore > scoreToUse)
					{
						var messageData = {
							nameKey: 'SendGauntletScore',
							mainTextKey: 'SendGauntletScore',
							leftTextKey: 'No',
							rightTextKey: 'Yes',
							icon: 'info',
							type: 'twochoice',
							leftAction: () -> {},
							rightAction: () ->
							{
								GenUtil.sendScore(1069472, PlayState.campaignScore, 'null');
							},
							completedAction: () ->
							{
								FlxG.save.data.bestGauntletScoreStandard = PlayState.campaignScore;

								FlxG.save.flush();

								GenUtil.playUISound('confirm');
								messageWindow.destroy();
								messageWindow = null;
								leaveScreen(false);
							},
							backAction: () ->
							{
								messageWindow.destroy();
								messageWindow = null;
								canControl = true;
							}
						}
						messageWindow = new MessageWindowUI(messageData);
						add(messageWindow);
					}
					else
						leaveScreen(false);
				}
				else
				{
					scoreToUse = PlayState.campaignScore;
					FlxG.save.data.bestGauntletScoreStandard = PlayState.campaignScore;
					FlxG.save.flush();
					leaveScreen(false);
				}
			}
			else
			{
				GenUtil.playUISound('confirm');
				confirmSelection();
			}
		}
		else if (controls.LEFT_P)
			changeSelection(-1);
		else if (controls.RIGHT_P)
			changeSelection(1);
	}
}

function changeSelection(change:Int)
{
	if (change != 0 && avaliableGauntletMods.length > 0)
		GenUtil.playUISound('move');

	if (avaliableGauntletMods.length <= 0)
	{
		leaveScreen(true);
	}
	else
	{
		gt_curSel = FlxMath.wrap(gt_curSel + change, 0, gauntletCards.length - 1);

		for (i in 0...gauntletCards.length)
			gauntletCards[i].selected = false;

		gauntletCards[gt_curSel].selected = true;
	}
}

function confirmSelection()
{
	canControl = false;

	if (!data.endGauntlet)
	{
		if (avaliableGauntletMods.length <= 0)
		{
			leaveScreen(true);
		}
		else
		{
			curGauntletMods.push(gauntletCards[gt_curSel].cardDataP.nameKey);
			leaveScreen(true);
		}
	}
}

function leaveScreen(continueRun:Bool)
{
	gauntletSound?.fadeOut(0.75, 0.0);

	camFadeOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	camFadeOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(camFadeOverlay);
	camFadeOverlay.scrollFactor.set(0.0, 0.0);
	camFadeOverlay.alpha = 0.0;

	FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 1.5, {
		ease: FlxEase.quadInOut,
		onComplete: function(twn:FlxTween)
		{
			new FlxTimer().start(0.5, function(tmr:FlxTimer)
			{
				if (continueRun)
				{
					if (PlayState.storyPlaylist.length >= 2)
					{
						PlayState.storyPlaylist.shift();
						PlayState.loadSong(PlayState.storyPlaylist[0], gauntletChartDiff);
						FlxG.switchState(new PlayState());
					}
					else
					{
						FlxG.switchState(new ModState("HQGauntlet"));
					}
				}
				else
				{
					FlxG.switchState(new ModState("HQGauntlet"));
				}
			});
		}
	});
}
