import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

class StatusEffectUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var icon:FunkinSprite;

	var effect:String = '';

	public function new(newEffect:String)
	{
		super();

		group = new FlxSpriteGroup();
		effect = newEffect;

		var offset:Int = 0;
		if (Options.downscroll)
			offset = 100;

		icon = new FunkinSprite(0, PlayState.instance.iconP1.y + offset);
		icon.loadGraphic(Paths.image("game/statusicons"), true, 100, 100);
		icon.addAnim('reeducedRecovery', null, 0, false, false, [0]);
		icon.addAnim('bleed', null, 0, false, false, [1]);
		icon.addAnim('timeStop', null, 0, false, false, [2]);
		icon.addAnim('divineProtection', null, 0, false, false, [3]);
		add(icon);
		icon.offset.set(25, 25);
		icon.playAnim(newEffect);

		text = new FlxText(0, PlayState.instance.iconP1.y + offset, 125, '0.0s\n0x');
		text.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0x88000000);
		text.borderSize = 3.0;
		add(text);
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

		icon.x = PlayState.instance.iconP1.x + 100;
		icon.scale.set(PlayState.instance.iconP1.scale.x, PlayState.instance.iconP1.scale.y);

		text.x = PlayState.instance.iconP1.x + 100;
		text.scale.set(PlayState.instance.iconP1.scale.x, PlayState.instance.iconP1.scale.y);

		icon.alpha = PlayState.instance.iconP1.alpha;
		text.alpha = PlayState.instance.iconP1.alpha;

		switch (effect)
		{
			case 'bleed':
				text.text = FlxMath.roundDecimal(bleed_Dura, 1) + 's\n' + bleed_Stack + 'x';
				text.color = FlxColor.fromRGB(255, 255 - (2 * bleed_Dura), 255 - (1 * bleed_Dura));
			case 'timeStop':
				text.text = FlxMath.roundDecimal(timeStop_Dura, 1) + 's';
			case 'reducedRecovery':
				text.text = FlxMath.roundDecimal(reducedRecovery_Dura, 1) + 's\n' + reducedRecovery_Stack + 'x';
				text.color = FlxColor.fromRGB(255, 255 - (2 * reducedRecovery_Dura), 255 - (1 * reducedRecovery_Dura));

			case 'divineProtection':
				text.text = '';
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
		super.destroy();
	}
}
