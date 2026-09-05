import funkin.backend.scripting.events.sprite.PlayAnimEvent;
import openfl.display.BlendMode;
import util.GenUtil;

public var timeStopNoteHit:Bool = false;
var timeStopLength:Float = 1.5;
var timeStopDuration:Float = 0.0;
public var frozenPlayer:Character;
var timestopShaderTween:FlxTween;

function create()
{
	frozenPlayer = new Character(bf.x, bf.y, 'gf-base', true);
	insert(members.indexOf(bf), frozenPlayer);
	frozenPlayer.visible = false;

	if (Options.gameplayShaders)
	{
		bnwShader = new CustomShader("Grayscale");
		frozenPlayer.shader = bnwShader;
		bnwShader.grayness = 1.0;

		timestopShader = new CustomShader("Timestop");
		timestopShader.scale = 0.0;
	}
}

function postCreate()
{
	if (Options.gameplayShaders)
		FlxG.camera.addShader(timestopShader);
	// strumLines.members[1].characters.push(frozenPlayer);
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	if (Options.gameplayShaders)
		timestopShader.iTime = totalElapsed;

	totalElapsed += elapsed;
}

function onNoteCreation(e)
{
	if (e.noteType == 'Timestop Note')
	{
		e.note.avoid = true;
		e.noteSprite = "game/mechanics/homura/timestop";
	}
}

function onPostNoteCreation(e)
{
	if (e.noteType == 'Timestop Note')
	{
		if (Options.downscroll)
			e.note.offset.set(51 + (100 * (1.0 - Options.playerStrumScale)), 0);
		else
			e.note.offset.set(51 + (100 * (1.0 - Options.playerStrumScale)), 0);
	}
}

function onPlayerHit(e)
{
	if (e.noteType == 'Timestop Note')
	{
		e.cancel();

		frozenPlayer.playAnim(frozenPlayer.getSingAnim(e.direction, '') + e.animSuffix + 'miss', PlayAnimEvent.MISS, e.forceAnim, 1);
		frozenPlayer.danceOnBeat = false;
		frozenPlayer.animation.pause();
		frozenPlayer.visible = true;

		playerIgnoreNoteAnims = true;
		disablePlayerInput = true;
		bf.visible = false;

		if (dad.curCharacter == 'homura-base')
			dad.playAnim('timestop', true);

		if (kyubey != null)
		{
			if (Options.gameplayShaders)
			{
				bnwShader = new CustomShader("Grayscale");
				kyubey.shader = bnwShader;
				kyubeySpeaker.shader = bnwShader;
			}
			kyubey.danceOnBeat = false;
			kyubey.animation.pause();
			kyubeySpeaker.animation.pause();
		}

		if (Options.gameplayShaders)
		{
			if (timestopShaderTween != null)
				timestopShaderTween?.cancel();

			timestopShaderTween = FlxTween.num(0.75, 0.05, 0.5, {
				ease: FlxEase.quadOut
			}, function(num:Float)
			{
				timestopShader.scale = num;
			});
		}

		e.note.strumLine.vocals.volume = 0;
		playerStrums.vocals.volume = 0;

		inflictStatusEffect('timeStop', 1.0, e);

		timeStopNoteHit = true;

		if (!Options.lowMemoryMode)
		{
			var shieldSpin = new FunkinSprite(0, 0).loadGraphic(Paths.image("game/mechanics/homura/timestop-hit"));
			add(shieldSpin);
			shieldSpin.cameras = [camHUD];
			shieldSpin.alpha = 1.0;
			shieldSpin.blend = BlendMode.ADD;
			GenUtil.alignToCenter(shieldSpin, playerStrums.members[e.direction]);

			FlxTween.tween(shieldSpin, {angle: 90}, 0.25, {ease: FlxEase.backOut});

			FlxTween.tween(shieldSpin, {'scale.x': 1.5, 'scale.y': 1.5, alpha: 0.0}, 0.5, {
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween)
				{
					shieldSpin.destroy();
					remove(shieldSpin, true);
				}
			});
		}
	}
}

function onPlayerMiss(e)
{
	if (e.noteType == 'Timestop Note')
	{
		e.cancel();
		e.note.strumLine.deleteNote(e.note);
	}
}

function clearStatusEffect(statusEffect:String)
{
	switch (statusEffect)
	{
		case 'timeStop':
			playerIgnoreNoteAnims = false;
			disablePlayerInput = false;
			bf.visible = true;
			frozenPlayer.visible = false;

			if (Options.gameplayShaders)
				kyubey.shader = null;
			kyubey.danceOnBeat = true;

			if (Options.gameplayShaders)
				kyubeySpeaker.shader = null;
			kyubeySpeaker.animation.resume();

			if (Options.gameplayShaders)
			{
				if (timestopShaderTween != null)
					timestopShaderTween?.cancel();
				timestopShaderTween = FlxTween.num(0.15, 0.00, 0.15, {
					ease: FlxEase.quadIn
				}, function(num:Float)
				{
					timestopShader.scale = num;
				});
			}
	}
}
