import funkin.play.character.MultiSparrowCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.play.GameOverSubState;
import funkin.graphics.adobeanimate.FlxAtlasSprite;
import flixel.util.FlxTimer;
import funkin.graphics.FunkinSprite;
import funkin.audio.FunkinSound;
import funkin.Paths;
import funkin.Conductor;
import flixel.FlxSprite;
import flixel.FlxG;
import funkin.modding.base.ScriptedFunkinSprite;
import flixel.group.FlxTypedSpriteGroup;
import flixel.effects.FlxFlicker;
import funkin.play.PauseSubState;
import funkin.modding.module.ModuleHandler;
import flixel.tweens.FlxTween;
import funkin.play.components.HealthIcon;


class KomiCharacter extends MultiSparrowCharacter {
	function new() {
		super('komi');
	}
	var myIcon:HealthIcon;
	var iconIsAlive:Bool = true;
	var iconTimer:Float = 0;

	function onUpdate(event)
	{
		if (!isDead && iconIsAlive && myIcon != null)
		{
			if (iconTimer < 4)
			{
				iconTimer += event.elapsed * 6;
				if (iconTimer > 4)
				{
					iconTimer = 4;
					//myIcon.playAnimation(iconAnimPostfix != "" ? "losing" : "idle", null, false);
				}
			}
		}
		super.onUpdate(event);
	}

	function loopCurrentAnim() {
		if ((this.characterType != 0 || isHoldingNote()) && this.animation.curAnim.curFrame >= _data.loopHoldFrame && lastNoteAnimation != null && (lastHoldFinish != null && lastHoldFinish >= Conductor.instance.songPosition))
		{
			//this.playAnimation(lastNoteAnimation + iconAnimPostfix, true);
			if (iconIsAlive)
			{
				iconTimer = holdTimer = 0;
				myIcon.playAnimation(lastNoteAnimation + iconAnimPostfix, null, true);
			}
		}
		super.loopCurrentAnim();
	}
	var LOSING_THRESHOLD:Float = 0.25 * 2;
	var iconAnimPostfix:String = "";
	function initHealthIcon(isOpponent:Bool)
	{
		var icon = super.initHealthIcon(isOpponent);
		icon.flipX = true;
		icon.updateHealthIcon = (h:Float) -> {
			final health = h;

			iconAnimPostfix = (health < LOSING_THRESHOLD) ? "-alt" : "";

			if (iconTimer >= 4)
			{
				//trace(iconTimer);
				switch (icon.getCurrentAnimation())
				{
					case "idle":
						if (health < LOSING_THRESHOLD)
							icon.playAnimation("toLosing");

					case "losing":
						if (health > LOSING_THRESHOLD)
							icon.playAnimation("fromLosing");


					case "toLosing":
						if (icon.isAnimationFinished())
							icon.playAnimation("losing", "idle");
					case "fromLosing":
						if (icon.isAnimationFinished())
							icon.playAnimation("idle");

					default:
						icon.playAnimation(iconAnimPostfix != "" ? "losing" : "idle", null, false);
				}
			}
			
		}
		icon.animation.addByPrefix("losing", "lose0", 1, true);
		icon.animation.addByPrefix("idle", "basic0", 1, true);

		icon.animation.addByPrefix("toLosing", "basic-to-lose", 24, false);
		icon.animation.addByPrefix("fromLosing", "lose-to-basic", 24, false);

		icon.animation.addByPrefix("singLEFT", "right", 24, false);
		icon.animation.addByPrefix("singRIGHT", "left", 24, false);
		icon.animation.addByPrefix("singUP", "up", 24, false);
		icon.animation.addByPrefix("singDOWN", "down", 24, false);

		icon.animation.addByPrefix("singLEFT-alt", "alt right", 24, false);
		icon.animation.addByPrefix("singRIGHT-alt", "alt left", 24, false);
		icon.animation.addByPrefix("singUP-alt", "alt up", 24, false);
		icon.animation.addByPrefix("singDOWN-alt", "alt down", 24, false);
		icon.playAnimation("idle", null, true);

		icon.animOffsets = [
			"singUP" => [0, 5],
			"singUP-alt" => [0, 5],
			
			"toLosing" => [6, 1],			

			"singLEFT" => [-5, 0],
			"singLEFT-alt" => [-5, 0],
		];
		return myIcon = icon;
		//заготовинг для иконки
	}
	/*
	function onNoteHit(event:HitNoteScriptEvent)
	{
		super.onNoteHit(event);
		if (!event.note.noteData.getMustHitNote() && characterType == CharacterType.DAD && !event.eventCanceled) {
			//заготовинг для иконки
			//trace("Make icons sing note");
		}
	}
	*/
	public function playSingAnimation(dir:NoteDirection, miss:Bool = false, ?suffix:String = '')
	{
		super.playSingAnimation(dir, miss, suffix);

		if (iconIsAlive)
		{
			iconTimer = 0;
			if (myIcon != null)
				myIcon.playAnimation(lastNoteAnimation + iconAnimPostfix, null, true);
		}
	}


	function onBeatHit(event)
	{
		super.onBeatHit(event);
		if (PlayState.instance == null) retutn;

		if (event.beat == 168) //no skips
		{
			iconIsAlive = false;
			//myIcon.updateHealthIcon(100 - PlayState.instance.health);
		}
	}
}
