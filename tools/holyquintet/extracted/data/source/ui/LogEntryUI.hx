import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;

class LogEntryUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var narration:Bool = true;

	public function new(data:Dynamic, id:Int)
	{
		super();

		group = new FlxSpriteGroup();

		// super band-aid fix to fix incorrect logs
		if (PlayState.SONG.meta.name == 'resonance')
		{
			switch (id)
			{
				case 7 | 10 | 12 | 16 | 23 | 25:
					data.name = 'sayaka';

				case 8 | 11 | 14 | 18 | 24:
					data.name = 'mami';

				case 9 | 13 | 17 | 21 | 26:
					data.name = 'madoka';

				case 15 | 19 | 20 | 22:
					data.name = 'girlfriend';
			}
		}

		if (PlayState.SONG.meta.name == 'partea')
		{
			if (id >= 26)
			{
				id += 1;
			}
		}

		if (PlayState.SONG.meta.name == 'out-of-time')
		{
			switch (id)
			{
				case 6 | 7 | 19 | 20:
					data.name = 'homura';

				case 17 | 18:
					data.name = 'girlfriend';
			}
		}

		chartab = new FunkinSprite(0, -50).loadGraphic(Paths.image('game/dialogue/log/chartab'));
		add(chartab);
		chartab.color = convertSpeakerColor(data.name);

		bg = new FunkinSprite(0, 0).loadGraphic(Paths.image('game/dialogue/log/bg'));
		add(bg);

		charTxt = new FlxText(20, -42, 0, convertSpeakerName(data.name));
		charTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.LEFT);
		add(charTxt);

		var translatedName:String = PlayState.SONG.meta.displayName;
		if (PlayState.SONG.meta.name == 'eternalstar')
			translatedName = 'EternalStar';

		var iconName:String = data.name;
		if (iconName == 'girlfriend')
			iconName = 'gf';

		icon = new HealthIcon(iconName);
		group.add(icon);

		var textPosition = 25;
		var textWidth = bg.width - 25;

		if (data.name != '')
			narration = false;

		if (!narration)
		{
			textPosition = 175;
			textWidth = bg.width - 175;
		}

		dialogueTxt = new FlxText(textPosition, 20, textWidth, i18n.tr('Dialogue/${translatedName}/${id}'));
		dialogueTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.BLACK, FlxTextAlign.LEFT);
		add(dialogueTxt);

		if (narration)
		{
			chartab.visible = false;
			bg.color = FlxColor.BLACK;
			bg.alpha = 0.5;
			dialogueTxt.color = FlxColor.WHITE;
			dialogueTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
			dialogueTxt.borderSize = 3.0;

			icon.visible = false;

			bg.y -= 25;
			dialogueTxt.y -= 25;
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
		super.destroy();
	}

	function convertSpeakerName(name:String):String
	{
		var convertedName:String = '';

		switch (name)
		{
			case 'girlfriend':
				convertedName = 'Girlfriend';
			case 'sayaka':
				convertedName = 'Sayaka Miki';
			case 'mami':
				convertedName = 'Mami Tomoe';
			case 'madoka':
				convertedName = 'Madoka Kaname';
			case 'kyoko':
				convertedName = 'Kyoko Sakura';
			case 'homura':
				convertedName = 'Homura Akemi';
			case 'nagisa':
				convertedName = 'Nagisa Momoe';
			case 'unknown':
				convertedName = '???';
		}

		return convertedName;
	}

	function convertSpeakerColor(name:String):FlxColor
	{
		var convertedColor:FlxColor = FlxColor.WHITE;

		switch (name)
		{
			case 'girlfriend':
				convertedColor = 0xFFD00D2B;
			case 'sayaka':
				convertedColor = 0xFF72AEDA;
			case 'mami':
				convertedColor = 0xFFFFEC76;
			case 'madoka':
				convertedColor = 0xFFFBA8BC;
			case 'kyoko':
				convertedColor = 0xFFA83658;
			case 'homura':
				convertedColor = 0xFF3A3A3A;
			case 'nagisa':
				convertedColor = 0xFFFFA6AC;
			case 'unknown':
				convertedColor = 0xFF0D090D;
		}

		return convertedColor;
	}
}
