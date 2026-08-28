import funkin.modding.module.Module;
import funkin.util.Constants;
import funkin.util.MathUtil;
import funkin.audio.FunkinSound;
import funkin.ui.debug.charting.util.ChartEditorDropdowns;
import funkin.ui.debug.charting.ChartEditorState;
import funkin.Conductor;
import funkin.Highscore;
import openfl.display.animation.AnimatedSprite;
import Main;
import flixel.graphics.frames.FlxAtlasFrames;
import funkin.play.components.HealthIcon;
import funkin.play.Countdown;
import funkin.play.CountdownStep;
import flixel.system.FlxAssets;
import StringTools;
import grafex.util.HttpUtil;

class AnimaniaStuff extends Module
{
	function new()
	{
		super("AnimaniaStuff", 14);
		ChartEditorDropdowns.NOTE_KINDS.set("gf", "Girlfriend Note");
		ChartEditorDropdowns.NOTE_KINDS.set("both", "Parents (Both) Sings (Week 5)");
		ChartEditorDropdowns.NOTE_KINDS.set("parents-miss", "Parents Miss (Week 5)");
		ChartEditorDropdowns.NOTE_KINDS.set("cheer", "Cool Custom HEY Note wows");
		ChartEditorDropdowns.NOTE_KINDS.set("beatbox", "BeatBox Note (Fresh)");
		ChartEditorDropdowns.NOTE_KINDS.set("fresh", "Fresh Note (Fresh)");
		ChartEditorDropdowns.NOTE_KINDS.set("blush", "Blush Note (Fresh)");
		//ChartEditorDropdowns.NOTE_KINDS.set("fuckup", "FuckUp Note (Wow!)");
		Constants.DEFAULT_SONG = "cocoa";

		var oldSpr = null;
		Countdown.showCountdownGraphic = function(index:CountdownStep, isPixelStyle:Bool)
		{
			var spritePath:String = null;

			if (isPixelStyle)
			{
				switch (index)
				{
					case CountdownStep.TWO:
						spritePath = 'weeb/pixelUI/ready-pixel';
					case CountdownStep.ONE:
						spritePath = 'weeb/pixelUI/set-pixel';
					case CountdownStep.GO:
						spritePath = 'weeb/pixelUI/date-pixel';
					default:
						// null
				}
			}
			else
			{
				spritePath = "ui/countdown/COUNTDOWN";
			}

			if (spritePath == null)
				return;

			var countdownSprite:FunkinSprite;
			if (index != CountdownStep.AFTER)
			{
				countdownSprite = isPixelStyle ? FunkinSprite.create(spritePath) : FunkinSprite.createSparrow(0, 0, spritePath);
				countdownSprite.zoomFactor = 0.25;
				countdownSprite.scrollFactor.set();
				countdownSprite.antialiasing = !isPixelStyle;
			}
			if (isPixelStyle)
			{
				if (countdownSprite != null)
				{
					countdownSprite.setGraphicSize(Std.int(countdownSprite.width * Constants.PIXEL_ART_SCALE));
					countdownSprite.updateHitbox();
					countdownSprite.screenCenter();
					// Fade sprite in, then out, then destroy it.
					FlxTween.tween(countdownSprite, {y: (countdownSprite.y -= 15) + 30, alpha: 0}, Conductor.instance.beatLengthMs / 1000, {
						ease: FlxEase.cubeInOut,
						onComplete: function(twn:FlxTween)
						{
							countdownSprite.destroy();
							PlayState.instance.remove(countdownSprite, true);
						}
					});
				}
			}
			else
			{
				if (oldSpr != null && index != CountdownStep.AFTER)
				{
					oldSpr.destroy();
					PlayState.instance.remove(countdownSprite, true);
				}
				if (countdownSprite != null)
					oldSpr = countdownSprite;
				switch (index)
				{
					case CountdownStep.THREE:
						countdownSprite.animation.addByPrefix("count", "count3", 24, false);
					case CountdownStep.TWO:
						countdownSprite.animation.addByPrefix("count", "count2", 24, false);
					case CountdownStep.ONE:
						countdownSprite.animation.addByPrefix("count", "count1", 24, false);
					case CountdownStep.GO:
						countdownSprite.animation.addByPrefix("count", "countgo", 24, false);
					case CountdownStep.AFTER:
						FlxTween.tween(oldSpr, {alpha: 0, angle: FlxG.random.sign() * 30}, Conductor.instance.beatLengthMs / 2000, {
							ease: FlxEase.backIn,
							onComplete: _ ->
							{
								oldSpr.destroy();
								PlayState.instance.remove(oldSpr, true);
								oldSpr = null;
							}
						});
						FlxTween.tween(oldSpr.scale, {x: 0, y: 0}, Conductor.instance.beatLengthMs / 1800, {
							ease: FlxEase.backIn
						});
					default:
						// null
				}
				if (countdownSprite != null)
				{
					countdownSprite.animation.play("count");
					countdownSprite.scale.set(.75, .75);
					countdownSprite.screenCenter();
					countdownSprite.x += 0;
					countdownSprite.centerOffsets();
					countdownSprite.centerOrigin();
					if (index == CountdownStep.THREE || index == CountdownStep.ONE)
						countdownSprite.x += 30;
					if (PlayState.instance.currentStage != null
						&& StringTools.startsWith(PlayState.instance.currentStage.id, "xMasCityMallAmTake"))
					{
						countdownSprite.x -= 280;
					}
				}
			}
			if (countdownSprite != null)
				PlayState.instance.add(countdownSprite);
		}
	}

	var DEATH_THRESHOLD:Float = 0.125 * 2;
	var LOSING_THRESHOLD:Float = 0.25 * 2;
	var WINING_THRESHOLD:Float = 0.8 * 2;

	function makeAmTakeIcon(ic:HealthIcon):HealthIcon
	{
		var icon = ic;
		icon.updateHealthIcon = (health:Float) ->
		{
			switch (icon.getCurrentAnimation())
			{
				case "idle":
					if (health < LOSING_THRESHOLD) icon.playAnimation("losing"); else if (health < DEATH_THRESHOLD) icon.playAnimation("death"); else
						icon.playAnimation("idle");

				case "losing":
					if (health < DEATH_THRESHOLD) icon.playAnimation("death"); else if (health > LOSING_THRESHOLD) icon.playAnimation("idle"); else
						icon.playAnimation("losing");

				case "death":
					if (health > DEATH_THRESHOLD && health < LOSING_THRESHOLD) icon.playAnimation("losing"); else if (health > LOSING_THRESHOLD)
						icon.playAnimation("idle"); else icon.playAnimation("death");

				default:
					icon.playAnimation("idle", null, false);
			}
		}
		icon.animation.add("idle", [0], 0, false, false);
		icon.animation.add("losing", [1], 0, false, false);
		icon.animation.add("death", [2], 0, false, false);
		icon.animation.remove("winning");
	}

	function makeAmTakeAnimatedIcon(ic:HealthIcon, ?isPlayer:Bool = null, ?customOffsets:Array<Float> = null):HealthIcon
	{
		var icon = ic;

		if (isPlayer == null)
			isPlayer = (icon.playerId == 0);

		icon.updateHealthIcon = (health:Float) ->
		{
			switch (icon.getCurrentAnimation())
			{
				case "winning":
					health < WINING_THRESHOLD ? icon.playAnimation("fromWinning", "idle") : icon.playAnimation("winning", "idle");

				case "idle":
					if (health > WINING_THRESHOLD) icon.playAnimation("toWinning"); // icon.playAnimation("winning");
					else if (health < LOSING_THRESHOLD) icon.playAnimation("toLosing"); else icon.playAnimation("idle");

				case "losing":
					if (health < DEATH_THRESHOLD) icon.playAnimation("toDeath"); else if (health > LOSING_THRESHOLD) icon.playAnimation("fromLosing"); else
						icon.playAnimation("losing");

				case "death":
					if (health > DEATH_THRESHOLD && health < LOSING_THRESHOLD) icon.playAnimation("fromDeath"); else if (health > LOSING_THRESHOLD)
						icon.playAnimation("idle"); else icon.playAnimation("death");

				/////////////////////////////////
				case "toWinning":
					// icon.frameOffset.y = 7.55;
					if (icon.isAnimationFinished()) icon.playAnimation("winning", "idle");
				case "fromWinning":
					// icon.frameOffset.y = 7.55;
					if (icon.isAnimationFinished()) icon.playAnimation("idle");

				case "toLosing":
					// icon.frameOffset.y = 6.0;
					if (icon.isAnimationFinished()) icon.playAnimation("losing", "idle");
				case "fromLosing":
					// icon.frameOffset.y = 7.0;
					if (icon.isAnimationFinished()) icon.playAnimation("idle");

				case "toDeath":
					// icon.frameOffset.y = 7.0;
					if (icon.isAnimationFinished()) icon.playAnimation("death", "idle");
				case "fromDeath":
					// icon.frameOffset.y = 8.55;
					if (icon.isAnimationFinished()) icon.playAnimation("losing");

				/////////////////////////////////
				default:
					icon.playAnimation("idle", null, false);
			}
		}
		icon.animation.addByPrefix("winning", "win0", 1, true);
		icon.animation.addByPrefix("idle", "basic0", 1, true);
		icon.animation.addByPrefix("losing", "lose0", 1, true);
		icon.animation.addByPrefix("death", "predeath0", 1, true);

		icon.animation.addByPrefix("toWinning", "basic-to-win0", 24, false);
		icon.animation.addByPrefix("fromWinning", "win-to-basic0", 24, false);
		icon.animation.addByPrefix("toLosing", "basic-to-lose0", 24, false);
		icon.animation.addByPrefix("fromLosing", "lose-to-basic0", 24, false);
		icon.animation.addByPrefix("toDeath", "lose-to-predeath0", 24, false);
		icon.animation.addByPrefix("fromDeath", "predeath-to-lose0", 24, false);

		icon.flipX = isPlayer;

		icon.animOffsets = customOffsets ?? ["default" => [0, 0]];
		return icon;
	}
}
