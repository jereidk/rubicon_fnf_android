import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import funkin.backend.system.Control;
import BlurFilter;
import ui.ButtonUI;

class MessageWindowUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var iconTimer:FlxTimer;

	var blur:BlurFilter;

	var scrollTween:FlxTween;

	public function new(theData:Dynamic)
	{
		super();

		data = theData;

		group = new FlxSpriteGroup();

		messageCam = new FlxCamera();
		messageCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(messageCam, false);
		messageCam.scroll.y -= 15;
		scrollTween = FlxTween.num(-15, 0, 0.5, {ease: FlxEase.expoOut}, function(num:Float)
		{
			messageCam.scroll.y = num;
		});

		if (Options.gameplayShaders)
		{
			blur = new BlurFilter(0.0);
			blur.apply(FlxG.camera);
			FlxTween.num(0.0, 15, 0.50, {ease: FlxEase.expoOut}, function(num:Float)
			{
				blur.set(num);
			});
		}

		msgBG = new FunkinSprite(0, 0).makeGraphic(1920, 1080, FlxColor.BLACK);
		msgBG.scale.set(FlxG.width * 2, FlxG.height * 2);
		add(msgBG);
		msgBG.alpha = 0.0;
		FlxTween.tween(msgBG, {alpha: 0.75}, 0.50, {ease: FlxEase.expoOut});
		msgBG.cameras = [messageCam];

		msgBox = new FunkinSprite().loadGraphic(Paths.image('ui/common/window'));
		add(msgBox).cameras = [messageCam];
		msgBox.screenCenter();

		msgHeader = new FlxText(msgBox.x, msgBox.y + 52, msgBox.width, i18n.tr('Message/Header/${data.nameKey}'));
		msgHeader.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		msgHeader.borderSize = 2.5;
		add(msgHeader).cameras = [messageCam];
		msgHeader.cameras = [messageCam];

		var textToUse = data.nameKey;
		if (data.mainTextKey != null)
			textToUse = data.mainTextKey;

		msgMain = new FlxText(msgBox.x + 75, msgBox.y + 250, msgBox.width - 150, i18n.tr('Message/${data.mainTextKey}'));
		msgMain.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		msgMain.borderSize = 2.5;
		add(msgMain).cameras = [messageCam];

		var iconToUse = 'info';
		if (data.icon != null)
			iconToUse = data.icon;
		msgIcon = new FunkinSprite(msgBox.x + 50, msgBox.y + 17).loadGraphic(Paths.image('ui/common/window_icon_${iconToUse}'));
		add(msgIcon).cameras = [messageCam];
		msgIcon.alpha = 0.0;
		msgIcon.y -= 25;
		FlxTween.tween(msgIcon, {y: msgIcon.y + 25, alpha: 1.0}, 0.50, {
			ease: FlxEase.elasticInOut,
			onComplete: function(twn:FlxTween)
			{
				add(GenUtil.glowPulse(msgIcon, 1.0, 0.5, 1.0)).cameras = [messageCam];
			}
		});

		if (iconToUse == 'danger')
		{
			iconTimer = new FlxTimer().start(2.5, function(tmr:FlxTimer)
			{
				add(GenUtil.glowPulse(msgIcon, 1.0, 0.5, 1.0)).cameras = [messageCam];
			}, 0);
		}

		switch (data.type)
		{
			case 'twochoice':
				lButton = new ButtonUI(0, 650, 'basic');
				lButton.text = i18n.tr('Message/Options/${data.leftTextKey}');
				add(lButton.group).cameras = [messageCam];
				lButton.group.screenCenter(FlxAxes.X);
				lButton.group.x -= 250;

				rButton = new ButtonUI(0, 650, 'basic');
				rButton.text = i18n.tr('Message/Options/${data.rightTextKey}');
				add(rButton.group).cameras = [messageCam];
				rButton.group.screenCenter(FlxAxes.X);
				rButton.group.x += 250;

			case 'languagechoose':
				englishOp = new FunkinSprite(msgBox.x, msgBox.y + 400).loadGraphic(Paths.image('ui/settings/english'));
				add(englishOp).cameras = [messageCam];
				englishOp.x = (msgBox.x + msgBox.width / 2 - englishOp.width / 2) - 400;
				englishOp.scale.set(1.5, 1.5);

				spanishOp = new FunkinSprite(msgBox.x, msgBox.y + 400).loadGraphic(Paths.image('ui/settings/spanish'));
				add(spanishOp).cameras = [messageCam];
				spanishOp.x = (msgBox.x + msgBox.width / 2 - spanishOp.width / 2);
				spanishOp.scale.set(1.5, 1.5);

				japaneseOp = new FunkinSprite(msgBox.x, msgBox.y + 400).loadGraphic(Paths.image('ui/settings/japanese'));
				add(japaneseOp).cameras = [messageCam];
				japaneseOp.x = (msgBox.x + msgBox.width / 2 - japaneseOp.width / 2) + 400;
				japaneseOp.scale.set(1.5, 1.5);
		}

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

		if ((FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.A) && !lButton.selected)
		{
			GenUtil.playUISound('move');
			lButton.selected = true;
			rButton.selected = false;
		}
		else if ((FlxG.keys.justPressed.RIGHT || FlxG.keys.justPressed.D) && !rButton.selected)
		{
			GenUtil.playUISound('move');
			lButton.selected = false;
			rButton.selected = true;
		}
		else if (FlxG.keys.justPressed.ENTER)
		{
			new FlxTimer().start(0.0001, function(tmr:FlxTimer)
			{
				if (lButton.selected)
				{
					data.leftAction();
					data.completedAction();
					GenUtil.playUISound('close');
				}
				else if (rButton.selected)
				{
					data.rightAction();
					data.completedAction();
					GenUtil.playUISound('close');
				}
			});
		}
		else if (FlxG.keys.justPressed.ESCAPE && !data.type != 'languagechoose')
		{
			new FlxTimer().start(0.0001, function(tmr:FlxTimer)
			{
				data.backAction();
				GenUtil.playUISound('close');
			});
		}

		if (data.type == 'languagechoose')
		{
			if (FlxG.mouse.justPressed && CoolUtil.mouseOverlaps(englishOp))
			{
				Options.language = 'en_US';
				data.completedAction();
				i18n.loadFromString(Assets.getText('data/langs/${Options.language}/translations.json'));
			}
			if (FlxG.mouse.justPressed && CoolUtil.mouseOverlaps(spanishOp))
			{
				Options.language = 'es_US';
				data.completedAction();
				i18n.loadFromString(Assets.getText('data/langs/${Options.language}/translations.json'));
			}
			if (FlxG.mouse.justPressed && CoolUtil.mouseOverlaps(japaneseOp))
			{
				Options.language = 'ja';
				data.completedAction();
				i18n.loadFromString(Assets.getText('data/langs/${Options.language}/translations.json'));
			}
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
		if (Options.gameplayShaders)
			blur.remove(FlxG.camera);
		FlxG.cameras.remove(messageCam);
		FlxTween.cancelTweensOf(msgIcon);
		iconTimer?.cancel();

		super.destroy();
	}
}
