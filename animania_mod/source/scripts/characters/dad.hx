import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;

class DadCharacter extends AnimateAtlasCharacter
{
	function new()
	{
		super('dad');
	}

	function onCreate()
	{
		super.onCreate();
	}

	public override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reversed:Bool = false):Void
	{
		switch (name)
		{
			case "angy":
				idleSuffix = "-angry";

			case "imok":
				idleSuffix = "";

			default:
				super.playAnimation(name, restart, ignoreOther, reversed);
		}
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind))
			return;

		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled)
		{
			if (event.note.holdNoteSprite != null)
				lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			switch (event.note.kind)
			{
				case "mom":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt');
					return;

				case "beatbox":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'beatbox');
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, idleSuffix.indexOf("angry") != -1 ? "angry" : "");
					return;
			}
		}
		// super.onNoteHit(event);
	}

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon]);
	}
}
