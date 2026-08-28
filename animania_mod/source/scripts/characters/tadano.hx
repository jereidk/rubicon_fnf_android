import funkin.play.character.MultiAnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import flixel.util.FlxTimer;
import funkin.graphics.FunkinSprite;
import funkin.audio.FunkinSound;
import funkin.Paths;
import flixel.FlxSprite;
import flixel.FlxG;
import funkin.modding.base.ScriptedFunkinSprite;
import flixel.group.FlxTypedSpriteGroup;
import flixel.effects.FlxFlicker;
import funkin.play.PauseSubState;
import funkin.modding.module.ModuleHandler;
import flixel.tweens.FlxTween;
// import grafex.util.ThreaderUtil;
import funkin.play.GameOverSubState;
import funkin.graphics.adobeanimate.FlxAtlasSprite;
import flixel.util.FlxTimerManager;
import flixel.FlxCameraFollowStyle;
import funkin.util.Constants;

class TadanoCharacter extends MultiAnimateAtlasCharacter
{
	function new()
	{
		super('tadano');
	}

	function onCreate(event:ScriptEvent)
	{
		super.onCreate(event);

		GameOverSubState.musicSuffix = '-tadano';
		GameOverSubState.blueBallSuffix = '-tadano';

		PauseSubState.musicSuffix = '-phonecall';
	}

	function onNoteHit(event:HitNoteScriptEvent)
	{
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

				case "fresh":
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, 'both');
					return;

				default:
					holdTimer = 0;
					this.playSingAnimation(event.note.noteData.getDirection(), false, idleSuffix.indexOf("alt") != -1 ? "alt" : "");
					return;
			}
		}

		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled)
			super.onNoteHit(event);
	}

	function onNoteMiss(event)
	{
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
					this.playSingAnimation(event.note.noteData.getDirection(), true, idleSuffix.indexOf("alt") != -1 ? "alt" : "");
					return;
			}
		}

		super.onNoteMiss(event);
	}

	override function onNoteGhostMiss(event:GhostMissNoteScriptEvent)
	{
		super.onNoteGhostMiss(event);

		if (characterType == CharacterType.BF && !event.eventCanceled)
		{
			this.playSingAnimation(event.dir, true, idleSuffix.indexOf("alt") != -1 ? "alt" : "");
		}
	}

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		final offs = ["idle" => [0, 0], "toLosing" => [0, 15], "losing" => [0, -5]];
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon, !isOpponent, offs]);
	}

	override function onAnimationFinished(prefix:String):Void
	{
		switch (prefix)
		{
			case "intro":
				trace(prefix);
				super.onAnimationFinished(prefix);
				dance(true);

			default:
				super.onAnimationFinished(prefix);
		}
	}

	function playAnimation(name:String, restart:Bool, ignoreOther:Bool, reverse:Bool)
	{
		if (name == "firstDeath")
		{
			setupDeath();
		}
		else if (name == "deathLoop" && !debug)
		{
			FlxTween.tween(GameOverSubState.instance.cameraFollowPoint, {x: GameOverSubState.instance.cameraFollowPoint.x - 450}, 3.5, {ease: FlxEase.sineOut});
			coolRetrySprite.alpha = 1;
			coolRetrySprite.anim.play("start", true);
		}
		else if (name == "deathConfirm" && !debug)
		{
			coolRetrySprite.anim.play("confirm", true);
			FlxTween.cancelTweensOf(GameOverSubState.instance.cameraFollowPoint);
			FlxTween.tween(GameOverSubState.instance.cameraFollowPoint, {y: GameOverSubState.instance.cameraFollowPoint.y - 350}, 3.5,
				{startDelay: .8, ease: FlxEase.backInOut});
			return;
		}

		super.playAnimation(name, restart, ignoreOther, reverse);
	}

	var coolRetrySprite:FunkinSprite;

	function setupDeath()
	{
		if (debug)
			return;

		PlayState.instance.persistentDraw = true;
		var darkBg = GameOverSubState.instance.darkBg;
		darkBg.alpha = .9;
		FlxTween.tween(darkBg, {alpha: 0.5}, 1, {ease: FlxEase.backOut});

		var goUP = Preferences.downscroll;
		for (obj in [
			PlayState.instance.healthBar,
			PlayState.instance.iconP1,
			PlayState.instance.iconP2
		])
			FlxTween.tween(obj, {y: obj.y - 250 * (goUP ? 1 : -1), alpha: 0}, 1.75, {ease: FlxEase.smootherStepIn, startDelay: .25});

		for (obj in [PlayState.instance.playerStrumline, PlayState.instance.opponentStrumline])
			FlxTween.tween(obj, {y: obj.y + 250 * (goUP ? 1 : -1), alpha: 0}, 1.75, {ease: FlxEase.smootherStepIn, startDelay: .5});

		FlxTween.tween(darkBg, {alpha: 0.75}, 1.25, {ease: FlxEase.backOut, startDelay: 1});

		coolRetrySprite = new FunkinSprite(this.x - 850, this.y + 450, Paths.animateAtlas("characters/phonecall/tadano-phone-death-text", "shared"));
		coolRetrySprite.anim.addByFrameLabel("start", "start", 24, false);
		coolRetrySprite.anim.addByFrameLabel("loop", "loop", 24, true);
		coolRetrySprite.anim.addByFrameLabel("confirm", "confirm", 24, false);
		coolRetrySprite.anim.onFinish.addOnce((n) -> if (n == "start") coolRetrySprite.anims.play("loop", true));
		GameOverSubState.instance.add(coolRetrySprite);
		coolRetrySprite.alpha = 0.0001;
	}
}
