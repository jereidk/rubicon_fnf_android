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
var selection:Int = -1;

FlxG.sound.load(Paths.sound('ui/ui_GODUKA_move'));
FlxG.sound.load(Paths.sound('ui/ui_GODKUA_confirm'));
function create()
{
	camera = gameOverCam = new FlxCamera();
	gameOverCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(gameOverCam, false);

	blackOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	blackOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(blackOverlay);
	blackOverlay.alpha = 1.0;

	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		gameOverCam.addShader(bloomShader);
		bloomShader.amt = 0.0;
	}

	stars = new FlxBackdrop(Paths.image("stages/initium/stars"), FlxAxes.XY, 0, 0);
	add(stars);
	stars.alpha = 0.5;
	stars.velocity.set(0, -15);

	/*
		bg = new FunkinSprite().loadGraphic(Paths.image('game/goduka/spacebg'));
		add(bg);
		bg.scale.set(2.5, 2.5);
		bg.screenCenter();
		bg.angle = -10;
		FlxTween.tween(bg, {angle: 10, 'scale.x': 2.0, 'scale.y': 2.0}, 25, {ease: FlxEase.quadInOut});
	 */

	goduka = new FunkinSprite().loadGraphic(Paths.image('game/goduka/GODUKA'));
	add(goduka);
	goduka.y = FlxG.height - goduka.height;
	goduka.x += 500;

	FlxTween.tween(goduka, {x: goduka.x - 250}, 1.5, {ease: FlxEase.quadOut});
	FlxTween.tween(goduka, {y: goduka.y + 5}, 1, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	godukaHelpTxtPixels = new FlxText(0, 0, 0, i18n.tr('Gameplay/Goduka/Question'));
	godukaHelpTxtPixels.setFormat(Paths.font("kaisho-S.otf"), 72, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	godukaHelpTxtPixels.borderSize = 2.5;
	godukaHelpTxtPixels.drawFrame(true);

	godukaHelpTxt = new FunkinSprite(100, 300).loadGraphic(godukaHelpTxtPixels.graphic);
	add(godukaHelpTxt);
	godukaHelpTxt.skew.x = -15;
	godukaHelpTxt.skew.y = -5;

	godukaHelpTxtPixels2 = new FlxText(0, 0, 0, i18n.tr('Gameplay/Goduka/CurrentSong'));
	godukaHelpTxtPixels2.setFormat(Paths.font("kaisho-S.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	godukaHelpTxtPixels2.borderSize = 2.5;
	godukaHelpTxtPixels2.drawFrame(true);

	godukaHelpTxt2 = new FunkinSprite(125, 450).loadGraphic(godukaHelpTxtPixels2.graphic);
	add(godukaHelpTxt2);
	godukaHelpTxt2.alpha = 0.5;
	godukaHelpTxt2.skew.x = -15;
	godukaHelpTxt2.skew.y = -5;

	FlxTween.tween(godukaHelpTxt, {y: godukaHelpTxt.y + 15}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	FlxTween.tween(godukaHelpTxt2, {y: godukaHelpTxt2.y + 15}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	godukaYesTxtPixels = new FlxText(0, 0, 0, i18n.tr('Message/Options/Yes'));
	godukaYesTxtPixels.setFormat(Paths.font("kaisho-S.otf"), 72, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	godukaYesTxtPixels.borderSize = 2.5;
	godukaYesTxtPixels.drawFrame(true);

	godukaYesTxt = new FunkinSprite(300, 550).loadGraphic(godukaYesTxtPixels.graphic);
	add(godukaYesTxt);
	godukaYesTxt.alpha = 0.5;
	godukaYesTxt.scale.set(0.75, 0.75);
	godukaYesTxt.skew.x = -15;
	godukaYesTxt.skew.y = -5;

	FlxTween.tween(godukaYesTxt, {y: godukaYesTxt.y + 15}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	godukaNoTxtPixels = new FlxText(0, 0, 0, i18n.tr('Message/Options/No'));
	godukaNoTxtPixels.setFormat(Paths.font("kaisho-S.otf"), 72, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	godukaNoTxtPixels.borderSize = 2.5;
	godukaNoTxtPixels.drawFrame(true);

	godukaNoTxt = new FunkinSprite(315, 650).loadGraphic(godukaNoTxtPixels.graphic);
	add(godukaNoTxt);
	godukaNoTxt.alpha = 0.5;
	godukaNoTxt.scale.set(0.75, 0.75);
	godukaNoTxt.skew.x = -15;
	godukaNoTxt.skew.y = -5;

	FlxTween.tween(godukaNoTxt, {y: godukaNoTxt.y + 15}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	overlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	overlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(overlay);
	overlay.alpha = 1.0;
	FlxTween.tween(overlay, {alpha: 0.0}, 1.0, {ease: FlxEase.quadOut});

	overlayWhite = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.WHITE);
	overlayWhite.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(overlayWhite);
	overlayWhite.alpha = 0.0;

	if (!Options.flashingLights)
		overlayWhite.color = FlxColor.BLACK;

	if (Options.language == 'es_US')
	{
		godukaHelpTxt.x += 65;
		godukaYesTxt.x += 25;
	}
}

function postCreate()
{
}

function update(elapsed:Float)
{
	// moved = true;
	if (canControl)
	{
		if (controls.UP_P && selection != 0)
		{
			selection = 0;

			FlxTween.cancelTweensOf(godukaNoTxt, ['scale.x', 'scale.y', 'alpha']);
			FlxTween.cancelTweensOf(godukaYesTxt, ['scale.x', 'scale.y', 'alpha']);

			FlxTween.tween(godukaYesTxt, {'scale.x': 1.25, 'scale.y': 1.25, alpha: 1.0}, 0.25, {ease: FlxEase.quadOut});
			FlxTween.tween(godukaNoTxt, {'scale.x': 0.75, 'scale.y': 0.75, alpha: 0.5}, 0.25, {ease: FlxEase.quadOut});

			FlxG.sound.play(Paths.sound('ui/ui_GODUKA_move'), 1.0 * Options.volumeSFX).pitch = FlxG.random.float(0.98, 1.02);
		}

		if (controls.DOWN_P && selection != 1)
		{
			selection = 1;

			FlxTween.cancelTweensOf(godukaNoTxt, ['scale.x', 'scale.y', 'alpha']);
			FlxTween.cancelTweensOf(godukaYesTxt, ['scale.x', 'scale.y', 'alpha']);

			FlxTween.tween(godukaNoTxt, {'scale.x': 1.25, 'scale.y': 1.25, alpha: 1.0}, 0.25, {ease: FlxEase.quadOut});
			FlxTween.tween(godukaYesTxt, {'scale.x': 0.75, 'scale.y': 0.75, alpha: 0.5}, 0.25, {ease: FlxEase.quadOut});

			FlxG.sound.play(Paths.sound('ui/ui_GODUKA_move'), 1.0 * Options.volumeSFX).pitch = FlxG.random.float(0.98, 1.02);
		}

		if (controls.ACCEPT)
		{
			if (selection != -1)
				canControl = false;

			if (selection == 0)
			{
				GenUtil.playUISound('confirm');

				FlxG.sound.play(Paths.sound('ui/ui_GODKUA_confirm'), 1.0 * Options.volumeSFX).pitch = FlxG.random.float(0.98, 1.02);

				camera.zoom = 1.05;
				FlxTween.tween(camera, {zoom: 1.0}, 0.5, {ease: FlxEase.quadOut});

				FlxTween.tween(camera, {zoom: 1.75}, 1.5, {ease: FlxEase.expoIn, startDelay: 0.5});
				FlxTween.num(0.0, -0.5, 1.5, {ease: FlxEase.expoIn, startDelay: 0.5}, function(num:Float)
				{
					bloomShader.amt = num;
				});

				FlxTween.tween(overlayWhite, {alpha: 1.0}, 1.5, {ease: FlxEase.expoIn, startDelay: 0.5});

				new FlxTimer().start(2.0, function(tmr:FlxTimer)
				{
					overlay.alpha = 1.0;
					FlxTween.tween(overlayWhite, {alpha: 0.0}, 3.0, {ease: FlxEase.quadInOut});

					new FlxTimer().start(5.0, function(tmr:FlxTimer)
					{
						FlxG.switchState(new PlayState());
						godukaEnabled = true;
						godukaCooldown = -1;
					});
				});
			}

			if (selection == 1)
			{
				GenUtil.playUISound('back');

				FlxTween.cancelTweensOf(overlay);
				FlxTween.tween(overlay, {alpha: 1.0}, 1.0, {
					ease: FlxEase.quadIn,
					onComplete: function(twn:FlxTween)
					{
						godukaCooldown = 5;

						FlxG.switchState(new PlayState());
					}
				});
			}
		}
	}
}

function confirmSelection()
{
}
