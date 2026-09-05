import util.GenUtil;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import hxvlc.flixel.FlxVideoSprite;

var canControl:Bool = false;
var introVideo:FlxVideoSprite;
var yesVideo:FlxVideoSprite;
var yesText:FlxText;
var noText:FlxText;
var yesSelTween:FlxTween;
var noSelTween:FlxTween;
var selectorTween:FlxTween;
var selectorAlphaTween:FlxTween;
var selectingYes:Bool = false;
var hasMoved:Bool = false;

FlxG.sound.load(Paths.sound("videos/intro_start"));
FlxG.sound.load(Paths.sound("videos/intro_yes"));
FlxG.sound.load(Paths.sound("videos/intro_no"));
function create()
{
	introVideo = new FlxVideoSprite(0, 0);
	introVideo.antialiasing = true;
	introVideo.bitmap.onFormatSetup.add(function():Void
	{
		if (introVideo.bitmap != null && introVideo.bitmap.bitmapData != null)
		{
			final scale:Float = Math.min((FlxG.width / introVideo.bitmap.bitmapData.width) * 1, (FlxG.height / introVideo.bitmap.bitmapData.height) * 1);

			introVideo.setGraphicSize(introVideo.bitmap.bitmapData.width * scale, introVideo.bitmap.bitmapData.height * scale);
			introVideo.updateHitbox();
			introVideo.screenCenter();
		}
	});
	introVideo.bitmap.onEndReached.add(() ->
	{
		yesVideo.pause();

		FlxTween.tween(questionText, {alpha: 1.0}, 0.5, {ease: FlxEase.quadIn});
		FlxTween.tween(noText, {alpha: 0.5}, 1.5, {ease: FlxEase.quadIn});
		FlxTween.tween(yesText, {alpha: 0.5}, 1.5, {
			ease: FlxEase.quadIn,
			onComplete: function(twn:FlxTween)
			{
				canControl = true;
			}
		});
	});
	add(introVideo);
	introVideo.load(Paths.video("intro_start"));
	introVideo.play();

	yesVideo = new FlxVideoSprite(0, 0);
	yesVideo.antialiasing = true;
	yesVideo.bitmap.onFormatSetup.add(function():Void
	{
		if (yesVideo.bitmap != null && yesVideo.bitmap.bitmapData != null)
		{
			final scale:Float = Math.min((FlxG.width / yesVideo.bitmap.bitmapData.width) * 1, (FlxG.height / yesVideo.bitmap.bitmapData.height) * 1);

			yesVideo.setGraphicSize(yesVideo.bitmap.bitmapData.width * scale, yesVideo.bitmap.bitmapData.height * scale);
			yesVideo.updateHitbox();
			yesVideo.screenCenter();
		}
	});
	yesVideo.bitmap.onEndReached.add(() ->
	{
		yesVideo.pause();
		FlxG.switchState(new ModState("HQDisclaimer"));
	});
	add(yesVideo);
	yesVideo.visible = false;
	yesVideo.load(Paths.video("intro_yes"));
	yesVideo.play();
	yesVideo.pause();
	yesVideo.bitmap.time = 0;

	noVideo = new FlxVideoSprite(0, 0);
	noVideo.antialiasing = true;
	noVideo.bitmap.onFormatSetup.add(function():Void
	{
		if (noVideo.bitmap != null && noVideo.bitmap.bitmapData != null)
		{
			final scale:Float = Math.min((FlxG.width / noVideo.bitmap.bitmapData.width) * 1, (FlxG.height / noVideo.bitmap.bitmapData.height) * 1);

			noVideo.setGraphicSize(noVideo.bitmap.bitmapData.width * scale, noVideo.bitmap.bitmapData.height * scale);
			noVideo.updateHitbox();
			noVideo.screenCenter();
		}
	});
	noVideo.bitmap.onEndReached.add(() ->
	{
		noVideo.pause();

		// I can't figure out why the settings don't get saved after saying no then yes so fuck it, i'll fix it later
		FlxG.save.data.firstTimeSetupDone = false;
		FlxG.save.data.seeIntro = true;

		Options.__save.erase();
		Options.__save.flush();
		FlxG.save.flush();

		Sys.exit();
	});
	add(noVideo);
	noVideo.visible = false;
	noVideo.load(Paths.video("intro_no"));
	noVideo.play();
	noVideo.pause();
	noVideo.bitmap.time = 0;

	questionText = new FlxText(0, 685, FlxG.width, i18n.tr('Intro/WishQuestion'));
	questionText.setFormat(Paths.font("kaisho-S.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	questionText.borderSize = 3.0;
	add(questionText);
	questionText.alpha = 0.0;
	questionText.screenCenter(FlxAxes.X);

	selector = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/intro/selector2'));
	add(selector);
	selector.alpha = 0.0;
	selector.blend = BlendMode.ADD;

	selector2 = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/intro/selector'));
	add(selector2);
	selector2.scale.set(0.75, 0.75);
	selector2.alpha = 0.00;
	selector2.blend = BlendMode.ADD;

	selector3 = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/intro/selector'));
	add(selector3);
	selector3.scale.set(0.75, 0.75);
	selector3.angle = 90;
	selector3.alpha = 0.00;
	selector3.blend = BlendMode.ADD;

	selector.setPosition(710, 600);

	FlxTween.tween(selector2, {'scale.x': 1.5}, 3.0, {ease: FlxEase.quadInOut, type: FlxTween.PINGPONG});
	FlxTween.tween(selector3, {'scale.x': 1.5}, 3.0, {ease: FlxEase.quadInOut, type: FlxTween.PINGPONG});

	yesText = new FunkinSprite(619, 700).loadGraphic(Paths.image('ui/intro/yes'));
	add(yesText);
	yesText.alpha = 0.0;
	yesText.screenCenter(FlxAxes.X);
	yesText.x += 350;

	noText = new FunkinSprite(619, 730).loadGraphic(Paths.image('ui/intro/no'));
	add(noText);
	noText.alpha = 0.0;
	noText.screenCenter(FlxAxes.X);
	noText.x -= 350;

	/*
		yesText = new FlxText(0, 800, 400, i18n.tr('Message/Options/Yes'));
		yesText.setFormat(Paths.font("shingo.otf"), 72, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
		yesText.borderSize = 3.0;
		add(yesText);
		yesText.alpha = 0.0;
		yesText.screenCenter(FlxAxes.X);
		yesText.x -= 400;
		 

		noText = new FlxText(0, 800, 400, i18n.tr('Message/Options/No'));
		noText.setFormat(Paths.font("shingo.otf"), 72, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
		noText.borderSize = 3.0;
		add(noText);
		noText.alpha = 0.0;
		noText.screenCenter(FlxAxes.X);
		noText.x += 400;
	 */

	FlxG.sound.play(Paths.sound("videos/intro_start"), 2.0 * Options.volumeSFX);

	// FlxTween.tween(noText, {y: noText.y - 25}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	// FlxTween.tween(yesText, {y: yesText.y - 25}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	borders = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/intro/borders'));
	add(borders);

	subtitleText = new FlxText(0, 900, FlxG.width, '');
	subtitleText.setFormat(Paths.font("arial.ttf"), 42, FlxColor.YELLOW, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	subtitleText.borderSize = 2.0;
	add(subtitleText);
}

function postCreate()
{
}

function update(elapsed:Float)
{
	selector2.setPosition(selector.x, selector.y);
	selector3.setPosition(selector.x, selector.y);

	selector2.angle -= 15 * elapsed;
	selector3.angle += 15 * elapsed;
	selector2.alpha = selector.alpha / 5;
	selector3.alpha = selector.alpha / 5;

	if (canControl)
	{
		if (controls.LEFT_P && (selectingYes || !hasMoved))
		{
			GenUtil.playUISound('move');

			selectingYes = false;
			hasMoved = true;
			FlxTween.cancelTweensOf(noText, ["alpha", "scale.x", "scale.y"]);
			FlxTween.cancelTweensOf(yesText, ["alpha", "scale.x", "scale.y"]);

			noSelTween?.cancel();
			yesSelTween?.cancel();

			noSelTween = FlxTween.tween(noText, {alpha: 1.0, 'scale.x': 1.15, 'scale.y': 1.15}, 0.5, {ease: FlxEase.expoOut});
			yesSelTween = FlxTween.tween(yesText, {alpha: 0.5, 'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {ease: FlxEase.expoOut});

			selectorTween?.cancel();
			selectorTween = FlxTween.tween(selector, {x: 375, y: 600}, 0.5, {ease: FlxEase.expoOut});

			selectorAlphaTween?.cancel();
			selectorAlphaTween = FlxTween.tween(selector, {alpha: 0.5}, 0.5, {ease: FlxEase.expoOut});
		}
		else if (controls.RIGHT_P && (!selectingYes || !hasMoved))
		{
			GenUtil.playUISound('move');

			selectingYes = true;
			hasMoved = true;
			FlxTween.cancelTweensOf(noText, ["alpha", "scale.x", "scale.y"]);
			FlxTween.cancelTweensOf(yesText, ["alpha", "scale.x", "scale.y"]);

			noSelTween?.cancel();
			yesSelTween?.cancel();

			noSelTween = FlxTween.tween(noText, {alpha: 0.5, 'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {ease: FlxEase.expoOut});
			yesSelTween = FlxTween.tween(yesText, {alpha: 1.0, 'scale.x': 1.15, 'scale.y': 1.15}, 0.5, {ease: FlxEase.expoOut});

			selectorTween?.cancel();
			selectorTween = FlxTween.tween(selector, {x: 1075, y: 600}, 0.5, {ease: FlxEase.expoOut});

			selectorAlphaTween?.cancel();
			selectorAlphaTween = FlxTween.tween(selector, {alpha: 0.5}, 0.5, {ease: FlxEase.expoOut});
		}
		else if (controls.ACCEPT && hasMoved)
		{
			canControl = false;

			FlxTween.cancelTweensOf(noText, ["alpha", "scale.x", "scale.y"]);
			FlxTween.cancelTweensOf(yesText, ["alpha", "scale.x", "scale.y"]);

			if (selectingYes)
			{
				GenUtil.playUISound('confirm');
				noSelTween = FlxTween.tween(yesText, {alpha: 1.0, 'scale.x': 1.25, 'scale.y': 1.25}, 1.0, {ease: FlxEase.expoOut});
				insert(members.indexOf(yesText) + 1, GenUtil.glowPulse(yesText, 1.0, 0.5, 1.0));
			}
			else
			{
				FlxG.sound.play(Paths.sound("ui/ui_confirm_bad"), 1.0 * Options.volumeSFX).persist = true;
				noSelTween = FlxTween.tween(noText, {alpha: 1.0, 'scale.x': 1.25, 'scale.y': 1.25}, 1.0, {ease: FlxEase.expoOut});
				insert(members.indexOf(noText) + 1, GenUtil.glowPulse(noText, 1.0, 0.5, 1.0));
			}

			for (spr in [yesText, noText, questionText, selector])
			{
				if (spr != selector)
					FlxTween.cancelTweensOf(spr);
				FlxTween.tween(spr, {alpha: 0.0}, 1.0, {ease: FlxEase.quadOut, startDelay: 1.25});
			}

			new FlxTimer().start(1.5, function(tmr:FlxTimer)
			{
				if (selectingYes)
				{
					new FlxTimer().start(1.0, function(tmr:FlxTimer)
					{
						noText.visible = false;
						yesText.visible = false;
						questionText.visible = false;
						FlxG.sound.play(Paths.sound("videos/intro_yes"), 2.0 * Options.volumeSFX);
						yesVideo.visible = true;
						yesVideo.play();

						FlxG.save.data.seeIntro = false;
						FlxG.save.flush();

						selector.alpha = 0.0;
					});
				}
				else
				{
					new FlxTimer().start(2.0, function(tmr:FlxTimer)
					{
						noText.visible = false;
						yesText.visible = false;
						questionText.visible = false;
						FlxG.sound.play(Paths.sound("videos/intro_no"), 2.0 * Options.volumeSFX);
						noVideo.visible = true;
						noVideo.play();

						selector.alpha = 0.0;
					});
				}
			});
		}
	}

	if (yesVideo.bitmap.time >= 300 && yesVideo.bitmap.time <= 1218)
	{
		subtitleText.text = i18n.tr('Intro/CutsceneSubtitles/AWish');
	}
	else if (yesVideo.bitmap.time >= 9350 && yesVideo.bitmap.time <= 10043)
	{
		subtitleText.text = i18n.tr('Intro/CutsceneSubtitles/I');
	}
	else if (yesVideo.bitmap.time >= 12346 && yesVideo.bitmap.time <= 13864)
	{
		subtitleText.text = i18n.tr('Intro/CutsceneSubtitles/BeLike');
	}
	else
	{
		subtitleText.text = '';
	}
}

function confirmSelection()
{
}
