import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import openfl.display.BitmapData;
import haxe.io.Bytes;
import sys.io.File;
import util.GenUtil;
import funkin.backend.utils.DiscordUtil;

var waitTimer:Float = 2.0;
var accepted:Bool = false;

function create()
{
	DiscordUtil.changePresenceSince("In Disclaimer", null);
	if (FlxG.sound.music != null)
		FlxG.sound.music.stop();

	disc = new FunkinSprite().loadGraphic(Paths.image('ui/main/disclaimer'));
	disc.scale.set(1.5, 1.5);
	add(disc);
	disc.screenCenter();

	discText = new FlxText(0, 340, FlxG.width, i18n.tr('Disclaimer'));
	discText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	discText.borderSize = 2.5;
	add(discText);

	fadeoutSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	fadeoutSprite.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(fadeoutSprite);
	fadeoutSprite.alpha = 1.0;

	FlxTween.tween(fadeoutSprite, {alpha: 0}, 1.0, {
		ease: FlxEase.quadInOut,
		onComplete: function(twn:FlxTween)
		{
		}
	});
}

var totalElapsed:Float = 0.0;
var updateShader:Float = 0.3;

function update(elapsed:Float)
{
	updateShader -= elapsed;
	totalElapsed += elapsed;

	waitTimer -= elapsed;

	if (controls.ACCEPT && waitTimer <= 0 && !accepted)
	{
		GenUtil.playUISound('confirm');
		accepted = true;

		FlxTween.tween(fadeoutSprite, {alpha: 1}, 1.0, {
			ease: FlxEase.quadInOut,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(1.0, function(tmr:FlxTimer)
				{
					FlxG.switchState(new ModState("HQTitle"));
				});
			}
		});
	}
}
