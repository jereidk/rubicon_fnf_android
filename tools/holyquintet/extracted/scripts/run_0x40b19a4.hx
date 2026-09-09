import flixel.input.keyboard.FlxKey;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

class SettingOptionUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var option_BG:FunkinSprite;
	public var option_Name:FlxText;
	public var option_Desc:FlxText;
	public var option_Setting:FlxText;

	var currentValue:Dynamic;

	public var data:Dynamic;

	public var selected(default, set):Bool = false;
	public var active(default, set):Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0, ?theData:Dynamic)
	{
		super(x, y, theData);
		data = theData;

		group = new FlxSpriteGroup(x, y);

		option_BG = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/settings/optionback'));
		group.add(option_BG);

		option_Name = new FlxText(75, 20, option_BG.width, i18n.tr('Settings/${data.nameKey}'));
		option_Name.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		option_Name.borderSize = 2.0;
		group.add(option_Name);

		option_Desc = new FlxText(75, 60, option_BG.width, data.descriptionKey);
		option_Desc.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		option_Desc.borderSize = 1.5;
		group.add(option_Desc);
		option_Desc.alpha = 0.75;

		switch (data.type)
		{
			case 'bool':
				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
			case 'int':
				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
			case 'float':
				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
			case 'language':
				option_Flag = new FunkinSprite(-25, -25).loadGraphic(Paths.image('ui/settings/${data.nameKey.toLowerCase()}'));
				group.add(option_Flag);
				option_Flag.scale.set(0.75, 0.75);

				option_Name.x += 150;
				option_Desc.x += 150;

				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
			case 'control':
				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
			case 'separator':
				option_Name.text = '';
				option_Desc.text = '';

				option_Setting = new FlxText(75, 35, option_BG.width - 150, formatCurOption());
				option_Setting.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				option_Setting.borderSize = 2.0;
				group.add(option_Setting);
		}

		option_Desc.text = '';
		option_Name.x -= 10;
		option_Name.y += 11;

		selected = this.selected;
		active = this.active;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			option_BG.color = FlxColor.WHITE;
			option_Name.color = FlxColor.WHITE;
			if (data.nameKey == 'DestroySaveData')
				option_Name.color = FlxColor.RED;

			option_Desc.color = FlxColor.WHITE;
			if (data.type != 'separator' && option_Setting != null)
				option_Setting.color = FlxColor.WHITE;
			if (data.type == 'language' && option_Flag != null)
				option_Flag.color = FlxColor.WHITE;
		}
		else
		{
			option_BG.color = FlxColor.BLACK;
			option_Name.color = FlxColor.GRAY;
			option_Desc.color = FlxColor.GRAY;
			if (data.type != 'separator' && option_Setting != null)
				option_Setting.color = FlxColor.GRAY;
			if (data.type == 'language' && option_Flag != null)
				option_Flag.color = FlxColor.GRAY;

			if (data.nameKey == 'DestroySaveData')
				option_Name.color = 0xFF880000;
		}

		return (selected = isSelected);
	}

	function set_active(isActive:Bool):Bool
	{
		if (isActive)
		{
			option_BG.alpha = 1.0;
			option_Name.alpha = 1.0;
			option_Desc.alpha = 0.75;
			if (data.type != 'separator' && option_Setting != null)
				option_Setting.alpha = 1.0;
			if (data.type == 'language' && option_Flag != null)
				option_Flag.alpha = 1.0;
		}
		else
		{
			option_BG.alpha = 0.5;
			option_Name.alpha = 0.5;
			option_Desc.alpha = 0.25;
			if (data.type != 'separator' && option_Setting != null)
				option_Setting.alpha = 0.5;
			if (data.type == 'language' && option_Flag != null)
				option_Flag.alpha = 0.5;
		}

		return (active = isActive);
	}

	public function selection(change:Int)
	{
		var currentValue = Reflect.field(Options, data.parentValue);

		switch (data.type)
		{
			case 'bool':
				currentValue = !currentValue;

				if (!currentValue)
					GenUtil.playUISound('on');
				else
					GenUtil.playUISound('off');
			case 'int':
				currentValue = FlxMath.bound(currentValue + change, data.lowerLimit, data.upperLimit);
			case 'float':
				currentValue = FlxMath.bound(currentValue + change, data.lowerLimit, data.upperLimit);
			case 'language':
				currentValue = data.defaultValue;
		}

		Reflect.setField(Options, data.parentValue, currentValue);
		FlxG.save.flush();

		switch (data.parentValue)
		{
			case 'autoPause':
				FlxG.autoPause = currentValue;
			case 'framerate':
				if (FlxG.updateFramerate < currentValue)
					FlxG.drawFramerate = FlxG.updateFramerate = currentValue;
				else
					FlxG.updateFramerate = FlxG.drawFramerate = currentValue;
			case 'antialiasing':
				FlxG.game.stage.quality = (FlxG.enableAntialiasing = currentValue) ? 'BEST' : 'LOW';
			case 'songOffset':
				Conductor.songOffset = currentValue;
		}

		option_Setting.text = formatCurOption();
	}

	public function formatCurOption():String
	{
		var returnedString:String = '';
		var currentValue = Reflect.field(Options, data.parentValue);

		switch (data.type)
		{
			case 'bool':
				if (currentValue)
					returnedString = i18n.tr('Settings/On');
				else
					returnedString = i18n.tr('Settings/Off');
			case 'int':
				returnedString = currentValue;
			case 'float':
				returnedString = currentValue;
			case 'language':
				returnedString = '';
				if (data.defaultValue == Options.language)
					returnedString = i18n.tr('Settings/Selected');
			case 'control':
				returnedString = CoolUtil.keyToString(currentValue[0]);
		}

		if (data.parentValue == 'strumUnderlayAlpha')
			returnedString += '%';

		if (data.parentValue == 'songOffset')
			returnedString += 'ms';

		if (data.parentValue == 'playerStrumSpeed')
			returnedString += 'x';

		if (data.parentValue == 'framerate')
			returnedString += ' FPS';

		return returnedString;
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
