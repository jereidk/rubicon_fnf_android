import funkin.play.character.MultiSparrowCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.play.GameOverSubState;
import funkin.graphics.adobeanimate.FlxAtlasSprite;
import flixel.util.FlxTimer;
import funkin.graphics.FunkinSprite;
import funkin.audio.FunkinSound;
import funkin.Paths;
import funkin.Conductor;
import flixel.FlxSprite;
import flixel.FlxG;
import funkin.modding.base.ScriptedFunkinSprite;
import flixel.group.FlxTypedSpriteGroup;
import flixel.effects.FlxFlicker;
import funkin.play.PauseSubState;
import funkin.modding.module.ModuleHandler;
import flixel.tweens.FlxTween;
import funkin.play.components.HealthIcon;

class KomiStandCharacter extends MultiSparrowCharacter
{
	function new()
	{
		super('komi-stand');
	}

	function playAnimation(name:String, restart:Bool, ignoreOther:Bool, reverse:Bool)
	{
		super.playAnimation(name, restart, ignoreOther, reverse);
		if (name == "endConv")
			this.danceEvery = 99999;
	}

	var LOSING_THRESHOLD:Float = 0.25 * 2;

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		icon.updateHealthIcon = (h:Float) ->
		{
			final health = h;
			switch (icon.getCurrentAnimation())
			{
				case "idle":
					if (health < LOSING_THRESHOLD) icon.playAnimation("toLosing");

				case "losing":
					if (health > LOSING_THRESHOLD) icon.playAnimation("fromLosing");

				case "toLosing":
					if (icon.isAnimationFinished()) icon.playAnimation("losing", "idle");
				case "fromLosing":
					if (icon.isAnimationFinished()) icon.playAnimation("idle");

				default:
					icon.playAnimation("idle", null, false);
			}
		}
		icon.animation.addByPrefix("losing", "lose0", 1, true);
		icon.animation.addByPrefix("idle", "basic0", 1, true);

		icon.animation.addByPrefix("toLosing", "basic-to-lose", 24, false);
		icon.animation.addByPrefix("fromLosing", "lose-to-basic", 24, false);
		icon.playAnimation("idle", null, true);

		icon.animOffsets = ["toLosing" => [6, 1]];
		return icon;
	}
}
