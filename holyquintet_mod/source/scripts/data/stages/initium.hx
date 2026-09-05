import ui.StatTextUI;
import util.GenUtil;
import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.util.FlxAxes;
import openfl.display.BlendMode;

importScript('data/scripts/dropshadow-effect');
var doTut:Bool = true;
var inTut:Bool = true;
var canProgressTut:Bool = false;
var canSkipTut:Bool = FlxG.save.data.tutorialCompleted;
var ominousScreen:Bool = false;
var tutProgress:Int = 0;
var missGriefSeed:Bool = FlxG.random.bool(0.225); // 1/444 chance
var imageStages:Array<FunkinSprite> = [];

graphicCache.cache(Paths.image("game/soulgem/soulgemrecover"));
graphicCache.cache(Paths.image("game/soulgem/soulgemdownrecover"));
graphicCache.cache(Paths.image("game/soulgem/glow"));
FlxG.sound.load(Paths.sound("game/dialogue/next"));
FlxG.sound.load(Paths.sound("game/dialogue/kyubey_tossGS"));
FlxG.sound.load(Paths.sound("soulgem_max"));
FlxG.sound.load(Paths.sound("initium_riser"));
function create()
{
	startUIvisablityArgs = [true, true, true, true, true, 0, false, 4, "linear", "In"];

	if (Options.gameplayShaders)
	{
		boilShader = new CustomShader('wave');
		boilShader.strength = 0.25;
		boilShader.speed = 7.0;
	}

	whiteShader = new CustomShader('WhiteOverlay');
	whiteShader.strength = 1.0;
	dad.shader = whiteShader;

	// Setup Stages
	stars = new FlxBackdrop(Paths.image("stages/initium/stars"), FlxAxes.XY, 0, 0);
	insert(members.indexOf(dad), stars);
	stars.alpha = 0.0;
	stars.velocity.set(0, -15);

	initBG_white = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.WHITE);
	initBG_white.scale.set(FlxG.width * 6, FlxG.height * 6);
	insert(members.indexOf(dad), initBG_white);
	initBG_white.visible = false;

	for (i in 1...9)
	{
		initBG_flashBackBG = new FunkinSprite(-850, -100);
		initBG_flashBackBG.loadSprite(Paths.image('stages/initium/week$i'));
		initBG_flashBackBG.scale.set(1.5, 1.5);
		initBG_flashBackBG.scrollFactor.set(1.0, 1.0);
		if (Options.gameplayShaders)
			initBG_flashBackBG.shader = boilShader;
		insert(members.indexOf(dad), initBG_flashBackBG);
		imageStages.push(initBG_flashBackBG);
		initBG_flashBackBG.visible = false;

		if (i == 1)
			initBG_flashBackBG.setPosition(-850, -100);
		if (i == 2)
			initBG_flashBackBG.setPosition(-850, -200);
		if (i == 3)
			initBG_flashBackBG.setPosition(-850, -300);
		if (i == 4)
			initBG_flashBackBG.setPosition(-1350, -175);
		if (i == 5)
			initBG_flashBackBG.setPosition(-850, -500);
		if (i == 6)
			initBG_flashBackBG.setPosition(-925, -300);
		if (i == 7)
			initBG_flashBackBG.setPosition(-800, -300);
		if (i == 8)
			initBG_flashBackBG.setPosition(-800, -240);
	}

	initBG_outsideBG = new FunkinSprite(-1550, -200);
	initBG_outsideBG.loadSprite(Paths.image('stages/initium/building'));
	initBG_outsideBG.scale.set(1.5, 1.5);
	initBG_outsideBG.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(dad), initBG_outsideBG);
	initBG_outsideBG.visible = false;

	// Tutorial Stuff
	nerdKyubey = new FunkinSprite(125, 150);
	nerdKyubey.loadSprite(Paths.image("stages/initium/nerdkyubey"));
	add(nerdKyubey);
	nerdKyubey.scale.set(0.85, 0.85);
	nerdKyubey.updateHitbox();
	nerdKyubey.origin.set(400, 600);
	nerdKyubey.alpha = 0.0;

	tutorialTxt = new FlxTypeText(nerdKyubey.x + nerdKyubey.width - 100, nerdKyubey.y + 100, 500, "");
	tutorialTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	tutorialTxt.borderSize = 3.0;
	add(tutorialTxt);
	tutorialTxt.completeCallback = () -> finishTyping();
	tutorialTxt.alpha = 0.0;
	tutorialTxt.sounds = [FlxG.sound.load(Paths.sound("game/dialogue/kyubey_speak"))];
	tutorialTxt.sounds[0].pitch = 1.0;

	tutorialTxtBox = new FunkinSprite(tutorialTxt.x - 100, tutorialTxt.y - 100);
	tutorialTxtBox.loadSprite(Paths.image("stages/initium/dialoguebox"));
	insert(members.indexOf(tutorialTxt), tutorialTxtBox);
	tutorialTxtBox.alpha = 0.0;

	tutorialGriefSeed = new FunkinSprite(tutorialTxt.x, tutorialTxt.y);
	tutorialGriefSeed.loadSprite(Paths.image("stages/initium/griefseed"));
	insert(members.indexOf(nerdKyubey), tutorialGriefSeed);
	tutorialGriefSeed.visible = false;
	tutorialGriefSeed.scale.set(0.75, 0.75);
	tutorialGriefSeed.moves = true;
	tutorialGriefSeed.angularVelocity = 150;

	tutorialNextTxt = new FlxText(tutorialTxtBox.x, tutorialTxtBox.y + tutorialTxtBox.height, tutorialTxtBox.width + 100, i18n.tr('Dialogue/PressKey'));
	tutorialNextTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	tutorialNextTxt.borderSize = 3.0;
	add(tutorialNextTxt);
	tutorialNextTxt.alpha = 0.0;

	if (canSkipTut)
		tutorialNextTxt.text += '\n ${i18n.tr('Dialogue/PressKeySkip')}';

	ominousScreenSprite = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	ominousScreenSprite.scale.set(FlxG.width * 6, FlxG.height * 6);
	add(ominousScreenSprite);
	ominousScreenSprite.visible = false;

	ominousScreenSpriteFlash = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.WHITE);
	ominousScreenSpriteFlash.scale.set(FlxG.width * 6, FlxG.height * 6);
	add(ominousScreenSpriteFlash);
	ominousScreenSpriteFlash.visible = false;
	ominousScreenSpriteFlash.alpha = 0.0;

	canPause = !doTut;
	canReset = false;

	camZooming = false;
}

function postCreate()
{
	health = 0.3;
	iconP1.setIcon(dad.icon);
	iconP2.visible = false;

	for (spr in [
		nerdKyubey,
		tutorialTxt,
		tutorialTxtBox,
		tutorialNextTxt,
		tutorialGriefSeed,
		ominousScreenSpriteFlash
	])
		spr.cameras = [camUI];
}

var updateShader:Float = 0;
var totalElapsed:Float = 0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	updateShader -= elapsed;
	if (updateShader <= 0)
	{
		if (Options.gameplayShaders)
			boilShader.time = totalElapsed;
		updateShader = 0.3;
	}

	if (inTut)
	{
		if (FlxG.sound.music.time > Conductor.stepCrochet * 208)
			FlxG.sound.music.time = Conductor.stepCrochet * 80;
	}

	if (FlxG.keys.justPressed.Z && canProgressTut && inTut && !paused)
	{
		canProgressTut = false;
		tutorialProgression();
		FlxG.sound.play(Paths.sound("game/dialogue/next"), 1.0 * Options.volumeSFX);
	}
	else if (FlxG.keys.justPressed.X && canProgressTut && inTut && !paused && !ominousScreen && canSkipTut)
	{
		tutProgress = 13;
		purity = 1;
		health = 0.3;
		healthDisplay = 0.3;
		songScore = 0;
		targetScore = 0;
		inTut = false;
		canProgressTut = false;
		scripts.call('soulGemUpdate');
		tutorialProgression();
		FlxG.sound.play(Paths.sound("game/dialogue/next"), 1.0 * Options.volumeSFX);
	}
}

function stepHit(curStep:Int)
{
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Star BG":
				if (params[1] == 'On')
				{
					tutorialProgression();
					if (params[2] == 0 || params[2] == '')
					{
						stars.alpha = 1.0;
					}
					else
					{
						FlxTween.tween(stars, {alpha: 1.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
					}
				}

			case "New Stage":
				initBG_white.visible = true;
				for (spr in imageStages)
					spr.visible = false;
				dad.shader = null;
				imageStages[params[1]].visible = true;
				if (Options.flashingLights)
					camGame.flash(FlxColor.WHITE, 0.5);

			case "Outside":
				initBG_white.visible = false;
				for (spr in imageStages)
					spr.visible = false;
				dad.shader = null;
				initBG_outsideBG.visible = true;

				if (Options.gameplayShaders)
				{
					var dropShadow2 = getDropShadow(dad);
					dropShadow2.setAdjustColor(0, -5, 15, 0);
					dropShadow2.color = 0xFFFF8944;
					dropShadow2.angle = 125;
					dropShadow2.distance = 15;
					dropShadow2.curZoom = 1;
					dropShadow2.threshold = 0.1;
					dropShadow2.antialiasAmt = 4;
				}
		}
	}
}

function tutorialProgression()
{
	var regenKyubey:Bool = true;
	var nextTimer:Float = -1;
	var textBoxX:Float = 0;
	var textBoxY:Float = 0;
	var kyubeyAngleOffset:Float = -2;
	var endTutorial:Bool = false;
	tutorialNextTxt.alpha = 0.0;

	FlxTween.cancelTweensOf(nerdKyubey);

	switch (tutProgress)
	{
		case 0: // Note Strum Explaination
			nerdKyubey.setPosition(125, 150);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/0'));
			textBoxX = 675;
			textBoxY = 200;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(-100, 650);
				kyubeyAngleOffset = 15;
				textBoxX = 675;
				textBoxY = 680;
			}

			uiVisibility('strums', 8, 1.0);
			uiVisibility('health', 8, 0.3);
			uiVisibility('score', 8, 0.3);
			uiVisibility('soulgem', 8, 0.3);

		case 1: // Health Bar Explaination
			nerdKyubey.setPosition(-100, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/1'));
			kyubeyAngleOffset = 15;
			textBoxX = 675;
			textBoxY = 700;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(-50, 100);
				kyubeyAngleOffset = -2;
				textBoxX = 700;
				textBoxY = 200;
			}

			uiVisibility('strums', 8, 0.3);
			uiVisibility('health', 8, 1.0);

		case 2: // Health Bar Explaination
			nerdKyubey.setPosition(-100, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/2'));
			kyubeyAngleOffset = 15;
			textBoxX = 675;
			textBoxY = 750;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(-50, 100);
				kyubeyAngleOffset = -2;
				textBoxX = 700;
				textBoxY = 200;
			}

		case 3: // Health Bar Explaination
			nerdKyubey.setPosition(800, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/3'));
			kyubeyAngleOffset = 25;
			textBoxX = 1350;
			textBoxY = 550;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(950, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

			uiVisibility('health', 8, 0.3);
			uiVisibility('soulgem', 8, 1.0);

		case 4: // Health Bar Explaination
			nerdKyubey.setPosition(800, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/4'));
			kyubeyAngleOffset = 25;
			textBoxX = 1350;
			textBoxY = 550;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(950, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

		case 5:
			regenKyubey = false;
			tutorialGriefSeed.visible = true;
			tutorialGriefSeed.setPosition(nerdKyubey.x + 450, nerdKyubey.y + 100);

			FlxG.sound.play(Paths.sound("game/dialogue/kyubey_tossGS"), 1.0 * Options.volumeSFX);

			if (missGriefSeed)
			{
				if (Options.downscroll)
				{
					tutorialGriefSeed.velocity.x += 250;
					tutorialGriefSeed.acceleration.x -= 50;
					tutorialGriefSeed.velocity.y -= 250;
					tutorialGriefSeed.acceleration.y += 750;
					nextTimer = 3.0;
				}
				else
				{
					tutorialGriefSeed.velocity.x += 350;
					tutorialGriefSeed.acceleration.x += 75;
					tutorialGriefSeed.velocity.y -= 1000;
					tutorialGriefSeed.acceleration.y += 1000;
					nextTimer = 3.0;
				}
			}
			else
			{
				if (Options.downscroll)
				{
					tutorialGriefSeed.velocity.x += 550;
					tutorialGriefSeed.acceleration.x -= 50;
					tutorialGriefSeed.velocity.y -= 750;
					tutorialGriefSeed.acceleration.y += 750;
					nextTimer = 0.65;
				}
				else
				{
					tutorialGriefSeed.velocity.x += 150;
					tutorialGriefSeed.acceleration.x += 75;
					tutorialGriefSeed.velocity.y -= 1000;
					tutorialGriefSeed.acceleration.y += 1000;
					nextTimer = 2.0;
				}
			}
			textBoxX = 1350;
			textBoxY = 550;

			FlxTween.tween(nerdKyubey, {angle: nerdKyubey.angle - 25}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.elasticOut});

		case 6: // Health Bar Explaination
			nerdKyubey.setPosition(800, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/5'));
			kyubeyAngleOffset = 10;
			textBoxX = 1350;
			textBoxY = 550;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(950, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

		case 7: // Score Explaination
			nerdKyubey.setPosition(600, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/6'));
			kyubeyAngleOffset = 20;
			textBoxX = 1200;
			textBoxY = 700;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(750, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

			uiVisibility('soulgem', 8, 0.3);
			uiVisibility('score', 8, 1.0);

		case 8:
			nerdKyubey.setPosition(600, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/7'));
			kyubeyAngleOffset = 20;
			textBoxX = 1200;
			textBoxY = 650;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(750, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

			FlxTween.num(songScore, 5000, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadInOut}, function(num:Float)
			{
				songScore = Std.int(num);
			});

		case 9:
			nerdKyubey.setPosition(600, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/8'));
			kyubeyAngleOffset = 20;
			textBoxX = 1200;
			textBoxY = 675;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(750, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

			FlxTween.num(targetScore, 2500, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadInOut}, function(num:Float)
			{
				targetScore = Std.int(num);
			});

		case 10:
			nerdKyubey.setPosition(600, 650);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/9'));
			kyubeyAngleOffset = 20;
			textBoxX = 1200;
			textBoxY = 625;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(750, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

			FlxTween.num(targetScore, 7500, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadInOut}, function(num:Float)
			{
				targetScore = Std.int(num);
			});

		case 11:
			nerdKyubey.setPosition(200, 350);
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/10'));
			kyubeyAngleOffset = -2;
			textBoxX = 675;
			textBoxY = 200;

			FlxTween.num(songScore, 0, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.quadInOut}, function(num:Float)
			{
				songScore = Std.int(num);
			});

			FlxTween.num(targetScore, 0, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.quadInOut}, function(num:Float)
			{
				targetScore = Std.int(num);
			});

			uiVisibility('strums', 8, 0.3);
			uiVisibility('health', 8, 0.3);
			uiVisibility('score', 8, 0.3);
			uiVisibility('soulgem', 8, 0.3);
			multiAnimation('hide');

		case 12:
			tutorialTxt.resetText(i18n.tr('Dialogue/Initium/11'));
			textBoxX = 675;
			textBoxY = 475;
			ominousScreen = true;
			ominousScreenSprite.visible = true;
			onVocalsResync();

			uiVisibility('strums', 0, 0.0);
			uiVisibility('health', 0, 0.0);
			uiVisibility('score', 0, 0.0);
			uiVisibility('soulgem', 0, 0.0);

		case 13:
			endTutorial = true;

		case 1002:
			nerdKyubey.setPosition(800, 650);
			tutorialTxt.resetText("Oops.");
			kyubeyAngleOffset = -2;
			textBoxX = 1350;
			textBoxY = 650;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(950, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}

		case 1003:
			nerdKyubey.setPosition(800, 650);
			tutorialTxt.resetText("Gulp... that wasn't supposed to happen! Sorry but that was my last one...");
			kyubeyAngleOffset = -2;
			textBoxX = 1350;
			textBoxY = 575;

			if (Options.downscroll)
			{
				nerdKyubey.setPosition(950, 150);
				kyubeyAngleOffset = -2;
				textBoxX = 1350;
				textBoxY = 300;
			}
	}

	if (ominousScreen)
	{
		nerdKyubey.visible = false;
		tutorialTxtBox.visible = false;
	}

	if (regenKyubey)
	{
		if (!endTutorial)
			nerdKyubey.angle = kyubeyAngleOffset;
		FlxTween.tween(nerdKyubey, {angle: nerdKyubey.angle + 4}, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	}

	if (endTutorial)
	{
		for (spr in [nerdKyubey, tutorialTxtBox, tutorialTxt])
			spr.visible = false;

		if (!inTut)
		{
			canPause = true;
			ominousScreen = false;
			ominousScreenSprite.visible = false;
			inst.resume();
			vocals.resume();
			onVocalsResync();
			FlxG.sound.music.time = Conductor.stepCrochet * 208;
			uiVisibility('strums', 0, 1.0);
			uiVisibility('health', 0, 1.0);
			uiVisibility('score', 0, 1.0);
			uiVisibility('soulgem', 0, 1.0);
		}
		else
		{
			ominousScreenSpriteFlash.visible = true;
			FlxG.sound.play(Paths.sound("initium_riser"), 1.0 * Options.volumeMusic);

			FlxTween.tween(ominousScreenSpriteFlash, {alpha: 1.0}, 1.371, {
				ease: FlxEase.quadIn,
				onComplete: function(twn:FlxTween)
				{
					inTut = false;
					canPause = true;
					ominousScreen = false;
					ominousScreenSprite.visible = false;
					inst.resume();
					vocals.resume();
					onVocalsResync();
					FlxG.sound.music.time = Conductor.stepCrochet * 208;
					uiVisibility('strums', 16, 1.0);
					uiVisibility('health', 16, 1.0);
					uiVisibility('score', 16, 1.0);
					uiVisibility('soulgem', 16, 1.0);

					FlxTween.tween(ominousScreenSpriteFlash, {alpha: 0.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});
				}
			});
		}

		FlxG.save.data.tutorialCompleted = true;
	}
	else
	{
		dummyTxt = new FlxText(0, 0, 500, tutorialTxt._finalText);
		dummyTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE);

		// Reposition All Text
		tutorialTxt.updateHitbox();
		tutorialTxtBox.setGraphicSize(dummyTxt.width + 100, dummyTxt.fieldHeight + 100);
		tutorialTxtBox.updateHitbox();
		tutorialTxtBox.setPosition(textBoxX, textBoxY);
		tutorialTxt.setPosition(tutorialTxtBox.x + 50, tutorialTxtBox.y + 50);
		tutorialNextTxt.setPosition(tutorialTxtBox.x, tutorialTxtBox.y + tutorialTxtBox.height - 25);
		if (canSkipTut)
			tutorialNextTxt.y -= 15;

		if (ominousScreen)
			tutorialNextTxt.text = i18n.tr('Dialogue/PressKey');

		if (regenKyubey)
		{
			for (spr in [nerdKyubey, tutorialTxtBox, tutorialTxt])
				spr.alpha = 0.0;

			FlxTween.tween(nerdKyubey, {y: nerdKyubey.y - 25, alpha: 1.0}, Conductor.stepCrochet * 4 / 1000, {ease: FlxEase.sineOut});
			FlxTween.tween(tutorialTxtBox, {alpha: 0.75}, Conductor.stepCrochet * 4 / 1000, {ease: FlxEase.sineOut});
			FlxTween.tween(tutorialTxt, {alpha: 1.0}, Conductor.stepCrochet * 4 / 1000, {ease: FlxEase.sineOut});
			tutorialTxt.start((ominousScreen ? 0.09 : 0.03), true);
		}
		else
		{
			tutorialTxtBox.alpha = 0.0;
			tutorialTxt.alpha = 0.0;
		}

		if (nextTimer != -1)
		{
			new FlxTimer().start(nextTimer, function(tmr:FlxTimer)
			{
				finishTyping();
				if (nextTimer == 3 && tutProgress == 5)
				{
					tutProgress = 1001;
					canProgressTut = false;
					tutorialProgression();
				}

				tutProgress += 1;
				canProgressTut = false;
				tutorialProgression();
			});
		}
	}
}

function finishTyping()
{
	switch (tutProgress)
	{
		case 1:
			FlxTween.num(health, 2, Conductor.stepCrochet * 16 / 1000, {
				ease: FlxEase.quadInOut,
				onComplete: function(twn:FlxTween)
				{
					nextPrompt();
				}
			}, function(num:Float)
			{
				health = num;
			});
		case 2:
			FlxTween.num(health, 0.3, Conductor.stepCrochet * 16 / 1000, {
				ease: FlxEase.quadInOut,
				onComplete: function(twn:FlxTween)
				{
					nextPrompt();
				}
			}, function(num:Float)
			{
				health = num;
			});
		case 3:
			FlxTween.num(purity, 0.3, Conductor.stepCrochet * 16 / 1000, {
				ease: FlxEase.quadInOut,
				onComplete: function(twn:FlxTween)
				{
					nextPrompt();
				}
			}, function(num:Float)
			{
				scripts.call('soulGemUpdate');
				purity = num;
			});
		case 4:
			nextPrompt();
		case 5:
			tutorialGriefSeed.visible = false;
			tutorialGriefSeed.moves = false;

			if (!missGriefSeed)
			{
				if (Options.downscroll)
				{
					soulgemGlow = new FunkinSprite();
					soulgemGlow.loadSprite(Paths.image("game/soulgem/soulgemdownrecover"));
					add(soulgemGlow);
					soulgemGlow.setPosition(FlxG.width - soulgemGlow.width + 10, -10);
					soulgemGlow.cameras = [camUI];
					soulgemGlow.blend = BlendMode.ADD;

					FlxTween.tween(soulgemGlow, {'scale.x': 1.15, 'scale.y': 1.15, alpha: 0.0}, Conductor.stepCrochet * 16 / 1000, {
						ease: FlxEase.expoOut,
						onComplete: function(twn:FlxTween)
						{
							soulgemGlow.destroy();
							remove(soulgemGlow, true);
						}
					});
				}
				else
				{
					soulgemGlow = new FunkinSprite();
					soulgemGlow.loadSprite(Paths.image("game/soulgem/soulgemrecover"));
					add(soulgemGlow);
					soulgemGlow.setPosition(FlxG.width - soulgemGlow.width + 10, FlxG.height - soulgemGlow.height + 10);
					soulgemGlow.cameras = [camUI];
					soulgemGlow.blend = BlendMode.ADD;

					FlxTween.tween(soulgemGlow, {'scale.x': 1.15, 'scale.y': 1.15, alpha: 0.0}, Conductor.stepCrochet * 16 / 1000, {
						ease: FlxEase.expoOut,
						onComplete: function(twn:FlxTween)
						{
							soulgemGlow.destroy();
							remove(soulgemGlow, true);
						}
					});
				}

				soulgemGlow2 = new FunkinSprite();
				soulgemGlow2.loadSprite(Paths.image("game/soulgem/glow"));
				add(soulgemGlow2);
				GenUtil.alignToCenter(soulgemGlow2, soulgemGlow);
				soulgemGlow2.x += (Options.downscroll ? 100 : 55);
				soulgemGlow2.y += (Options.downscroll ? -50 : 90);
				soulgemGlow2.scale.set(0.25, 0.25);
				soulgemGlow2.cameras = [camUI];
				soulgemGlow2.blend = BlendMode.ADD;

				FlxTween.tween(soulgemGlow2, {'scale.x': 1.75, 'scale.y': 1.75, alpha: 0.0}, Conductor.stepCrochet * 16 / 1000, {
					ease: FlxEase.expoOut,
					onComplete: function(twn:FlxTween)
					{
						soulgemGlow.destroy();
						remove(soulgemGlow, true);
					}
				});

				FlxG.sound.play(Paths.sound("soulgem_max"), 1.0 * Options.volumeSFX);

				purity = 1.0;
				scripts.call('soulGemUpdate');
			}
		default:
			nextPrompt();
	}
}

function onVocalsResync()
{
	if (ominousScreen)
	{
		inst.pause();
		vocals.pause();
	}
	else
	{
		inst.resume();
		vocals.resume();
	}
}

function nextPrompt()
{
	if (ominousScreen)
	{
		FlxTween.tween(tutorialNextTxt, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, Conductor.stepCrochet * 8 / 1000, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				if (tutProgress == 1003)
					tutProgress = 6;
				else
					tutProgress += 1;
				canProgressTut = true;
			}
		});
	}
	else
	{
		tutorialNextTxt.scale.x = 1.5;
		tutorialNextTxt.scale.y = 1.5;
		FlxTween.tween(tutorialNextTxt, {alpha: 1.0}, Conductor.stepCrochet * 4 / 1000, {ease: FlxEase.sineOut});
		FlxTween.tween(tutorialNextTxt, {'scale.x': 1.0, 'scale.y': 1.0}, Conductor.stepCrochet * 8 / 1000, {
			ease: FlxEase.bounceOut,
			onComplete: function(twn:FlxTween)
			{
				if (tutProgress == 1003)
					tutProgress = 6;
				else
					tutProgress += 1;
				canProgressTut = true;
			}
		});
	}
}
