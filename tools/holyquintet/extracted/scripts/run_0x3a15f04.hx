import Effect;
import util.GenUtil;
import funkin.backend.system.Controls;
import openfl.display.BlendMode;

var warningSprite:FunkinSprite;
var currentResult:String = '';
var dodgeResult:String = '';
var canDodge:Bool = false;
var dodgeDirection:Int = 0;
var gfDodgeSound:FlxSound;

FlxG.sound.load(Paths.sound("mechanics/kyoko_warning"));
FlxG.sound.load(Paths.sound("mechanics/kyoko_attack"));
FlxG.sound.load(Paths.sound("mechanics/dodgefeedback_perfect"));
function create()
{
	for (i in 1...24)
		FlxG.sound.load(Paths.sound('gf/gfvo_hit_$i'));

	for (i in 1...10)
		FlxG.sound.load(Paths.sound('gf/gfvo_dodge_l_$i'));
	for (i in 1...12)
		FlxG.sound.load(Paths.sound('gf/gfvo_dodge_d_$i'));
	for (i in 1...8)
		FlxG.sound.load(Paths.sound('gf/gfvo_dodge_u_$i'));
	for (i in 1...17)
		FlxG.sound.load(Paths.sound('gf/gfvo_dodge_r_$i'));

	warningSprite = new FunkinSprite(0, 0);
	warningSprite.loadSprite(Paths.image("game/mechanics/kyoko/warning"));
	warningSprite.scale.set(1.6, 1.6);
	warningSprite.color = FlxColor.YELLOW;
	warningSprite.alpha = 0.0;
	warningSprite.screenCenter();

	gfDodgeSound = new FlxSound();
	gfDodgeSound.volume = 2.25;
	FlxG.sound.list.add(gfDodgeSound);
}

function postCreate()
{
	// warningSprite.cameras = [camUI];
}

function update(elapsed:Float)
{
	if (controls.DODGE && canDodge)
	{
		dodgeResult = currentResult;
		canDodge = false;

		dodgeDirection = FlxG.random.int(0, 3);

		var animToPlay:Array<String> = ['dodgeLEFT', 'dodgeRIGHT', 'dodgeUP', 'dodgeDOWN'];
		bf.playAnim(animToPlay[dodgeDirection], true);

		switch (dodgeDirection)
		{
			case 0:
				gfDodgeSound.loadEmbedded(Paths.sound('gf/gfvo_dodge_l_${FlxG.random.int(1, 10)}'));
			case 1:
				gfDodgeSound.loadEmbedded(Paths.sound('gf/gfvo_dodge_r_${FlxG.random.int(1, 17)}'));
			case 2:
				gfDodgeSound.loadEmbedded(Paths.sound('gf/gfvo_dodge_u_${FlxG.random.int(1, 8)}'));
			case 3:
				gfDodgeSound.loadEmbedded(Paths.sound('gf/gfvo_dodge_d_${FlxG.random.int(1, 12)}'));
		}

		gfDodgeSound.volume = 1.5;
		gfDodgeSound.play();
	}
}

function onEvent(e)
{
	if (e.event.name == "Kyoko Attack"
		&& FlxMath.inBounds(e.event.time / 1000, (Conductor.songPosition / 1000) - 2, (Conductor.songPosition / 1000) + 2))
	{
		if (curMods.contains('NoMechanics') || (!PlayState.isGauntletMode && !Options.mechanics))
			return;

		var params:Array = e.event.params;

		canDodge = true;
		currentResult = 'miss-early';

		var popup = FunkinSprite.copyFrom(warningSprite);
		popup.color = FlxColor.YELLOW;
		add(popup).cameras = [camUI];
		FlxTween.tween(popup, {
			'scale.x': 1.5,
			'scale.y': 1.5,
			alpha: 1.0,
			angle: FlxG.random.int(-5, 5)
		}, Conductor.stepCrochet * 2 / 1000, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				FlxTween.tween(popup, {
					'scale.x': 0.0,
					'scale.y': 0.0,
					alpha: 0.0,
					angle: popup.angle * 15
				}, Conductor.stepCrochet * 4 / 1000, {
					ease: FlxEase.expoIn,
					onComplete: function(twn:FlxTween)
					{
						popup.destroy();
						remove(popup, true);
					}
				});
			}
		});

		FlxG.sound.play(Paths.sound('mechanics/kyoko_warning'), 0.5 * Options.volumeSFX).pitch = 1.0;

		new FlxTimer().start(Conductor.stepCrochet * 4 / 1000, function(tmr:FlxTimer)
		{
			var popup = FunkinSprite.copyFrom(warningSprite);
			popup.color = FlxColor.YELLOW;
			add(popup).cameras = [camUI];
			FlxTween.tween(popup, {
				'scale.x': 1.5,
				'scale.y': 1.5,
				alpha: 1.0,
				angle: FlxG.random.int(-5, 5)
			}, Conductor.stepCrochet * 2 / 1000, {
				ease: FlxEase.expoOut,
				onComplete: function(twn:FlxTween)
				{
					FlxTween.tween(popup, {
						'scale.x': 0.0,
						'scale.y': 0.0,
						alpha: 0.0,
						angle: popup.angle * 15
					}, Conductor.stepCrochet * 4 / 1000, {
						ease: FlxEase.expoIn,
						onComplete: function(twn:FlxTween)
						{
							popup.destroy();
							remove(popup, true);
						}
					});
				}
			});

			FlxG.sound.play(Paths.sound('mechanics/kyoko_warning'), 0.5 * Options.volumeSFX).pitch = 1.05;
			FlxG.sound.play(Paths.sound('mechanics/kyoko_attack'), 0.7 * Options.volumeSFX).pitch = 1.0;
			dad.playAnim('attack', true);
		});

		new FlxTimer().start(Conductor.stepCrochet * 8 / 1000, function(tmr:FlxTimer)
		{
			var popup = FunkinSprite.copyFrom(warningSprite);
			popup.color = FlxColor.RED;
			add(popup).cameras = [camUI];
			FlxTween.tween(popup, {
				'scale.x': 1.5,
				'scale.y': 1.5,
				alpha: 1.0,
				angle: FlxG.random.int(-5, 5)
			}, Conductor.stepCrochet * 2 / 1000, {
				ease: FlxEase.expoOut,
				onComplete: function(twn:FlxTween)
				{
					FlxTween.tween(popup, {
						'scale.x': 0.0,
						'scale.y': 0.0,
						alpha: 0.0,
						angle: popup.angle * 15
					}, Conductor.stepCrochet * 4 / 1000, {
						ease: FlxEase.expoIn,
						onComplete: function(twn:FlxTween)
						{
							popup.destroy();
							remove(popup, true);
						}
					});
				}
			});

			FlxG.sound.play(Paths.sound('mechanics/kyoko_warning'), 0.5 * Options.volumeSFX).pitch = 1.1;
		});

		new FlxTimer().start(Conductor.stepCrochet * 8.5 / 1000, function(tmr:FlxTimer)
		{
			if (!curMods.contains('HarderMechanics'))
				currentResult = 'dodge';
		});

		var dodgeWindowSteps:Float = 11.5;
		if (curMods.contains('HarderMechanics')) dodgeWindowSteps = 11.0;

		new FlxTimer().start(Conductor.stepCrochet * dodgeWindowSteps / 1000, function(tmr:FlxTimer)
		{
			currentResult = 'dodge-perfect';
		});

		new FlxTimer().start(Conductor.stepCrochet * 13 / 1000, function(tmr:FlxTimer)
		{
			executeDodgeResult(dodgeResult, params[0]);
		});
	}
}

function executeDodgeResult(result:String, damage:Float)
{
	if (PlayState.difficulty == "easy")
		damage /= 2;

	canDodge = false;
	if (result == '')
		result = 'miss-late';

	if (playerStrums.cpu)
		result = 'dodge-perfect';

	var judgement = new FunkinSprite(bf.x - 500, bf.y + 150).loadGraphic(Paths.image("game/judgement/dodges"), true, 400, 120);
	judgement.addAnim('miss-early', null, 0, false, false, [0]);
	judgement.addAnim('miss-late', null, 0, false, false, [1]);
	judgement.addAnim('dodge', null, 0, false, false, [2]);
	judgement.addAnim('dodge-perfect', null, 0, false, false, [3]);
	add(judgement);
	judgement.scale.set(1.25, 1.25);
	judgement.x += 500;
	judgement.playAnim(result);
	FlxTween.tween(judgement, {
		'scale.x': 1.0,
		'scale.y': 1.0,
		alpha: 1.0,
		angle: FlxG.random.int(-5, 5)
	}, Conductor.stepCrochet * 4 / 1000, {
		ease: FlxEase.expoOut,
		onComplete: function(twn:FlxTween)
		{
			FlxTween.tween(judgement, {y: judgement.y - 25, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {
				ease: FlxEase.expoIn,
				onComplete: function(twn:FlxTween)
				{
					judgement.destroy();
					remove(judgement, true);
				}
			});
		}
	});

	switch (result)
	{
		case 'miss-early' | 'miss-late':
			gfDodgeSound.stop();

			bf.playAnim('hurt-short', true);
			kyubey.playAnim('sad', true);
			healthChange(-damage / 50);
			if (curMods.contains('HarderMechanics'))
				inflictStatusEffect('reducedRecovery', 50, null);
			else if (PlayState.difficulty != "easy")
				inflictStatusEffect('reducedRecovery', 25, null);
			atksSustained += 1;
			updateScoreTxtPos();

			if (curMods.contains('InstantKillMechanics'))
				killPlayer();

			if (purity > 0.0)
				FlxG.sound.play(Paths.sound('gf/gfvo_hit_${FlxG.random.int(1, 23)}'), 2.0 * Options.volumeSFX);

		case 'dodge' | 'dodge-perfect':
			kyubey.playAnim('hey', true);
			if (result == 'dodge-perfect')
			{
				FlxG.sound.play(Paths.sound('mechanics/dodgefeedback_perfect'), 1.5 * Options.volumeSFX);
				healthChange(0.05);
				songScore += 500;

				insert(members.indexOf(judgement) + 1, GenUtil.glowPulse(judgement, 0.75, 0.5, 1.0));
			}
			else
			{
				insert(members.indexOf(judgement) + 1, GenUtil.glowPulse(judgement, 0.5, 0.25, 0.5));
			}

			var fx:Effect = new Effect(result);
			insert(members.indexOf(bf) + 1, fx);
	}

	currentResult = '';
	dodgeResult = '';
}
