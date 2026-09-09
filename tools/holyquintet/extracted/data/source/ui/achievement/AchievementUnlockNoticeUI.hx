import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import util.GenUtil;
import ui.achievement.AchievementUI;

class AchievementUnlockNoticeUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public function new(achievement:String)
	{
		super();

		popupData = achievementData.get(achievement);
		group = new FlxSpriteGroup();

		back = new FunkinSprite(0, 750).loadGraphic(Paths.image('ui/common/achievement_back'));
		group.add(back);
		back.alpha = 0.75;

		switch (popupData.diff)
		{
			case 0:
				back.color = 0xFF9A6D4F;
			case 1:
				back.color = 0xFF99ACAE;
			case 2:
				back.color = 0xFFCFB375;
			case 3:
				back.color = 0xFF82D0EF;
		}

		achievementIcon = new AchievementUI(0, 750, achievement);
		group.add(achievementIcon.group);
		achievementIcon.achievement_Frame.color = FlxColor.WHITE;
		achievementIcon.achievement_Icon.color = FlxColor.WHITE;
		achievementIcon.group.scale.set(0.5, 0.5);
		achievementIcon.group.setPosition(back.x - 52, back.y - 42);

		message = new FlxText(back.x + 150, back.y, back.width,
			i18n.tr('Accolades/Achievements/Names/${popupData.nameKey}') + '\n${i18n.tr('Accolades/Achievements/Earned')}');
		message.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x88000000);
		message.borderSize = 3.0;
		group.add(message);
		message.y = back.y + back.height / 2 - message.height / 2;

		group.x -= 500;
		group.alpha = 0.0;
		FlxTween.tween(group, {x: group.x + 500, alpha: 1.0}, 1.0, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				FlxTween.tween(group, {x: group.x - 500, alpha: 0.0}, 1.0, {
					ease: FlxEase.quadIn,
					startDelay: 1.0,
					onComplete: function(twn:FlxTween)
					{
						destroy();
					}
				});
			}
		});
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
