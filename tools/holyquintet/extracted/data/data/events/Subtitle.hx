import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;

function postCreate()
{
	subtitleText = new FlxText(0, 800, FlxG.width, '');
	subtitleText.setFormat(Paths.font("arial.ttf"), 42, FlxColor.YELLOW, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	subtitleText.borderSize = 2.0;
	add(subtitleText);
	subtitleText.cameras = [camUI];
}

function onEvent(e)
{
	if (e.event.name == "Subtitle")
	{
		var params:Array = e.event.params;

		subtitleText.text = params[0];
	}
}
