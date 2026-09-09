import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import util.GenUtil;

FlxG.sound.load(Paths.sound('ui/gauntlet/mod_selected'));
FlxG.sound.load(Paths.sound('ui/gauntlet/mod_unselected'));
class ClearConditionUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var cleared(default, set):Bool = false;

	public var makeSound:Bool = true;

	public function new(condition:String)
	{
		super();

		group = new FlxSpriteGroup();

		back = new FunkinSprite(0, 750).loadGraphic(Paths.image('game/conditions/cond_base'));
		group.add(back);

		cond_icon = new FunkinSprite(0, 750).loadGraphic(Paths.image('game/conditions/cond_icon'), true, 65, 65);
		cond_icon.addAnim('empty', null, 0, false, false, [0]);
		cond_icon.addAnim('cleared', null, 0, false, false, [1]);
		add(cond_icon);
		cond_icon.playAnim('empty', true);

		message = new FlxText(back.x + 65, back.y, back.width, i18n.tr('Gameplay/Condition/$condition', ["num" => requiredComboCount]));
		message.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x88000000);
		message.borderSize = 3.0;
		group.add(message);
		message.y = back.y + back.height / 2 - message.height / 2;

		switch (PlayState.SONG.meta.customValues.uiStyle)
		{
			case 'MegucaUI':
				group.x -= 40;
				group.y += 250;
				back.visible = false;
				cond_icon.visible = false;
				message.setFormat(Paths.font("arial.ttf"), 32, FlxColor.RED, FlxTextAlign.LEFT);
		}

		cleared = this.cleared;
	}

	function set_cleared(isCleared:Bool):Bool
	{
		switch (PlayState.SONG.meta.customValues.uiStyle)
		{
			case 'MegucaUI':
				if (isCleared && cleared != isCleared)
				{
					message.color = FlxColor.GREEN;
				}
				else
				{
					message.color = FlxColor.RED;
				}

			default:
				if (isCleared && cleared != isCleared)
				{
					var cond_iconChange:FunkinSprite = new FunkinSprite(0, 0).loadGraphic(Paths.image("ui/gauntlet/modtickchange"));
					add(cond_iconChange);
					cond_iconChange.scale.set(0.75, 0.75);
					cond_iconChange.blend = BlendMode.ADD;
					GenUtil.alignToCenter(cond_iconChange, cond_icon);
					FlxTween.tween(cond_iconChange, {
						'scale.x': 2.0,
						'scale.y': 2.0,
						alpha: 0.0
					}, 3.5, {
						ease: FlxEase.expoOut,
						onComplete: function(twn:FlxTween)
						{
							cond_iconChange.destroy();
							remove(cond_iconChange, true);
						}
					});

					FlxTween.cancelTweensOf(cond_icon);
					cond_icon.scale.set(1.5, 1.5);
					FlxTween.tween(cond_icon, {'scale.x': 1.0, 'scale.y': 1.0}, 1.5, {ease: FlxEase.expoOut});

					cond_icon.playAnim('cleared');

					if (makeSound)
						FlxG.sound.play(Paths.sound('ui/gauntlet/mod_selected'), 1.0 * Options.volumeSFX);
				}
				else
				{
					cond_icon.playAnim('off');
				}
		}

		return (cleared = isCleared);
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
