import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;


class DadBeastCharacter extends AnimateAtlasCharacter {
	function new() {
		super('dad-beast');
	}

	function onCreate()
	{
		super.onCreate();
		//idleSuffix = "-alt";
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled) {
			if (event.note.holdNoteSprite != null) lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			switch(event.note.kind) {
				case "mom":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt');
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, "");
					return;
			}
		}
		//super.onNoteHit(event);
	}

	var DEATH_THRESHOLD:Float = 0.2 * 2;
	var LOSING_THRESHOLD:Float = 0.3 * 2;
	var WINING_THRESHOLD:Float = 0.8 * 2;

	function initHealthIcon(isOpponent:Bool)
	{
		final icon = super.initHealthIcon(isOpponent);
		icon.applyStageMatrix = false;
		icon.useRenderTexture = false;
	
		icon.frames = Paths.getAnimateAtlas("icons/beast-dearest", null, getDefaultAtlasSettings());
		icon.animation.addByFrameLabel("winning", "win", 24, true);
		icon.animation.addByFrameLabel("fromWinning", "win-to-basic", 24, false);
		icon.animation.addByFrameLabel("toWinning", "basic-to-win", 24, false);
		icon.animation.addByFrameLabel("idle", "basic", 24, true);
		icon.animation.addByFrameLabel("toLosing", "basic-to-lose", 24, false);
		icon.animation.addByFrameLabel("losing", "lose", 24, true);
		icon.animation.addByFrameLabel("toDeath", "lose-to-predeath", 24, false);

		icon.animation.addByFrameLabel("death", "predeath", 24, true);
		icon.animation.addByFrameLabel("fromDeath", "predeath-to-lose", 24, false);
		icon.animation.addByFrameLabel("fromLosing", "lose-to-basic", 24, false);

		icon.updateHealthIcon = (health:Float) ->
		{
			switch (icon.getCurrentAnimation())
			{
				case "winning":
					icon.bopEvery = 4;
					health < WINING_THRESHOLD ? icon.playAnimation("fromWinning", "idle") : icon.playAnimation("winning", "idle");

				case "idle":
					icon.bopEvery = 4;
					if (health > WINING_THRESHOLD) icon.playAnimation("toWinning"); // icon.playAnimation("winning");
					else if (health < LOSING_THRESHOLD) icon.playAnimation("toLosing"); else icon.playAnimation("idle");

				case "losing":
					icon.bopEvery = 8;
					if (health < DEATH_THRESHOLD) icon.playAnimation("toDeath"); else if (health > LOSING_THRESHOLD) icon.playAnimation("fromLosing"); else
						icon.playAnimation("losing");

				case "death":
					icon.bopEvery = 666;
					icon.offset.x += FlxG.random.float(-2, 2);
					icon.offset.y += FlxG.random.float(-2, 2);
					if (health > DEATH_THRESHOLD && health < LOSING_THRESHOLD) icon.playAnimation("fromDeath"); else if (health > LOSING_THRESHOLD)
						icon.playAnimation("idle"); else icon.playAnimation("death");

				/////////////////////////////////
				case "toWinning":
					icon.bopEvery = 4;
					if (icon.isAnimationFinished()) icon.playAnimation("winning", "idle");
				case "fromWinning":
					icon.bopEvery = 4;
					if (icon.isAnimationFinished()) icon.playAnimation("idle");

				case "toLosing":
					icon.bopEvery = 8;
					if (icon.isAnimationFinished()) icon.playAnimation("losing", "idle");
				case "fromLosing":
					icon.bopEvery = 8;
					if (icon.isAnimationFinished()) icon.playAnimation("idle");

				case "toDeath":
					icon.bopEvery = 8;
					if (icon.isAnimationFinished()) icon.playAnimation("death", "idle");
				case "fromDeath":
					icon.bopEvery = 8;
					if (icon.isAnimationFinished()) icon.playAnimation("losing");

				/////////////////////////////////
				default:
					icon.playAnimation("idle", null, false);
			}
		}

		return icon; //ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon]);
	}

}
