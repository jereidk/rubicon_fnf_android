import funkin.play.character.SparrowCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.play.GameOverSubState;
import funkin.graphics.adobeanimate.FlxAtlasSprite;
import flixel.util.FlxTimer;
import funkin.graphics.FunkinSprite;
import funkin.audio.FunkinSound;
import funkin.Paths;
import flixel.FlxSprite;
import flixel.FlxG;
import funkin.modding.base.ScriptedFunkinSprite;
import funkin.play.PauseSubState;
import funkin.modding.module.ModuleHandler;
import flixel.tweens.FlxTween;

class DefaultStaticCharacter extends SparrowCharacter
{
	function new()
	{
		super('engine/defaultStatic');
	}

	//var staticSound:FunkinSound;
	var opponentOffsets = [
		"idle" => [0, 0],
		"singLEFT" => [-23, 133],
		"singLEFT-hold" => [-23, 133],
		"singLEFT-end" => [-23, 133],
		"singUP" => [-67, 318],
		"singUP-hold" => [-67, 318],
		"singUP-end" => [-67, 318],
		"singDOWN" => [21, -88],
		"singDOWN-hold" => [21, -88],
		"singDOWN-end" => [21, -88],
		"singRIGHT" => [171, 243],
		"singRIGHT-hold" => [171, 243],
		"singRIGHT-end" => [171, 243],
	];

	function onAdd(event:ScriptEvent)
	{
		super.onAdd(event);

		flipSingAnimations = characterType == CharacterType.DAD;

		if (characterType == CharacterType.DAD)
			animationOffsets = opponentOffsets;

		/*staticSound = new FunkinSound();
		staticSound.loadEmbedded(Paths.sound('static loop'));
		staticSound.looped = true;
		staticSound.volume = .3;
		staticSound.play();
		FlxG.sound.defaultSoundGroup.add(staticSound);
		FlxG.sound.list.add(staticSound);*/

	}
	/*
	function onPause()
	{
		staticSound.pause();
	}

	function onResume()
	{
		staticSound.resume();
	}
	*/
	var DEATH_THRESHOLD:Float = 0.125 * 2;
	var LOSING_THRESHOLD:Float = 0.2 * 2;
	var WINING_THRESHOLD:Float = 0.8 * 2;

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);

		icon.size.set(.8, .8);
		icon.updateHealthIcon = (health:Float) -> {
			switch (icon.getCurrentAnimation())
			{
				case "winning":
					health < WINING_THRESHOLD ? icon.playAnimation("fromWinning", "idle") : icon.playAnimation("winning", "idle");

				case "idle":
					if (health > WINING_THRESHOLD)
						icon.playAnimation("toWinning"); //icon.playAnimation("winning");
					else if (health < LOSING_THRESHOLD)
						icon.playAnimation("toLosing");
					else
						icon.playAnimation("idle");

				case "losing":
					if (health < DEATH_THRESHOLD)
						icon.playAnimation("toDeath");
					else if (health > LOSING_THRESHOLD)
						icon.playAnimation("fromLosing");
					else
						icon.playAnimation("losing");

				case "death":
					if (health > DEATH_THRESHOLD && health < LOSING_THRESHOLD)
						icon.playAnimation("fromDeath");
					else if (health > LOSING_THRESHOLD)
						icon.playAnimation("idle");
					else
						icon.playAnimation("death");


				/////////////////////////////////
				case "toWinning":
					//icon.frameOffset.y = 7.55;
					if (icon.isAnimationFinished())
						icon.playAnimation("winning", "idle");
				case "fromWinning":
					//icon.frameOffset.y = 7.55;
					if (icon.isAnimationFinished())
						icon.playAnimation("idle");

				case "toLosing":
					//icon.frameOffset.y = 6.0;
					if (icon.isAnimationFinished())
						icon.playAnimation("losing", "idle");
				case "fromLosing":
					//icon.frameOffset.y = 7.0;
					if (icon.isAnimationFinished())
						icon.playAnimation("idle");

				case "toDeath":
					//icon.frameOffset.y = 7.0;
					if (icon.isAnimationFinished())
						icon.playAnimation("death", "idle");
				case "fromDeath":
					//icon.frameOffset.y = 8.55;
					if (icon.isAnimationFinished())
						icon.playAnimation("losing");


				/////////////////////////////////
				default:
					icon.playAnimation("idle", null, false);
			}
		}

		icon.animation.addByIndices("idle", "face", [0, 1, 2, 3, 4, 5, 6, 7, 8], "", 24, true);

		icon.animation.addByIndices("winning", "face", [13, 14, 15, 16, 17, 18, 19, 20, 21], "", 24, true);
		icon.animation.addByIndices("toWinning", "face", [9, 10, 11, 12], "", 24, false); icon.animation.addByIndices("fromWinning", "face", [12, 11, 10, 9], "", 24, false);

		icon.animation.addByIndices("losing", "face", [26, 27, 28, 29, 30, 31, 32, 33, 34], "", 24, true);
		icon.animation.addByIndices("toLosing", "face", [22, 23, 24, 25], "", 24, false); icon.animation.addByIndices("fromLosing", "face", [25,24,23,22], "", 24, false);


		/*icon.animation.addByPrefix("winning", "win0", 1, true);
		icon.animation.addByPrefix("idle", "basic0", 1, true);
		icon.animation.addByPrefix("losing", "lose0", 1, true);
		icon.animation.addByPrefix("death", "predeath0", 1, true);

		icon.animation.addByPrefix("toWinning", "basic-to-win0", 24, false); icon.animation.addByPrefix("fromWinning", "win-to-basic0", 24, false);
		icon.animation.addByPrefix("toLosing", "basic-to-lose0", 24, false); icon.animation.addByPrefix("fromLosing", "lose-to-basic0", 24, false);
		icon.animation.addByPrefix("toDeath", "lose-to-predeath0", 24, false); icon.animation.addByPrefix("fromDeath", "predeath-to-lose0", 24, false);*/

		icon.flipX = isOpponent;

		//icon.animOffsets = customOffsets ?? ["default" => [0, 0]];
		return icon;


		//return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon, !isOpponent]);
	}

	/*override function destroy()
	{
		staticSound.destroy();
		super.destroy();
	}*/

}
