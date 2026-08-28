import funkin.play.character.MultiSparrowCharacter;
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
import funkin.Conductor;

import flixel.util.FlxGradient;

class TadanoStandCharacter extends MultiSparrowCharacter
{
	function new()
	{
		super('tadano-stand');
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
					this.playSingAnimation(event.note.noteData.getDirection(), true, idleSuffix.indexOf("alt") != -1 ? "alt" : "");
					return;
			}
		}

		super.onNoteMiss(event);
	}

	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		final offs = ["idle" => [0, 0], "toLosing" => [0, 5], "losing" => [0, -5]];
		return ModuleHandler.getModule("AnimaniaStuff").scriptCall("makeAmTakeAnimatedIcon", [icon, isOpponent, offs]);
	}

	///////////////////////////////////// DEATH
	var coolDeathSprite:FlxAtlasSprite;
	var coolRetrySprite:FlxAtlasSprite;
	var deathTimerManager:FlxTimerManager;

	function playAnimation(name:String, restart:Bool, ignoreOther:Bool, reverse:Bool)
	{
		if (name == "firstDeath")
		{
			createDeathSprites();
		}
		else if (name == "deathConfirm")
		{
			deathTimerManager.completeAll();
			coolRetrySprite.anim.onFinish.removeAll();
			coolRetrySprite.anims.play("confirm", true, false);

			FlxTween.tween(GameOverSubState.instance.cameraFollowPoint, {y: GameOverSubState.instance.cameraFollowPoint.y - 350}, 3.5, {startDelay: .2, ease:FlxEase.elasticInOut});

			FlxTween.cancelTweensOf(leftBLACK, ["x"]); FlxTween.cancelTweensOf(rightBLACK, ["x"]);
			FlxTween.tween(leftBLACK, {x: -300}, 3.5, {ease:FlxEase.backInOut});
			FlxTween.tween(rightBLACK, {x: FlxG.width-100}, 3.5, {ease:FlxEase.backInOut});

			var coolBlackyGradient:FunkinSprite = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height * 2.25, [FlxColor.BLACK, FlxColor.BLACK, FlxColor.TRANSPERENT]);
			coolBlackyGradient.screenCenter(FlxAxes.X);
			coolBlackyGradient.scrollFactor.set();
			coolBlackyGradient.y = -(FlxG.height * 2);
			FlxTween.tween(coolBlackyGradient, {y: 0}, 3.5, {ease:FlxEase.backIn});
			GameOverSubState.instance.add(coolBlackyGradient);

			return;
		}

		if (name == "deathLoop")
			return;

		super.playAnimation(name, restart, ignoreOther, reverse);
		if (name == "endAnimation")
			this.danceEvery = 99999;
	}

	var leftBLACK;
	var rightBLACK;
	function createDeathSprites()
	{
		//this.visible = false;
		deathTimerManager = new FlxTimerManager();
		GameOverSubState.instance.add(deathTimerManager);
		FlxG.camera.filters = PlayState.instance.camHUD.filters;
		GameOverSubState.instance.targetCameraZoom *= FlxG.camera.zoom / 0.65;

		PlayState.instance.persistentDraw = true;
		var darkBg = GameOverSubState.instance.darkBg;
		darkBg.alpha = 0;

		leftBLACK = new FunkinSprite().makeSolidColor(400, FlxG.height, FlxColor.BLACK);
		leftBLACK.zoomFactor = 0;
		leftBLACK.scrollFactor.set();
		leftBLACK.shouldDraw = true;
		leftBLACK.screenCenter(0x10);
		leftBLACK.x = -400;
		FlxTween.tween(leftBLACK, {x: -100}, 6, {ease:FlxEase.sineInOut});
		GameOverSubState.instance.add(leftBLACK);

		rightBLACK = new FunkinSprite().makeSolidColor(400, FlxG.height, FlxColor.BLACK);
		rightBLACK.zoomFactor = 0;
		rightBLACK.scrollFactor.set();
		rightBLACK.shouldDraw = true;
		rightBLACK.screenCenter(0x10);
		rightBLACK.x = FlxG.width;
		FlxTween.tween(rightBLACK, {x: FlxG.width-300}, 6, {ease:FlxEase.sineInOut});
		GameOverSubState.instance.add(rightBLACK);

		GameOverSubState.instance.remove(GameOverSubState.instance.boyfriend);
		GameOverSubState.instance.add(GameOverSubState.instance.boyfriend);

		var komi = PlayState.instance.currentStage.getDad();
		GameOverSubState.instance.add(komi);
		komi.danceEvery = 9999;
		komi.playAnimation("gameOver", true, true, false);
		komi.isDead = true;

		var goUP = Preferences.downscroll;
		for (obj in [
			PlayState.instance.healthBar,
			PlayState.instance.iconP1,
			PlayState.instance.iconP2 /*, PlayState.instance.playerStrumline*/]
		)
			FlxTween.tween(obj, {y: obj.y - 250 * (goUP ? 1 : -1), alpha: 0}, 1.75, {ease: FlxEase.smootherStepIn, startDelay: 0});

		for (obj in [PlayState.instance.playerStrumline, PlayState.instance.opponentStrumline])
			FlxTween.tween(obj, {y: obj.y + 250 * (goUP ? 1 : -1), alpha: 0}, 1.75, {ease: FlxEase.smootherStepIn, startDelay: .15});

		FlxTween.tween(darkBg, {alpha: 0.75}, 1.25, {ease: FlxEase.backOut, startDelay: .5});

		coolRetrySprite = new FlxAtlasSprite(this.x + this.offset.x + 240, this.y + this.offset.y,
			Paths.animateAtlas("characters/phonecall/tadano-phone-stand-death-text", "shared"), {uniqueInCache: true, filterQuality: 0});
		coolRetrySprite.anim.addByFrameLabel("start", "start", 24, false);
		coolRetrySprite.anim.addByFrameLabel("loop", "loop", 24, false);
		coolRetrySprite.anim.addByFrameLabel("confirm", "confirm", 24, false);
		coolRetrySprite.anim.onFinish.addOnce((n) -> if (n == "start") coolRetrySprite.anims.play("loop", true));
		coolRetrySprite.applyStageMatrix = true;
		coolRetrySprite.alpha = 0.00001;
		new FlxTimer(deathTimerManager).start(.25, () -> {
			coolRetrySprite.alpha = 1;
			coolRetrySprite.anims.play("start", true);
			GameOverSubState.instance.startDeathMusic(0, false);
			Conductor.instance.forceBPM(112);
			GameOverSubState.instance.gameOverMusic.fadeIn(12, 0, 1);
		});

		GameOverSubState.instance.add(coolRetrySprite);
	}
	public override function onBeatHit(event):Void
	{
		final gameOver = GameOverSubState.instance;
		if (gameOver != null && event.beat % 2 == 0)
		{
			FlxG.camera.zoom += 0.0075;
			if (PlayState.instance.isPlayerDying && coolRetrySprite != null && coolRetrySprite.anim.curAnimName == "loop")
				coolRetrySprite.anims.play("loop", true);
		}

	}

}
