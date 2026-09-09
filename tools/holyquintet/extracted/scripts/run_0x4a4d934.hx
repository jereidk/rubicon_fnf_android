import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;

class StatTextUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var stat:String = '';

	var headerTxt:FlxText;
	var statTxt:FlxText;

	var rainbow:Bool = false;

	var psi = PlayState.instance;

	var hueShader:CustomShader;

	public function new(newStat:String, yPos:Float)
	{
		super();

		group = new FlxSpriteGroup();
		stat = newStat;

		headerTxt = new FlxText(0, yPos + 70, 225, stat);
		headerTxt.setFormat(Paths.font("shingo.otf"), 24, 0xFFBFBFBF, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
		headerTxt.borderSize = 2.0;
		add(headerTxt);
		headerTxt.scale.x = 0.85;

		statTxt = new FlxText(headerTxt.x, headerTxt.y + 25, 225, '-');
		statTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
		statTxt.borderSize = 2.0;
		add(statTxt);

		if (Options.gameplayShaders)
		{
			hueShader = new CustomShader("adjustColor");
			statTxt.shader = hueShader;
			hueShader.hue = 15.0;
			hueShader.contrast = 0.0;
			hueShader.saturation = 0.0;
		}

		var keyString:String = '';
		switch (newStat)
		{
			case 'Breaks':
				keyString = 'Breaks';

			case 'Score':
				keyString = 'Score';

			case 'Accuracy':
				keyString = 'Accuracy';

			case 'FC Rank':
				keyString = 'FCRank';

			case 'Atks. Sustained':
				keyString = 'AttacksSustained';
		}

		headerTxt.text = i18n.tr('Gameplay/$keyString');
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

		if (psi.hits.get('sick') >= 1 && psi.hits.get('good') == 0 && psi.hits.get('bad') == 0 && psi.hits.get('shit') == 0 && psi.misses == 0)
			rainbow = true;
		else
			rainbow = false;

		if (rainbow && Options.gameplayShaders)
		{
			hueShader.hue += elapsed * 30;
			statTxt.color = 0xFF88FFFF;
		}
		else
		{
			statTxt.color = 0xFFFFFFFF;
		}

		switch (stat)
		{
			case 'Breaks':
				statTxt.text = psi.misses;
			case 'Accuracy':
				if (psi.totalAccuracyAmount == 0)
					statTxt.text = 'N/A';
				else
					statTxt.text = '${FlxMath.roundDecimal(psi.accuracy * 100, 2)}% [${psi.curRating.rating}]';
			case 'FC Rank':
				if (psi.totalAccuracyAmount == 0)
					statTxt.text = 'N/A';
				else
				{
					if (psi.hits.get('sick') >= 1 && psi.hits.get('good') == 0 && psi.hits.get('bad') == 0 && psi.hits.get('shit') == 0 && psi.misses == 0)
						statTxt.text = 'MFC';
					else if (psi.hits.get('good') >= 1 && psi.hits.get('bad') == 0 && psi.hits.get('shit') == 0 && psi.misses == 0)
						statTxt.text = 'GFC';
					else if (psi.hits.get('bad') >= 1 && psi.hits.get('shit') == 0 && psi.misses == 0)
						statTxt.text = 'FC';
					else if (psi.hits.get('shit') >= 1 && psi.misses == 0)
						statTxt.text = 'FC';
					else if (psi.misses >= 1 && psi.misses <= 9)
						statTxt.text = 'SDCB';
					else if (psi.misses >= 10)
						statTxt.text = 'Clear';
				}
			case 'Score Multiplier':
				statTxt.text = FlxMath.roundDecimal(comboMulti, 2) + 'x';
			case 'Atks. Sustained':
				statTxt.text = atksSustained;
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
