import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import funkin.game.HealthIcon;
import funkin.savedata.FunkinSave;
import util.GenUtil;

class CreditInfoUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var creditinfo_Sprite:FunkinSprite;

	public var creditinfo_Text:FlxText;

	public var selected(default, set):Bool = false;
	public var text(default, set):String = 'Button';

	public function new(?x:Float = 0, ?y:Float = 0, ?creditdata = null)
	{
		super(x, y);

		group = new FlxSpriteGroup(x, y);

		creditinfo_Sprite = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/freeplay/borders/base'), true, 980, 122);
		creditinfo_Sprite.addAnim('normal', null, 0, false, false, [0]);
		group.add(creditinfo_Sprite);
		creditinfo_Sprite.playAnim('normal');

		creditinfo_Icon = new FunkinSprite(-5, -20).loadGraphic(Paths.image('ui/credits/icons/${creditdata.imgName}'));
		group.add(creditinfo_Icon);
		creditinfo_Icon.playAnim('normal');

		creditinfo_Text = new FlxText(0, 0, creditinfo_Sprite.width + (creditinfo_Sprite.width * 0.35), creditdata.name);
		creditinfo_Text.setFormat(Paths.font("shingo.otf"), 48, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		creditinfo_Text.borderSize = 3.5;
		creditinfo_Text.setPosition(150, 20);
		group.add(creditinfo_Text);

		creditinfo_Role_Text = new FlxText(150, 75, 0, creditdata.role);
		creditinfo_Role_Text.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		creditinfo_Role_Text.borderSize = 3.5;
		group.add(creditinfo_Role_Text);

		if (creditdata.tworow)
		{
			creditinfo_Role_Text.y -= 8;
			creditinfo_Role_Text.size -= 1;
		}

		selected = this.selected;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			creditinfo_Sprite.color = FlxColor.WHITE;
			creditinfo_Icon.color = FlxColor.WHITE;
			creditinfo_Text.color = FlxColor.WHITE;
			creditinfo_Role_Text.color = FlxColor.WHITE;
		}
		else
		{
			creditinfo_Sprite.color = FlxColor.GRAY;
			creditinfo_Icon.color = FlxColor.GRAY;
			creditinfo_Text.color = FlxColor.GRAY;
			creditinfo_Role_Text.color = FlxColor.GRAY;
		}

		return (selected = isSelected);
	}

	function set_text(newText:String):String
	{
		songinfo_Text.text = newText;

		return (text = newText);
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
