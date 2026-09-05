import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import openfl.display.BlendMode;
import util.GenUtil;

class GauntletStatDisplay extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var countingTweens:Array<FlxTween> = [];

	var curNumber:Float = 0.0;

	var stat:String = '';

	var alignment:String = 'RIGHT';

	var countingSnd:FlxSound;

	public function new(?stat:String, ?alignment:String)
	{
		super(stat, alignment);

		group = new FlxSpriteGroup();

		statBG = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/counterbg'));
		statBG.setPosition((FlxG.width - statBG.width) * 0.990, (FlxG.height - (statBG.height / 2)) * 0.075);
		group.add(statBG);
		statBG.blend = BlendMode.MULTIPLY;

		statMainTxt = new FlxText(statBG.x - 695, statBG.y - 28, 1000, '-');
		statMainTxt.setFormat(Paths.font("shingo.otf"), 72, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		statMainTxt.borderSize = 3.0;
		group.add(statMainTxt);
		statMainTxt.origin.set(statMainTxt.width, statMainTxt.height);
		statMainTxt.scale.set(1.0, 1.0);

		statLable = new FlxText(statBG.x - 695, statBG.y + statMainTxt.height - 24, 1000, i18n.tr('Gauntlet/$stat'));
		statLable.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		statLable.borderSize = 3.0;
		group.add(statLable);

		switch (alignment)
		{
			case 'LEFT':
				for (spr in [statMainTxt, statLable])
				{
					spr.alignment = FlxTextAlign.LEFT;
					spr.x += 705;
				}
		}

		switch (stat)
		{
			case 'ScoreMultiplier':
				statMainTxt.text = GenUtil.padMultiplier(FlxMath.roundDecimal(curGauntletMultiplier, 2));
				curNumber = curGauntletMultiplier;

				if (curNumber >= gauntletBackgroundThresholds[1])
					statMainTxt.color = 0xFFFF0F7B;
				else if (curNumber >= gauntletBackgroundThresholds[0])
					statMainTxt.color = 0xFFF9D922;
				else
					statMainTxt.color = 0xFF55C5EF;
			case 'BestScore':
				statMainTxt.text = FlxStringUtil.formatMoney(curGauntletGamemode == 'Standard' ? FlxG.save.data.bestGauntletScoreStandard : FlxG.save.data.bestGauntletScoreEndless,
					false);
				curNumber = curGauntletGamemode == 'Standard' ? FlxG.save.data.bestGauntletScoreStandard : FlxG.save.data.bestGauntletScoreEndless;
				statMainTxt.x += 5;
				statMainTxt.y += 12;
				statMainTxt.size -= 18;
		}

		countingSound = new FlxSound().loadEmbedded(Paths.sound('game/results/results_increase'), true, false);
		FlxG.sound.list.add(countingSound);

		this.stat = stat;
		this.alignment = alignment;
	}

	public function count(target:Float)
	{
		for (twn in countingTweens)
			twn.cancel();

		switch (alignment)
		{
			case 'LEFT':
				statMainTxt.origin.set(0, statMainTxt.height);
		}

		countingTweens.push(FlxTween.tween(statMainTxt, {'scale.x': 1.15, 'scale.y': 1.15}, 0.25, {
			ease: FlxEase.expoOut
		}));

		countingTweens.push(FlxTween.num(curNumber, target, 1.0, {
			ease: FlxEase.sineOut,
			onComplete: function(twn:FlxTween)
			{
				countingSound?.stop();

				countingTweens.push(FlxTween.tween(statMainTxt, {'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {
					ease: FlxEase.expoIn,
					onComplete: function(twn:FlxTween)
					{
						// updateGraphics();

						// countingTweens.push(FlxTween.tween(gauntletMeterBG, {alpha: 0.5}, 0.5, {ease: FlxEase.cubeOut}));
						// countingTweens.push(FlxTween.tween(gauntletMeter, {alpha: 0.5}, 0.5, {ease: FlxEase.cubeOut}));
					}
				}));
			}
		}, function(num:Float)
		{
			curNumber = num;

			switch (stat)
			{
				case 'ScoreMultiplier':
					statMainTxt.text = GenUtil.padMultiplier(FlxMath.roundDecimal(num, 2));
					countingSound?.pitch = 0.6 + (0.15 * num);
					if (num >= gauntletBackgroundThresholds[1])
						statMainTxt.color = 0xFFFF0F7B;
					else if (num >= gauntletBackgroundThresholds[0])
						statMainTxt.color = 0xFFF9D922;
					else
						statMainTxt.color = 0xFF55C5EF;
				case 'BestScore':
					statMainTxt.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(num, 0), false);
			}
		}));

		switch (stat)
		{
			case 'ScoreMultiplier':
				countingSound?.play();
			case 'BestScore':
				countingSound?.play();
		}
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
	}

	override function draw()
	{
		super.draw();
		group.draw();
	}

	override function destroy()
	{
		group.destroy();

		countingSound?.destroy();
		FlxG.sound.list.remove(countingSound);

		super.destroy();
	}
}
