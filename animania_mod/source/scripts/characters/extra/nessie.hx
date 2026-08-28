import funkin.play.character.MultiAnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;

class NessieCharacter extends MultiAnimateAtlasCharacter
{
	function new()
	{
		super('extra/manager/nessie');
	}


	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled)
		{
			// Override the hit note animation.
			if (event.note.holdNoteSprite != null)
				lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			switch (event.note.kind)
			{
				case "mom":
					if (event.note.direction != 1)
					{
						holdTimer = 0;
						this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt');
					}
					else
					{
						playAnimation("getit", true, true);
					}
					return;


				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, '');
					return;
			}
		}
		// super.onNoteHit(event);
	}

	function onBeatHit(e)
	{
		super.onBeatHit(e);
		if (e.beat == 116)
		{
			danceEvery = 0;
			playAnimation("theend", true, true);
		}
	}
		
}
