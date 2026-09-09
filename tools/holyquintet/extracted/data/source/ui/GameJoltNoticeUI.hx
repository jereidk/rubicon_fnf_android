import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import util.GenUtil;

class GameJoltNoticeUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public function new(message:String)
	{
		super();

		group = new FlxSpriteGroup();

		back = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/gjpopup'));
		group.add(back);

		message = new FlxText(0, 0, back.width, message);
		message.setFormat(Paths.font("shingo.otf"), 24, 0xFF0D090D, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.WHITE);
		message.borderSize = 3.0;
		group.add(message);
		GenUtil.alignToCenter(message, back);
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
