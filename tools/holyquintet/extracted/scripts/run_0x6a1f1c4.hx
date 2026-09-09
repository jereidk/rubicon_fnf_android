import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;

class CurrencyPopupUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var currency:String = '';

	var headerTxt:FlxText;
	var statTxt:FlxText;

	var rainbow:Bool = false;

	var iconBounceTween:FlxTween;

	var psi = PlayState.instance;

	public function new(newCurrency:String, change:Int)
	{
		FlxG.sound.load(Paths.sound("ui/kyubeycoin_gain"));
		FlxG.sound.load(Paths.sound("ui/kyubeycoin_show"));

		super();

		group = new FlxSpriteGroup();
		currency = newCurrency;

		currencyCur = FlxG.save.data.kyubeyCoins;
		currencyChange = change;

		negativeChange = false;
		if (currencyChange < 0)
			negativeChange = true;

		back = new FunkinSprite(0, 150).loadGraphic(Paths.image('ui/common/currency_back'));
		add(back);
		back.alpha = 0.5;

		icon = new FunkinSprite(25, 125).loadGraphic(Paths.image('ui/common/currency_kyubeycoins'));
		add(icon);

		curAmountTxt = new FlxText(icon.x + icon.width + 15, 152, 500, FlxStringUtil.formatMoney(currencyCur, false));
		curAmountTxt.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x88000000);
		curAmountTxt.borderSize = 2.0;
		add(curAmountTxt);
		curAmountTxt.origin.set(0, curAmountTxt.height);

		curChangeTxt = new FlxText(icon.x + icon.width + 15, 192, 500, '+${FlxStringUtil.formatMoney(currencyChange, false)}');
		curChangeTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.YELLOW, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x88000000);
		curChangeTxt.borderSize = 2.0;
		add(curChangeTxt);

		if (negativeChange)
		{
			curChangeTxt.text = '${FlxStringUtil.formatMoney(currencyChange, false)}';
			curChangeTxt.color = FlxColor.RED;
		}

		whiteShader = new CustomShader('WhiteOverlay');
		whiteShader.strength = 0.0;
		icon.shader = whiteShader;

		group.x = -400;

		FlxG.sound.play(Paths.sound('ui/kyubeycoin_show'), 0.85 * Options.volumeSFX);

		FlxTween.tween(group, {x: 0}, 0.5, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(0.5, function(tmr:FlxTimer)
				{
					if (!negativeChange)
						iconBounceTween = FlxTween.tween(icon, {y: icon.y - 5}, 0.05, {ease: FlxEase.quadInOut, type: FlxTween.PINGPONG});
					FlxTween.tween(curAmountTxt, {'scale.x': 1.25, 'scale.y': 1.25}, 0.25, {ease: FlxEase.backOut});

					FlxTween.num(1.0, 0.0, 0.5, {ease: FlxEase.quadOut}, function(num:Float)
					{
						whiteShader.strength = num;
					});

					FlxTween.num(currencyCur, currencyCur + currencyChange, 0.5 + FlxMath.bound((Math.abs(currencyChange / 1000)), 0.0, 1.0), {
						ease: FlxEase.linear,
						onComplete: function(twn:FlxTween)
						{
							iconBounceTween?.cancel();
							FlxTween.tween(icon, {y: 125}, 0.05, {ease: FlxEase.quadInOut});

							FlxTween.tween(curAmountTxt, {y: 166}, 0.5, {ease: FlxEase.quadInOut, startDelay: 0.1});
							FlxTween.tween(curChangeTxt, {alpha: 0.0}, 0.5, {
								ease: FlxEase.quadInOut,
								startDelay: 0.1,
								onComplete: function(twn:FlxTween)
								{
									curChangeTxt.visible = false;
								}
							});
							FlxTween.tween(curAmountTxt, {'scale.x': 1.0, 'scale.y': 1.0}, 0.4, {ease: FlxEase.backOut, startDelay: 0.1});

							FlxTween.tween(group, {x: group.x - 400, alpha: 0.0}, 1.0, {
								ease: FlxEase.quadInOut,
								startDelay: 1.0,
								onComplete: function(twn:FlxTween)
								{
									destroy();
								}
							});
						}
					}, function(num:Float)
					{
						curAmountTxt.text = FlxStringUtil.formatMoney(num, false);
						if (!negativeChange)
							curChangeTxt.text = '+${FlxStringUtil.formatMoney(currencyChange + (currencyCur - num), false)}';
						else
							curChangeTxt.text = '${FlxStringUtil.formatMoney(currencyChange + (currencyCur - num), false)}';
					});

					if (!negativeChange)
						FlxG.sound.play(Paths.sound('ui/kyubeycoin_gain'), 0.7 * Options.volumeSFX);
					else
						FlxG.sound.play(Paths.sound('ui/kyubeycoin_lose'), 0.7 * Options.volumeSFX);
				});
			}
		});

		FlxG.save.data.kyubeyCoins += currencyChange;
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
		super.destroy();
	}
}
