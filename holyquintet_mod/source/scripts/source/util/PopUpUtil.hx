import openfl.text.TextFormat;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import lime.app.Application;

public static var popups:Array<Sprite> = [];

class PopUpUtil
{
	public static function gjPopup(message:String)
	{
		var popup = new Sprite();
		Main.instance.addChild(popup);
		popups.push(popup);

		bg = new Bitmap(Assets.getBitmapData(Paths.image('ui/common/gjpopup'), true, false));
		popup.addChild(bg);
		popup.x = window.width / 2 - bg.width / 2;
		popup.y -= 250;

		// test2 = new FlxText(0, 0, bg.width, 'Hello world');
		// test2.setFormat(Paths.font("shingo.otf"), 24, 0xFF0D090D, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.WHITE);
		// test2.borderSize = 3.0;

		for (i in 0...9)
		{
			var popupTextOutLine = new TextField();
			popupTextOutLine.autoSize = TextFieldAutoSize.CENTER;
			popupTextOutLine.width = bg.width;
			popupTextOutLine.text = message;
			popupTextOutLine.defaultTextFormat = new TextFormat(Paths.getFontName(Paths.font('shingo.otf')), 32, 0xFF0D090D);
			popupTextOutLine.selectable = false;
			popupTextOutLine.x = bg.width / 2 - popupTextOutLine.width / 2;
			popupTextOutLine.y = bg.height / 2 - 20;
			popupTextOutLine.textColor = 0xFFFFFFFF;

			if (i == 0 || i == 3 || i == 6)
				popupTextOutLine.x -= 3;

			if (i == 2 || i == 5 || i == 8)
				popupTextOutLine.x += 3;

			if (i == 0 || i == 1 || i == 2)
				popupTextOutLine.y -= 3;

			if (i == 6 || i == 7 || i == 8)
				popupTextOutLine.y += 3;

			popup.addChild(popupTextOutLine);
		}

		popupText = new TextField();
		popupText.autoSize = TextFieldAutoSize.CENTER;
		popupText.width = bg.width;
		popupText.text = message;
		popupText.defaultTextFormat = new TextFormat(Paths.getFontName(Paths.font('shingo.otf')), 32, 0xFF0D090D);
		popupText.selectable = false;
		popupText.x = bg.width / 2 - popupText.width / 2;
		popupText.y = bg.height / 2 - 20;
		popup.addChild(popupText);

		FlxTween.tween(popup, {y: popup.y + 275}, 0.5, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(3.0, function(tmr:FlxTimer)
				{
					FlxTween.tween(popup, {y: popup.y - 275}, 0.5, {
						ease: FlxEase.quadIn,
						onComplete: function(twn:FlxTween)
						{
							Main.instance.removeChild(popup);
							popups.remove(popup);
						}
					});
				});
			}
		});
	}
}
