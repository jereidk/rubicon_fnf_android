import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;

var bgs:Array<FunkinSprite> = [];

function create()
{
	startUIvisablityArgs = [true, true, true, false, true, 0, false, 4, "linear", "In"];

	for (i in 0...6)
	{
		background = new FunkinSprite(0, 0);
		background.loadSprite(Paths.image('stages/stardom/$i'));
		background.scale.set(2.0, 2.0);
		background.scrollFactor.set(0.0, 0.0);
		add(background);
		bgs.push(background);
		background.ID = i;
		background.alpha = 0.0;
		background.color = FlxColor.GRAY;
		background.zoomFactor = 0.0;
		background.screenCenter();
		if (i == 0)
			background.alpha = 1.0;
	}

	lyricText = new FlxText(0, 850, FlxG.width, '');
	lyricText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	lyricText.borderSize = 2.5;
	add(lyricText);
	lyricText.cameras = [camHUD];
}

function postCreate()
{
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	health = 2;
	purity = 1;
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Lyric":
				lyricText.text = params[1] + '\n' + params[2];

			case "Crossfade":
				for (spr in bgs)
				{
					if (spr.ID == Std.int(params[1]))
						FlxTween.tween(spr, {alpha: 1.0}, 1.0, {ease: FlxEase.quadInOut});
				}
		}
	}
}
