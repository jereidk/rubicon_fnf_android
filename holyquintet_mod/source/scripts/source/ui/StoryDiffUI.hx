import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import funkin.backend.system.Control;
import BlurFilter;
import ui.ButtonUI;

class StoryDiffUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var headerTxt:FlxText;

	var lButton:ButtonUI;

	var iconTimer:FlxTimer;

	var blur:BlurFilter;

	var scrollTween:FlxTween;

	var curSel:String = '';

	public function new(theData:Dynamic)
	{
		FlxG.sound.load(Paths.sound('ui/freeplay/diff_easy'));
		FlxG.sound.load(Paths.sound('ui/freeplay/diff_hard'));

		super();

		data = theData;

		storyDiffCam = new FlxCamera();
		storyDiffCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(storyDiffCam, false);
		storyDiffCam.scroll.y -= 15;
		scrollTween = FlxTween.num(-15, 0, 0.5, {ease: FlxEase.expoOut}, function(num:Float)
		{
			storyDiffCam.scroll.y = num;
		});

		group = new FlxSpriteGroup();

		if (Options.gameplayShaders)
		{
			blur = new BlurFilter(0.0);
			blur.apply(FlxG.camera);
			FlxTween.num(0.0, 15, 0.50, {ease: FlxEase.expoOut}, function(num:Float)
			{
				blur.set(num);
			});
		}

		bg = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width * 2, FlxG.height * 2);
		add(bg);
		bg.alpha = 0.0;
		FlxTween.tween(bg, {alpha: 0.75}, 0.50, {ease: FlxEase.expoOut});

		msgHeader = new FlxText(0, 250, FlxG.width, i18n.tr('Main/SelectDiff'));
		msgHeader.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		msgHeader.borderSize = 2.5;
		add(msgHeader).cameras = [storyDiffCam];

		easyButton = new FunkinSprite().loadGraphic(Paths.image('ui/main/easy'));
		add(easyButton).cameras = [storyDiffCam];
		easyButton.screenCenter();
		easyButton.x -= 325;
		easyButton.origin.x = easyButton.width;

		hardButton = new FunkinSprite().loadGraphic(Paths.image('ui/main/hard'));
		add(hardButton).cameras = [storyDiffCam];
		hardButton.screenCenter();
		hardButton.x += 325;
		hardButton.origin.x = 0;

		easyButton.scale.set(0.75, 0.75);
		hardButton.scale.set(0.75, 0.75);
		easyButton.color = FlxColor.GRAY;
		hardButton.color = FlxColor.GRAY;

		GenUtil.playUISound('open');
	}

	public override function update(elapsed)
	{
		super.update(elapsed);
	}

	public function add(obj)
	{
		group.add(obj);
	}

	public function remove(obj)
	{
		group.remove(obj);
	}

	override function update(elapsed)
	{
		super.update(elapsed);
		group.update();

		if ((FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.A) && curSel != 'easy')
		{
			curSel = 'easy';
			GenUtil.playUISound('move');
			easyButton.color = FlxColor.WHITE;
			easyButton.scale.set(1.0, 1.0);
			hardButton.color = FlxColor.GRAY;
			hardButton.scale.set(0.75, 0.75);

			FlxG.sound.play(Paths.sound('ui/freeplay/diff_easy'), 1.0 * Options.volumeSFX);

			add(GenUtil.glowPulse(easyButton, 0.25, 0.1, 0.5)).cameras = [storyDiffCam];
		}
		else if ((FlxG.keys.justPressed.RIGHT || FlxG.keys.justPressed.D) && curSel != 'hard')
		{
			curSel = 'hard';
			GenUtil.playUISound('move');
			easyButton.color = FlxColor.GRAY;
			easyButton.scale.set(0.75, 0.75);
			hardButton.color = FlxColor.WHITE;
			hardButton.scale.set(1.0, 1.0);

			FlxG.sound.play(Paths.sound('ui/freeplay/diff_hard'), 1.0 * Options.volumeSFX);

			add(GenUtil.glowPulse(hardButton, 1.0, 0.1, 0.5)).cameras = [storyDiffCam];
		}
		else if (FlxG.keys.justPressed.ENTER)
		{
			if (curSel == 'easy')
			{
				data.leftAction();
				data.completedAction();
			}
			else if (curSel == 'hard')
			{
				data.rightAction();
				data.completedAction();
			}
		}
		else if (FlxG.keys.justPressed.ESCAPE)
		{
			data.backAction();
			GenUtil.playUISound('close');
		}
	}

	override function draw()
	{
		super.draw();
		group.draw();
	}

	override function destroy()
	{
		group.destroy();

		scrollTween.cancel();
		FlxTween.cancelTweensOf(storyDiffCam);
		if (Options.gameplayShaders)
			blur.remove(FlxG.camera);
		FlxG.cameras.remove(storyDiffCam);

		super.destroy();
	}
}
