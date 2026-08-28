import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;

class ParentsChristmasCharacter extends AnimateAtlasCharacter
{
	function new()
	{
		super('parents-christmas');
	}

	function onCreate()
	{
		super.onCreate();
		// idleSuffix = "-angry";
		//shader = HSVBlendedShader.xmasInit();
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
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt' + idleSuffix);
					return;

				case "both":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'both' + idleSuffix);
					return;

				case "parents-miss":
					event.cancel();
					event.note.noAnimation = true;
					idleSuffix = "-angry";
					shouldAlternate = false;
					return;
				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, idleSuffix.indexOf("angry") != -1 ? "angry" : "");
					return;
			}
		}
		// super.onNoteHit(event);
	}

	function onNoteMiss(e)
	{
		if (!e.note.noteData.getMustHitNote() && characterType == CharacterType.DAD)
			return;

		super.onNoteMiss(e);
	}

	public override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reversed:Bool = false):Void
	{
		var doBasic:Bool = false;
		switch (name)
		{
			case "skibidi":
				idleSuffix = "";
				shouldAlternate = true;
				danceEvery = 1;
			case "cocoaSoloLookLeft":
				canPlayOtherAnims = true;
				doBasic = true;
			case "cocoaSoloLookRight":
				doBasic = true;
				canPlayOtherAnims = true;
			default:
				super.playAnimation(name, restart, ignoreOther, reversed);
		}

		//trace(canPlayOtherAnims, name);
		if (doBasic)
			super.playAnimation(name, restart, ignoreOther, reversed);
	}

	override function onAnimationFinished(prefix:String):Void
	{
		trace(prefix);
		switch (prefix)
		{
			case "cocoaSolo" | "cocoaSoloLeft":
				trace("я сосу большие яйца <3");

			case "cocoaSoloLookLeft":
				trace("я сосу большие яйца <3 2");
				canPlayOtherAnims = true;
				playAnimation("cocoaSoloLeft", true, true);

			case "cocoaSoloLookRight":
				// trace("я сосу яйца по больше<3");
				canPlayOtherAnims = true;
				playAnimation("cocoaSolo", true, true);
				/*new FlxTimer().start(4, () ->
				{
					// idleSuffix = "";
					canPlayOtherAnims = true;
					// trace("ОТСОСИ ХУЙ БЛЯТЬ AAAA");
				});*/

			case "singRIGHTmiss":
				//idleSuffix = "-angry";
				//danceEvery = 2;
				//shouldAlternate = false;
				super.onAnimationFinished(prefix);

			default:
				super.onAnimationFinished(prefix);
		}
	}

	function initHealthIcon(isOpponent:Bool)
	{
		final icon = super.initHealthIcon(isOpponent);
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon]);
	}

}
