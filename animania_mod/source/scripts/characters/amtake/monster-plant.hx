import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;

import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;

class MonsterPlantCharacter extends AnimateAtlasCharacter {
	function new() {
		super('monster-plant');
	}

	// function onCreate()
	// {
	// 	super.onCreate();
	// 	//idleSuffix = "-angry";
	// }

	function onAdd(e)
	{
		super.onAdd(e);
		shouldAlternate = false;
		playAnimation("idle", true);
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (event.note.noteData.kind == "noAnimation" || event.note.noAnimation || event.note.noteData.kind == "noanim")
			return;

		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled) {
			// Override the hit note animation.
			if (event.note.holdNoteSprite != null) lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			switch(event.note.kind) {
				case "mom":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'alt');
					return;

				case "cheer":
					holdTimer = 0;
					playAnimation("laugh", true, false);
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, "");
					return;
			}
		}
		//super.onNoteHit(event);
	}

	function onNoteMiss(e)
	{
		if (!e.note.noteData.getMustHitNote() && characterType == CharacterType.DAD) return;

		super.onNoteMiss(e);
	}

	public override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reversed:Bool = false):Void
	{
		switch (name)
		{
			case "switch":
				shouldAlternate = !shouldAlternate;

			default:
				super.playAnimation(name, restart, ignoreOther, reversed);
		}
	}

	override function onAnimationFinished(prefix:String):Void
	{
		// trace(prefix);
		switch(prefix)
		{
			case "onBfSolo" | "onBfSoloLeft":

			case "momLookLeft":
				playAnimation("onBfSoloLeft", true, true);

			case "momLookRight":
				// trace("я сосу яйца по больше<3");
				playAnimation("onBfSolo", true, true);
				new FlxTimer().start(4, () -> {
					//idleSuffix = "";
					canPlayOtherAnims = true;
					// trace("ОТСОСИ ХУЙ БЛЯТЬ AAAA");
				});

			case "singRIGHTmiss":
				idleSuffix = "-angry";
				super.onAnimationFinished(prefix);

			default:
				super.onAnimationFinished(prefix);
		}
	}

	function initHealthIcon(isOpponent:Bool)
	{
		final icon = super.initHealthIcon(isOpponent);

		icon.frames = Paths.getSparrowAtlas("icons/extra/monster-boss");
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon]);
	}
}
