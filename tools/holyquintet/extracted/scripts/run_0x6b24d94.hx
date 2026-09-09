import flixel.addons.effects.FlxTrail;
import openfl.display.BlendMode;
import util.GenUtil;

using StringTools;

public var bulletNoteMissed:Bool = false;
var damage:Int = 0.10;
var afterFramePlayer:Character;
var afterFramePlayerTween:FlxTween;
var afterFrameOpponent:Character;
var afterFrameOpponentTween:FlxTween;
var shootTimestopShader:CustomShader;
var shootTimestopShaderTween:FlxTween;
var shootSnd:FlxSound;

graphicCache.cache(Paths.image("game/mechanics/homura/bullet-shot"));
graphicCache.cache(Paths.image("game/mechanics/homura/bullet-hit"));
FlxG.sound.load(Paths.sound("mechanics/homura_shoot"));
function create()
{
	if (!Options.lowMemoryMode)
	{
		afterFramePlayer = new Character(bf.x, bf.y, 'gf-base', true);
		insert(members.indexOf(bf), afterFramePlayer);
		afterFramePlayer.alpha = 0.0;
		afterFramePlayer.blend = BlendMode.ADD;
		afterFramePlayer.color = 0xFFECA6FF;
		afterFramePlayer.useRenderTexture = true;

		if (dad != null)
		{
			afterFrameOpponent = new Character(dad.x, dad.y, 'homura-base', false);
			insert(members.indexOf(dad), afterFrameOpponent);
			afterFrameOpponent.alpha = 0.0;
			afterFrameOpponent.blend = BlendMode.ADD;
			afterFrameOpponent.color = 0xFFECA6FF;
			afterFrameOpponent.useRenderTexture = true;
		}

		if (Options.gameplayShaders)
		{
			shootTimestopShader = new CustomShader("Timestop");
			shootTimestopShader.scale = 0.2;
			afterFrameOpponent.shader = shootTimestopShader;
		}
	}

	shootSnd = new FlxSound().loadEmbedded(Paths.sound('mechanics/homura_shoot'));
	shootSnd.volume = 0.5 * Options.volumeSFX;
	FlxG.sound.list.add(shootSnd);
}

function onNoteCreation(e)
{
	if (e.noteType == 'Bullet Note')
	{
		if (Options.downscroll)
			e.noteSprite = "game/mechanics/homura/bullet-ds"; // i hate this hudcamera class
		else
			e.noteSprite = "game/mechanics/homura/bullet";
	}
}

function onPostNoteCreation(e)
{
	if (e.noteType == 'Bullet Note')
	{
		if (Options.downscroll)
			e.note.offset.set(22 + (36 * (1.0 - Options.playerStrumScale)), 28);
		else
			e.note.offset.set(22 + (36 * (1.0 - Options.playerStrumScale)), 63);
	}
}

function onPlayerHit(e)
{
	if (e.noteType == 'Bullet Note')
	{
		e.cancel();

		var dodgeAnimation:Array<String> = ['dodgeLEFT', 'dodgeDOWN', 'dodgeUP', 'dodgeRIGHT'];

		if (e.character.animation.curAnim.name.contains('sing'))
			usePlayerAfterImage = true;
		else
			usePlayerAfterImage = false;

		if (usePlayerAfterImage && !Options.lowMemoryMode)
		{
			if (afterFramePlayerTween != null)
				afterFramePlayerTween?.cancel();

			afterFramePlayer.playAnim(dodgeAnimation[e.direction], true);
			afterFramePlayer.alpha = 1.0;
			afterFramePlayerTween = FlxTween.tween(afterFramePlayer, {alpha: 0.0}, 0.5, {ease: FlxEase.quadIn, startDelay: 0.25});
		}
		else
		{
			if (!Options.lowMemoryMode)
			{
				e.character.playAnim(dodgeAnimation[e.direction]);
			}
			else if (!e.character.animation.curAnim.name.contains('sing'))
			{
				e.character.playAnim(dodgeAnimation[e.direction]);
			}
		}

		if (!Options.lowMemoryMode)
		{
			var bulletShell = new FunkinSprite(0,0).loadGraphic(Paths.image("game/mechanics/homura/bullet-shot"));
			add(bulletShell);
			bulletShell.cameras = [camUI];
			bulletShell.moves = true;
			GenUtil.alignToCenter(bulletShell, playerStrums.members[e.direction]);

			if (Options.downscroll)
				bulletShell.y = 875;

			bulletShell.angularVelocity = -500;
			bulletShell.angularDrag = 350;
			bulletShell.velocity.set((FlxG.random.bool(50) ? -250 : 250), -550);
			bulletShell.acceleration.set(0, 1500);
			FlxTween.tween(bulletShell, {alpha: 0.0}, 0.5, {
				ease: FlxEase.quadIn,
				startDelay: 0.75,
				onComplete: function(twn:FlxTween)
				{
					bulletShell.destroy();
					remove(bulletShell, true);
				}
			});

			var bulletShield = new FunkinSprite(0, 0).loadGraphic(Paths.image("game/mechanics/homura/bullet-hit"));
			add(bulletShield);
			bulletShield.cameras = [camHUD];
			bulletShield.alpha = 0.75;

			GenUtil.alignToCenter(bulletShield, playerStrums.members[e.direction]);

			if (Options.downscroll)
				bulletShield.y -= 25;

			bulletShield.angle = (FlxG.random.bool(50) ? -5 : 5);
			bulletShield.scale.set(1.1, 1.1);
			FlxTween.tween(bulletShield, {'scale.x': 0.9, 'scale.y': 0.9, angle: 0}, 0.25, {ease: FlxEase.expoOut});

			FlxTween.tween(bulletShield, {alpha: 0.0}, 0.25, {
				ease: FlxEase.quadIn,
				startDelay: 0.1,
				onComplete: function(twn:FlxTween)
				{
					bulletShield.destroy();
					remove(bulletShield, true);
				}
			});
		}

		shootAnim();
	}

	if (e.noteType == 'Timestop Note' && !Options.lowMemoryMode)
	{
		if (afterFramePlayerTween != null)
			afterFramePlayerTween?.cancel();
		afterFramePlayer.alpha = 0.0;
	}
}

function onPlayerMiss(e)
{
	if (e.noteType == 'Bullet Note')
	{
		e.cancel();

		bf.playAnim('hurt-shot', true);
		shootAnim();

		healthChange(-damage);
		inflictStatusEffect('bleed', 5, e);

		e.note.strumLine.deleteNote(e.note);

		if (curMods.contains('InstantKillMechanics'))
			killPlayer();

		bulletNoteMissed = true;
	}
}

function shootAnim()
{
	shootSnd.pitch = FlxG.random.float(0.8, 1.2);
	shootSnd.play(true);

	if (dad != null)
	{
		if (dad.animation.curAnim.name.contains('sing') || dad.animation.curAnim.name.contains('shoot'))
			useOpponentAfterImage = true;
		else
			useOpponentAfterImage = false;

		if (useOpponentAfterImage && !Options.lowMemoryMode)
		{
			if (afterFrameOpponentTween != null)
				afterFrameOpponentTween?.cancel();

			afterFrameOpponent.playAnim('shoot', true);
			afterFrameOpponent.alpha = 1.0;
			afterFrameOpponentTween = FlxTween.tween(afterFrameOpponent, {alpha: 0.0}, 0.5, {ease: FlxEase.quadIn, startDelay: 0.25});

			if (Options.gameplayShaders)
			{
				if (shootTimestopShaderTween != null)
					shootTimestopShaderTween?.cancel();
				shootTimestopShaderTween = FlxTween.num(1.25, 0.25, 0.5, {
					ease: FlxEase.expoOut
				}, function(num:Float)
				{
					shootTimestopShader.scale = num;
				});
			}
		}
		else
		{
			if (!Options.lowMemoryMode)
			{
				dad.playAnim('shoot');
			}
			else if (!dad.animation.curAnim.name.contains('sing'))
			{
				dad.playAnim('shoot');
			}
		}
	}
}

override function destroy()
{
	shootSnd?.destroy();
	FlxG.sound.list.remove(shootSnd);
}
