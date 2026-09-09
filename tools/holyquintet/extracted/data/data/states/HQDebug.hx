import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import openfl.display.BitmapData;
import haxe.io.Bytes;
import sys.io.File;
import sys.net.Http;
import funkin.backend.utils.HttpUtil;

using StringTools;

function create()
{
	if (FlxG.sound.music != null)
		FlxG.sound.music.stop();

	debug_text = new FlxText(0, 150, 1920, 'DEBUG\n\nZ - Title State\nX - MainMenu State');
	debug_text.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	add(debug_text);
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	// if (FlxG.keys.justPressed.Z)
	//	FlxG.switchState(new ModState("HQMainMenu"));

	// if (FlxG.keys.justPressed.X)
	//	FlxG.switchState(new ModState("HQMainMenu"));
}
