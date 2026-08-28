import funkin.play.character.MultiAnimateAtlasCharacter;
import funkin.play.character.ScriptedMultiAnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;
import flixel.util.FlxTimerManager;
import funkin.play.GameOverSubState;
import funkin.FunkinMemory;

class BoyfriendCharacter extends MultiAnimateAtlasCharacter
{
	function new()
	{
		super('bf');
	}

	function onCreate(e)
	{
		super.onCreate(e);
		ignoreExclusionPref.push("singDOWN");
		//idleSuffix = "-angry";
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (event?.note?.kind == "stop bope")
		{
			canPlayOtherAnims = true;
			playAnimation("singDOWN", true, true);
			return;
		}

		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind))
			return;

		if (event.note.noteData.getMustHitNote() && characterType == CharacterType.BF && !event.eventCanceled)
		{
			if (event.note.holdNoteSprite != null)
				lastHoldFinish = event.note.strumTime + event.note.noteData.length;

			holdTimer = 0;
			switch (event.note.kind)
			{
				case "beatbox":
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'beatbox');
				case "blush":
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'blush');
				case "mom":
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt' + (idleSuffix.indexOf("angry") != -1 ? "-angry" : ""));
				case "fresh":
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'fresh');
				case "cheer":
					playAnimation("hey", true, false);
				case "cheer-alt":
					playAnimation("cheer-alt", true, false);
				case "erect-up":
					playAnimation("erect up", true, false);
				default:
					this.playSingAnimation(event.note.noteData.getDirection(), false, idleSuffix.indexOf("angry") != -1 ? "angry" : "");
			}
		}
	}

	function onNoteMiss(event)
	{
		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind))
			return;

		if (event.note.noteData.getMustHitNote() && characterType == CharacterType.BF && !event.eventCanceled)
		{
			lastHoldFinish = null;
			holdTimer = 0;
			switch (event.note.kind)
			{
				case "mom":
					this.playSingAnimation(event.note.noteData.getDirection(), true, 'alt');
				case "fresh":
					this.playSingAnimation(event.note.noteData.getDirection(), true, 'fresh');
				default:
					this.playSingAnimation(event.note.noteData.getDirection(), true, "");
			}
		}
	}

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon, isOpponent]);
	}

	var coolDeathSprite:FunkinSprite;
	var deathTimerManager:FlxTimerManager;

	override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reverse:Bool = false):Void
	{
		if (name == "erect up")
		{
			holdTimer = -5;
		}

		if (name == "cheer-alt")
		{
			holdTimer = -12;
		}
		super.playAnimation(name, restart, ignoreOther, reverse);
	}

	override function onAnimationFinished(prefix:String):Void
	{
		switch (prefix)
		{
			case "cheer-alt":
			default:
				super.onAnimationFinished(prefix);
		}

	}
}
