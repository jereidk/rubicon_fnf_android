import flixel.input.keyboard.FlxKey;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

using StringTools;

class EntryFieldUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var selected(default, set):Bool = false;

	public var entryString:FlxText;

	public var stringVisible(default, set):Bool = false;
	public var fakeString:FlxText;

	public function new(?x:Float = 0, ?y:Float = 0)
	{
		super(x, y);

		group = new FlxSpriteGroup(x, y);

		entryFieldBG = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/entryfield'));
		group.add(entryFieldBG);

		entryString = new FlxText(0, 0, entryFieldBG.width, '');
		entryString.setFormat(Paths.font("shingo.otf"), 36, 0xFF0D090D, FlxTextAlign.CENTER);
		group.add(entryString);
		entryString.y = entryFieldBG.y + entryFieldBG.height / 2 - entryString.height / 2;

		fakeString = new FlxText(0, 0, entryFieldBG.width, '');
		fakeString.setFormat(Paths.font("shingo.otf"), 36, 0xFF0D090D, FlxTextAlign.CENTER);
		group.add(fakeString);
		fakeString.y = entryFieldBG.y + entryFieldBG.height / 2 - fakeString.height / 2;
		fakeString.visible = false;

		selected = selected;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			entryFieldBG.color = FlxColor.WHITE;
		}
		else
		{
			entryFieldBG.color = FlxColor.GRAY;
		}

		return (selected = isSelected);
	}

	function set_stringVisible(isVisible:Bool):Bool
	{
		if (isVisible)
		{
			entryString.visible = true;
			fakeString.visible = false;
		}
		else
		{
			entryString.visible = false;
			fakeString.visible = true;
		}

		return (stringVisible = isVisible);
	}

	function pushKey(key:FlxKey)
	{
		var stringToAdd:String = CoolUtil.keyToString(key);

		var legalKeys:Array = [
			'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '0', '1', '2',
			'3', '4', '5', '6', '7', '8', '9', '-', '_', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'z',
			'x', 'c', 'v', 'b', 'n', 'm'
		];

		switch (stringToAdd)
		{
			case 'MINUS':
				if (!FlxG.keys.checkStatus(FlxKey.SHIFT))
					stringToAdd = '_';
				else
					stringToAdd = '-';
		}

		if (FlxG.keys.checkStatus(FlxKey.SHIFT))
			stringToAdd = stringToAdd.toLowerCase();

		for (i in legalKeys)
		{
			if (stringToAdd == i && entryString.text.length <= 33)
			{
				entryString.text += stringToAdd;
				fakeString.text += '*';
			}
		}

		if (key == 8)
		{
			entryString.text = entryString.text.substr(0, entryString.length - 1);
			fakeString.text = fakeString.text.substr(0, fakeString.length - 1);
		}

		// trace(stringToAdd);
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

		if (FlxG.keys.justPressed.ANY && selected)
		{
			pushKey(FlxG.keys.firstJustPressed());
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
