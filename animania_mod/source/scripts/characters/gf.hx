import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;
import funkin.play.CountdownStep;

using StringTools;

class GirlfriendCharacter extends AnimateAtlasCharacter
{
	function new()
	{
		super('gf');
	}

	var awesomeAnims = ["fresh solo"];

	function onCreate()
	{
		super.onCreate();
	}

	public override function playAnimation(name:String, restart:Bool = false, ignoreOther:Bool = false, reversed:Bool = false):Void
	{
		switch (name)
		{
			case "pre-dance":
				//canPlayOtherAnims = true;

			case "end-dance":
				//canPlayOtherAnims = true;

			case "stop drop dance":
				idleSuffix = "";
				return;
				// case "imok":
				//	idleSuffix = "";

				//	default:
				//		super.playAnimation(name, restart, ignoreOther, reversed);
		}
		super.playAnimation(name, restart, ignoreOther, reversed);
	}

	override function onAnimationFinished(prefix:String):Void
	{
		switch (prefix)
		{
			case "pre-dance":
				hasDanced = false;
				canPlayOtherAnims = true;
				idleSuffix = "-dance";

			case "end-dance":
				hasDanced = false;
				canPlayOtherAnims = true;
				idleSuffix = "";
				dance(true);
				return;

			case "fresh solo":
				hasDanced = false;
				idleSuffix = "-drop";
			default:
		}
		super.onAnimationFinished(prefix);
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
		if (AnimaniaModule.BANNED_NOTEKINDS.contains(event.note.kind) || event.eventCancele)
			return;

		if ((!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD)
			|| (event.note.noteData.getMustHitNote() && characterType == CharacterType.BF)
			|| (event.note.kind != null && event.note.kind.contains('gf') && characterType == CharacterType.GF))
		{
			if (event.note.holdNoteSprite != null)
				lastHoldFinish = event.note.strumTime + event.note.noteData.length;
			holdTimer = 0;
			this.playSingAnimation(event.note.noteData.getDirection(), false, "");
		}
		else if (characterType == CharacterType.GF && event.note.noteData.getMustHitNote())
		{
			switch (event.judgement)
			{
				case 'sick':
					playComboAnimation(event.comboCount);
				case 'good':
					playComboAnimation(event.comboCount);
				default:
					playComboDropAnimation(event.comboCount);
			}
		}
	}

	function playComboAnimation(comboCount:Int):Void
	{
		if (awesomeAnims.contains(getCurrentAnimation()))
			return;

		super.playComboAnimation(comboCount);
	}

	function playComboDropAnimation(comboCount:Int):Void
	{
		if (awesomeAnims.contains(getCurrentAnimation()))
			return;

		super.playComboDropAnimation(comboCount);
	}

	function initHealthIcon(isOpponent:Bool)
	{
		// var icon = super.initHealthIcon(isOpponent);
		// return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon]);
	}

	function onCountdownStep(e)
	{
		super.onCountdownStep(e);
		switch (e.step)
		{
			case CountdownStep.THREE:
				playAnimation("count three", true, false, false);
			case CountdownStep.TWO:
				playAnimation("count two", true, false, false);
			case CountdownStep.ONE:
				playAnimation("count one", true, false, false);
			case CountdownStep.GO:
				playAnimation("cheer", true, false, false);
		}
	}
}
