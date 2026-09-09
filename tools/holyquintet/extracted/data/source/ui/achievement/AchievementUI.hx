import flixel.input.keyboard.FlxKey;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

using StringTools;

class AchievementUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var data:Dynamic;

	public var selected(default, set):Bool = false;

	var locked:Bool = false;

	public var achievement_Frame:FunkinSprite;
	public var achievement_Icon:FunkinSprite;

	public function new(?x:Float = 0, ?y:Float = 0, ?achievement:String)
	{
		super(x, y, achievement);

		data = achievementData.get(achievement);
		locked = GenUtil.isAchievementLocked(data.nameKey);
		group = new FlxSpriteGroup(x, y);

		var border:String = 'bronze';
		switch (data.diff)
		{
			case 0:
				border = 'bronze';
			case 1:
				border = 'silver';
			case 2:
				border = 'gold';
			case 3:
				border = 'platinum';
		}

		achievement_Frame = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/accolades/frames/$border'));
		group.add(achievement_Frame);

		achievement_Icon = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/accolades/achievements/${data.img}'));
		group.add(achievement_Icon);

		group.scale.set(0.75, 0.75);

		if (locked)
		{
			achievement_Frame.color = FlxColor.GRAY;
			achievement_Icon.color = FlxColor.BLACK;
		}

		selected = this.selected;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected && !locked)
		{
			achievement_Frame.color = FlxColor.WHITE;
			achievement_Icon.color = FlxColor.WHITE;
		}
		else
		{
			achievement_Frame.color = isSelected ? FlxColor.GRAY : 0xFF3F3F3F;
			achievement_Icon.color = locked ? FlxColor.BLACK : FlxColor.GRAY;
		}

		return (selected = isSelected);
	}

	public function updateAchievementGraphic(newAchievement:String)
	{
		data = achievementData.get(newAchievement);
		locked = GenUtil.isAchievementLocked(data.nameKey);

		var border:String = 'bronze';
		switch (data.diff)
		{
			case 0:
				border = 'bronze';
			case 1:
				border = 'silver';
			case 2:
				border = 'gold';
			case 3:
				border = 'platinum';
		}
		achievement_Frame.loadGraphic(Paths.image('ui/accolades/frames/$border'));
		achievement_Icon.loadGraphic(Paths.image('ui/accolades/achievements/${data.img}'));

		selected = selected;
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
