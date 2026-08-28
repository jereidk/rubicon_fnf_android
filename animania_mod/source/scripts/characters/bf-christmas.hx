import funkin.play.character.MultiAnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.play.GameOverSubState;
import funkin.graphics.adobeanimate.FlxAtlasSprite;
import flixel.FlxCameraFollowStyle;
import funkin.util.Constants;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;
import funkin.Conductor;
import flixel.util.FlxTimerManager;

class BoyfriendChristmasCharacter extends MultiAnimateAtlasCharacter
{
	function new()
	{
		super('bf-christmas');
	}

	function onCreate(event:ScriptEvent)
	{
		super.onCreate(event);

		GameOverSubState.musicSuffix = '-xmas';
		GameOverSubState.blueBallSuffix = '-xmas';
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		// if (event.note.kind == "solotime" || event.note.noAnimation ||) return;

		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind))
			return;

		if (event.note.noteData.getMustHitNote() && characterType == CharacterType.BF && !event.eventCanceled)
		{
			// Override the hit note animation.
			if (event.note.holdNoteSprite != null)
				lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			switch (event.note.kind)
			{
				case "mom":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt');
					return;

				case "cheer":
					holdTimer = 0;
					playAnimation("hey", true, false);
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, "");
					return;
			}
		}
		// super.onNoteHit(event);
	}

	function onNoteMiss(event)
	{
		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind))
			return;

		if (event.note.noteData.getMustHitNote() && characterType == CharacterType.BF && !event.eventCanceled)
		{
			switch (event.note.kind)
			{
				case "mom":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), true, 'alt');
					return;

				case "fresh":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), true, 'both');
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), true, "");
					return;
			}
		}

		super.onNoteMiss(event);
	}

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon, isOpponent]);
	}

	function playAnimation(name:String, restart:Bool, ignoreOther:Bool)
	{
		if (!debug)
		{
			if (name == "firstDeath")
			{
				shader = null;
			}
			else if (name == "deathLoop")
			{
				Conductor.instance.forceBPM(100);
			}
			else if (name == "deathConfirm")
			{
				GameOverSubState.instance.targetCameraZoom *= 1.15;
				FlxTween.tween(FlxG.camera, {zoom: GameOverSubState.instance.targetCameraZoom}, 2, {ease: FlxEase.backOut});
				GameOverSubState.instance.cameraFollowPoint.x += 225;
				GameOverSubState.instance.cameraFollowPoint.y -= 75;
			}
		}
		super.playAnimation(name, restart, ignoreOther);
	}
}
