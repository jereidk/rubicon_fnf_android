import util.GenUtil;
import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import funkin.editors.charter.Charter;
import funkin.menus.FreeplayState;
import funkin.menus.StoryMenuState;
import openfl.display.BlendMode;

var canControl:Bool = true;
FlxG.sound.load(Paths.music("gameover"));
FlxG.sound.load(Paths.sound("game/gameover/fall"));
FlxG.sound.load(Paths.sound("game/gameover/flashbuildup"));
FlxG.sound.load(Paths.sound("game/gameover/gemshatter"));
FlxG.sound.load(Paths.sound("game/gameover/gfscream"));
FlxG.sound.load(Paths.sound("game/gameover/gameover-despair"));
var backingTrack:FlxSound;
var timeToRetry:Float = 0.0;
var timeToRetryDisplay:Float = 0.0;
var sceneEnding:Bool = false;
var startEndSequence:Bool = false;
var lightDustSprites:Array<FunkinSprite> = [];
var textBump:FlxTween;
var textCylces:Int = 0;

var strings:Array<String> = [
	i18n.tr('Gameplay/GameOver/Quotes/0'),
	i18n.tr('Gameplay/GameOver/Quotes/1'),
	i18n.tr('Gameplay/GameOver/Quotes/2'),
	i18n.tr('Gameplay/GameOver/Quotes/3'),
];

var godukaPrompt:Bool = false;
var alreadyTransitioned:Bool = false;

function create()
{
	if (PlayState.deathCounter <= 3 || PlayState.isGauntletMode || godukaEnabled || godukaCooldown > 1)
		godukaPrompt = false;
	else
		godukaPrompt = true;

	camera = gameOverCam = new FlxCamera();
	gameOverCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(gameOverCam, false);

	gameOverCamUI = new FlxCamera();
	gameOverCamUI.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(gameOverCamUI, false);

	if (Options.gameplayShaders)
	{
		transverseShader = new CustomShader('Transverse');
		transverseShader.falloff = 6;
		transverseShader.blur = 5.0;
		gameOverCam.addShader(transverseShader);

		bloomShader = new CustomShader("Bloom");
		gameOverCam.addShader(bloomShader);
		bloomShader.amt = 0.0;
	}

	bg = new FunkinSprite().loadGraphic(Paths.image('game/death/bg'));
	add(bg);
	bg.alpha = 0.5;

	bgHappy = new FunkinSprite().loadGraphic(Paths.image('game/death/bghappy'));
	add(bgHappy);
	bgHappy.visible = false;

	var font:String = "zyzol.otf";
	if (Options.language == 'ja')
		font = "shingo.otf";

	happyTxt = new FlxText(0, 900, 0, strings[FlxG.random.int(0, strings.length - 1)], 92);
	happyTxt.setFormat(Paths.font(font), 92, 0xFFA7113E, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFFA7113E);
	happyTxt.borderSize = 5;
	add(happyTxt);
	happyTxt.visible = false;
	happyTxt.screenCenter(FlxAxes.X);
	happyTxt.x += 50;
	happyTxt.cameras = [gameOverCamUI];

	happyTxt2 = new FlxText(0, happyTxt.y - 10, 0, happyTxt.text, 92);
	happyTxt2.setFormat(Paths.font(font), 92, 0xFFFFFFFF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFFE04CAC);
	happyTxt2.borderSize = 5;
	add(happyTxt2);
	happyTxt2.visible = false;
	happyTxt2.screenCenter(FlxAxes.X);
	happyTxt2.x += 50;
	happyTxt2.cameras = [gameOverCamUI];

	baseLight = new FunkinSprite().loadGraphic(Paths.image('game/death/baselight'));
	add(baseLight);
	baseLight.screenCenter(FlxAxes.X);
	baseLight.alpha = 1.0;

	lightning = new FunkinSprite(600, 50);
	lightning.frames = Paths.getSparrowAtlas('game/death/lightning');
	lightning.addAnim('start', 'lightningback', 24, false, false, CoolUtil.parseNumberRange("0..17"));
	add(lightning);
	lightning.scale.set(4, 4);
	lightning.color = (Options.flashingLights ? FlxColor.WHITE : FlxColor.GRAY);

	gf = new FunkinSprite(475, 350);
	gf.loadSprite(Paths.image("game/death/gf"));
	gf.addAnim('start', 'gfdeath', 24, false, false, CoolUtil.parseNumberRange("0..24"));
	gf.addAnim('loop', 'gfdeath', 24, true, false, CoolUtil.parseNumberRange("25..42"));
	gf.addAnim('fall', 'gfdeath', 24, false, false, CoolUtil.parseNumberRange("49..64"));
	gf.scale.set(1.0, 1.0);
	gf.updateHitbox();
	add(gf);
	gf.playAnim('loop');

	gfHey = new Character(490, 135, 'gf-base', true);
	add(gfHey);
	gfHey.visible = false;
	gfHey.scale.set(0.85, 0.85);

	for (i in 0...5)
	{
		var lightDust = new FunkinSprite(600 + FlxG.random.int(0, 100), -250 + FlxG.random.int(0, 600));
		lightDust.loadSprite(Paths.image("game/death/specks"));
		add(lightDust);
		lightDust.alpha = FlxG.random.float(0.5, 1.0);
		lightDustSprites.push(lightDust);
		lightDust.blend = BlendMode.ADD;

		FlxTween.tween(lightDust, {y: lightDust.y + FlxG.random.int(50, 350), alpha: 0.0}, 25, {
			ease: FlxEase.linear,
			onComplete: function(twn:FlxTween)
			{
				lightDust?.destroy();
				remove(lightDust, true);
			}
		});
	}

	addLight = new FunkinSprite().loadGraphic(Paths.image('game/death/bglighting'));
	add(addLight);
	addLight.screenCenter(FlxAxes.X);
	addLight.alpha = 0.5;
	addLight.blend = BlendMode.ADD;

	var chosenFrames:Array<Int> = [];
	for (i in 0...4)
		chosenFrames.push(FlxG.random.int(0, 7, chosenFrames));

	flashingSpr = new FunkinSprite(0, 0).loadGraphic(Paths.image('game/death/deathflash' + (Options.flashingLights ? '' : '-dim')), true, 192, 108);
	add(flashingSpr);
	flashingSpr.animation.add('flashes', chosenFrames, 8, true);
	flashingSpr.scale.set(10, 10);
	flashingSpr.screenCenter();
	flashingSpr.animation.play('flashes');

	purifyTxt = new FunkinText(0, 900, 0, i18n.tr('Gameplay/GameOver/ConfirmPurify'), 32);
	purifyTxt.setFormat(Paths.font("kaisho-S.otf"), 32, 0xFFFFFFFF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF000000);
	purifyTxt.borderSize = 2;
	add(purifyTxt);
	purifyTxt.alpha = 0.0;
	purifyTxt.cameras = [gameOverCamUI];
	purifyTxt.screenCenter(FlxAxes.X);

	gameOverText = new FunkinSprite().loadGraphic(Paths.image('game/death/gameover-${Options.language}'));
	add(gameOverText);
	gameOverText.scale.set(0.75, 0.75);
	gameOverText.alpha = 0.0;
	gameOverText.cameras = [gameOverCamUI];
	gameOverText.screenCenter();

	gameOverTextOverlay = new FlxBackdrop(Paths.image('game/death/gameovertextoverlay'), FlxAxes.X, 0, 0);
	add(gameOverTextOverlay);
	gameOverTextOverlay.scale.set(0.75, 0.75);
	gameOverTextOverlay.y = gameOverText.y - 5;
	gameOverTextOverlay.blend = BlendMode.MULTIPLY;
	gameOverTextOverlay.alpha = 0.0;
	gameOverTextOverlay.velocity.set(10, 0);
	gameOverTextOverlay.cameras = [gameOverCamUI];

	backingTrack = new FlxSound().loadEmbedded(Paths.sound('game/gameover/gameover-despair'));
	backingTrack.volume = 0.0;
	FlxG.sound.list.add(backingTrack);

	// Start Death Scene
	for (strumLine in PlayState.instance.strumLines.members)
		strumLine.vocals?.stop();

	FlxG.sound.play(Paths.sound("game/gameover/flashbuildup")).onComplete = function()
	{
		gameOverCam.zoom = 2.5;
		FlxTween.tween(gameOverCam, {zoom: 1.05}, 0.5, {ease: FlxEase.expoOut});
		FlxTween.num(25, 0, 2.25, {
			ease: FlxEase.expoOut
		}, function(num:Float)
		{
			gameOverCam.scroll.x = FlxG.random.float(-num, num);
			gameOverCam.scroll.y = FlxG.random.float(-num, num);
		});

		if (Options.gameplayShaders)
		{
			FlxTween.num(-1.25, -0.25, 2.25, {
				ease: FlxEase.expoOut
			}, function(num:Float)
			{
				bloomShader.amt = num;
			});
		}

		FlxG.sound.play(Paths.sound("game/gameover/gemshatter"));
		FlxG.sound.play(Paths.sound("game/gameover/gfscream"));
		flashingSpr.visible = false;
		gf.playAnim('start', true);
		gf.animation.finishCallback = () ->
		{
			gf.playAnim('loop');
			lightning.animation.finishCallback = null;

			CoolUtil.playMusic(Paths.music("gameover"), false, 1, false);
			backingTrack.play();

			startEndSequence = true;

			FlxTween.tween(purifyTxt, {alpha: 0.5}, 1.0, {ease: FlxEase.quadIn});
		};
		lightning.playAnim('start', true);
		lightning.animation.finishCallback = () ->
		{
			lightning.visible = false;
			lightning.animation.finishCallback = null;
		};
	};

	darknessOverlay = new FunkinSprite().loadGraphic(Paths.image('game/death/darkoverlay'));
	add(darknessOverlay);
	darknessOverlay.alpha = 0.0;
	darknessOverlay.zoomFactor = 0.0;
	darknessOverlay.screenCenter();
	darknessOverlay.scale.set(1.65, 1.65);

	camFadeOverlay = new FlxSprite(-FlxG.width * 2, -FlxG.height * 2).makeGraphic(1, 1, FlxColor.BLACK);
	camFadeOverlay.scale.set(FlxG.width * 8, FlxG.height * 8);
	add(camFadeOverlay);
	camFadeOverlay.alpha = 0.0;
	camFadeOverlay.cameras = [gameOverCamUI];

	godukaCooldown -= 1;
}

function postCreate()
{
}

function update(elapsed:Float)
{
	if (!sceneEnding && startEndSequence)
	{
		timeToRetry = FlxMath.bound(timeToRetry + (0.05 * elapsed), 0.0, 1.0);
		timeToRetryDisplay = CoolUtil.fpsLerp(timeToRetryDisplay, timeToRetry, 0.05);

		gameOverCam.zoom = 1.05 + (timeToRetryDisplay * 0.25);
		gameOverCam.scroll.x = 0;
		gameOverCam.scroll.y = 0 + (timeToRetryDisplay * 50);
		backingTrack.volume = 0.0 + timeToRetry;
		addLight.alpha = 0.5 - (timeToRetry * 0.40);
		darknessOverlay.alpha = 0.0 + timeToRetry;
		if (Options.gameplayShaders)
		{
			transverseShader.falloff = 6 - timeToRetry;
			bloomShader.amt = -0.25 + (timeToRetry * 0.25);
		}

		if (timeToRetry >= 0.5)
		{
			darknessOverlay.offset.x = FlxG.random.float((-timeToRetry + 0.5) * 5, (timeToRetry - 0.5) * 5);
			darknessOverlay.offset.y = FlxG.random.float((-timeToRetry + 0.5) * 5, (timeToRetry - 0.5) * 5);
		}

		if (timeToRetry >= 0.25 && textBump == null)
		{
			textBump = FlxTween.tween(purifyTxt, {'scale.x': 1.1, 'scale.y': 1.1, alpha: 1.0}, timeToRetry >= 1.0 ? 0.3 : 0.5, {
				ease: FlxEase.quadInOut,
				onComplete: function(twn:FlxTween)
				{
					FlxTween.tween(purifyTxt, {'scale.x': 1.0, 'scale.y': 1.0, alpha: 0.5}, timeToRetry >= 1.0 ? 0.3 : 0.5, {
						ease: FlxEase.quadInOut,
						onComplete: function(twn:FlxTween)
						{
							new FlxTimer().start((textCylces % 2 == 0 || timeToRetry >= 1.0) ? 0 : 4, function(tmr:FlxTimer)
							{
								textBump = null;
							});
							textCylces += 1;
						}
					});
				}
			});
		}

		if (controls.ACCEPT_HOLD)
		{
			timeToRetry -= 0.5 * elapsed;
			if (timeToRetry <= 0)
			{
				FlxG.sound.music.time = Conductor.stepCrochet * 228;
				backingTrack.time = FlxG.sound.music.time;
			}
		}
	}

	if (controls.BACK && !sceneEnding && startEndSequence)
	{
		FlxG.sound.music.time = Conductor.stepCrochet * 228;
		backingTrack.time = FlxG.sound.music.time;
	}
	else if (controls.BACK && sceneEnding)
	{
		if (PlayState.chartingMode && Charter.undos.unsaved)
			game.saveWarn(false);
		else
		{
			godukaEnabled = false;

			if (Charter.instance != null)
				Charter.instance.__clearStatics();

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();
			FlxG.sound.music = null;

			if (PlayState.isGauntletMode)
				FlxG.switchState(new ModState("HQGauntlet"));
			else
				FlxG.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
		}
	}

	if (controls.ACCEPT && sceneEnding && timeToRetry <= 0)
	{
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		FlxG.sound.music = null;

		camFadeOverlay.visible = true;
		camFadeOverlay.alpha = 1.0;
		if (!alreadyTransitioned)
			returnToPlayState();
	}

	if (FlxG.sound.music.time >= Conductor.stepCrochet * 228 && !sceneEnding)
	{
		sceneEnding = true;

		textBump = null;
		purifyTxt.visible = false;

		if (timeToRetry <= 0)
		{
			if (Options.gameplayShaders && Options.flashingLights)
			{
				FlxTween.num(-1.25, 0, 2.25, {
					ease: FlxEase.expoOut
				}, function(num:Float)
				{
					bloomShader.amt = num;
				});
			}

			if (Options.gameplayShaders)
				gameOverCam.removeShader(transverseShader);

			baseLight.visible = false;
			addLight.visible = false;
			for (spr in lightDustSprites)
				spr.visible = false;
			gf.visible = false;
			bgHappy.visible = true;

			gfHey.playAnim('hey', true, 'LOCK');
			gfHey.visible = true;
			new FlxTimer().start(0.75, function(tmr:FlxTimer)
			{
				gfHey.stopAnim();
			});

			happyTxt.visible = true;
			happyTxt2.visible = true;
			FlxTween.tween(happyTxt, {x: happyTxt.x - 50}, 1.0, {ease: FlxEase.quadOut});
			FlxTween.tween(happyTxt2, {x: happyTxt2.x - 50}, 1.0, {ease: FlxEase.quadOut});

			FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 3.0, {
				ease: FlxEase.quadIn,
				startDelay: 3.5,
				onComplete: function(twn:FlxTween)
				{
					if (!godukaPrompt)
						FlxG.switchState(new PlayState());
					else if (!alreadyTransitioned)
						returnToPlayState();
				}
			});
		}
		else
		{
			FlxG.sound.play(Paths.sound("game/gameover/fall"));
			gf.playAnim('fall');
			gf.animation.finishCallback = () ->
			{
				gf.animation.pause();
			};

			FlxTween.tween(gameOverCam, {zoom: 0.75, alpha: 0.0}, 7.5, {ease: FlxEase.quadIn});
			FlxTween.tween(baseLight, {alpha: 0.0}, 2.5, {ease: FlxEase.quadIn});
			FlxTween.tween(addLight, {alpha: 0.0}, 1.0, {ease: FlxEase.quadOut});
			for (spr in lightDustSprites)
			{
				FlxTween.cancelTweensOf(spr, ['alpha']);
				FlxTween.tween(spr, {alpha: 0.0}, 1.0, {ease: FlxEase.quadOut});
			}

			new FlxTimer().start(3.0, function(tmr:FlxTimer)
			{
				gameOverTextOverlay.alpha = 1.0;
				FlxTween.tween(gameOverText, {'scale.x': 1.0, 'scale.y': 1.0, alpha: 1.0}, 2.5, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						insert(members.indexOf(gameOverText) + 1, GenUtil.glowPulse(gameOverText, 1.0, 0.25, 1.5)).cameras = [gameOverCamUI];
					}
				});
				FlxTween.tween(gameOverTextOverlay, {'scale.x': 1.0, 'scale.y': 1.0}, 2.5, {ease: FlxEase.quadOut});
			});

			new FlxTimer().start(6.5, function(tmr:FlxTimer)
			{
				FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 2.5, {
					ease: FlxEase.quadIn,
					onComplete: function(twn:FlxTween)
					{
						if (PlayState.chartingMode && Charter.undos.unsaved)
							game.saveWarn(false);
						else
						{
							godukaEnabled = false;

							if (Charter.instance != null)
								Charter.instance.__clearStatics();

							if (FlxG.sound.music != null)
								FlxG.sound.music.stop();
							FlxG.sound.music = null;

							if (PlayState.isGauntletMode)
								FlxG.switchState(new ModState("HQGauntlet"));
							else
								FlxG.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
						}
					}
				});
			});
		}
	}
}

function confirmSelection()
{
	GenUtil.playUISound('confirm');

	canControl = false;
}

function returnToPlayState()
{
	alreadyTransitioned = true;

	if (!godukaPrompt)
		FlxG.switchState(new PlayState());
	else
	{
		godkuaSubState = new ModSubState("HQGodukaPrompt");
		openSubState(godkuaSubState);
	}
}
