import openfl.display.BlendMode;
import util.GenUtil;

var healthDrain:Float = 0.0;
var sayakaHealSnd:FlxSound;
var healing:Bool = false;
var whiteShader:CustomShader;

graphicCache.cache(Paths.image("game/mechanics/sayaka/fx1"));
graphicCache.cache(Paths.image("game/mechanics/sayaka/fx2"));
graphicCache.cache(Paths.image("game/mechanics/sayaka/plus"));
function create()
{
	sayakaHealSnd = new FlxSound().loadEmbedded(Paths.sound('mechanics/sayaka_healstart'));
	FlxG.sound.list.add(sayakaHealSnd);

	healingCircle = new FunkinSprite(dad.x - 1225, dad.y - 150);
	healingCircle.loadSprite(Paths.image("game/fx/healingcircle"));
	healingCircle.addAnim('idle', 'HEALCIRCLE', 24, true, false);
	healingCircle.scale.set(1.0, 0.20);
	healingCircle.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(dad), healingCircle);
	healingCircle.playAnim('idle');
	healingCircle.blend = BlendMode.ADD;
	healingCircle.alpha = 0.0;

	aura = new FlxSprite(dad.x - 150, dad.y - 50).loadGraphic(Paths.image('game/mechanics/sayaka/aura'));
	aura.scale.set(1.5, 1.5);
	aura.updateHitbox();
	aura.blend = BlendMode.ADD;
	insert(members.indexOf(dad) + 1, aura);
	aura.alpha = 0.0;

	if (!Options.lowMemoryMode)
	{
		new FlxTimer().start(FlxG.random.float(0.2, 0.3), function(tmr:FlxTimer)
		{
			if (healing)
			{
				var spr:FlxSprite = new FlxSprite((dad.x - 100) + FlxG.random.int(0, 500),
					(dad.y + 500) - FlxG.random.int(0, 300)).loadGraphic(Paths.image('game/mechanics/sayaka/fx${FlxG.random.int(1, 2)}'));
				spr.scale.set(1.5, 1.5);
				spr.updateHitbox();
				spr.velocity.y = FlxG.random.int(-50, -10);
				spr.acceleration.y = FlxG.random.int(-75, -100);
				spr.blend = BlendMode.ADD;
				insert(members.indexOf(dad) + 1, spr);

				FlxTween.tween(spr, {alpha: 0}, FlxG.random.float(1.5, 2.0), {
					ease: FlxEase.quadInOut,
					onComplete: function(twn:FlxTween)
					{
						spr.destroy();
						remove(spr, true);
					}
				});
			}
		}, 0);

		new FlxTimer().start(FlxG.random.float(0.5, 0.75), function(tmr:FlxTimer)
		{
			if (healing)
			{
				var spr:FlxSprite = new FlxSprite(iconP2.x + FlxG.random.int(25, 125),
					iconP2.y + FlxG.random.int(25, 100)).loadGraphic(Paths.image('game/mechanics/sayaka/plus'));
				spr.scale.set(0.75, 0.75);
				spr.updateHitbox();
				spr.alpha = 0.75;
				spr.velocity.y = FlxG.random.int(-25, -35);
				spr.acceleration.y = FlxG.random.int(-25, -35);
				spr.blend = BlendMode.ADD;
				insert(members.indexOf(soulgem_sanityOverlay) - 1, spr);
				spr.cameras = [camUI];

				FlxTween.tween(spr, {alpha: 0}, FlxG.random.float(1.0, 1.5), {
					ease: FlxEase.quadInOut,
					onComplete: function(twn:FlxTween)
					{
						spr.destroy();
						remove(spr, true);
					}
				});
			}
		}, 0);
	}
}

function postCreate()
{
	whiteShader = new CustomShader("WhiteOverlay");
	whiteShader.strength = 0.0;
	iconP2.shader = whiteShader;
}

function update(elapsed:Float)
{
	if (health >= 0.05)
		health -= healthDrain * elapsed;
}

function onEvent(e)
{
	if (e.event.name == "Sayaka Heal")
	{
		if (curMods.contains('NoMechanics') || (!PlayState.isGauntletMode && !Options.mechanics))
			return;

		var params:Array = e.event.params;

		if (params[0])
		{
			FlxG.sound.play('mechanics/sayaka_healstart');

			sayakaHealSnd?.play();

			executeEvent({name: "Play Animation", time: 0, params: [0, "healstart", true, "NONE"]});
			dad.altSuffix = '-alt';
			new FlxTimer().start(0.03 * 30, function(tmr:FlxTimer)
			{
				healing = true;
				healthDrain = params[1];
				if (PlayState.difficulty == "easy")
					healthDrain /= 2.5;
				iconP2.setIcon('sayaka-heal');

				whiteShader.strength = 1.0;
				FlxTween.num(1.0, 0.0, 0.75, {ease: FlxEase.quadOut}, function(num:Float)
				{
					whiteShader.strength = num;
				});
			});

			new FlxTimer().start(0.03 * 30, function(tmr:FlxTimer)
			{
				FlxTween.completeTweensOf(healingCircle);
				FlxTween.completeTweensOf(aura);
				FlxTween.tween(healingCircle, {alpha: 1.0}, 0.25, {ease: FlxEase.expoOut});
				FlxTween.tween(aura, {alpha: 0.75}, 0.25, {ease: FlxEase.expoOut});
			});
		}
		else
		{
			healing = false;
			executeEvent({name: "Play Animation", time: 0, params: [0, "healend", true, "NONE"]});
			dad.altSuffix = '';
			healthDrain = 0.0;
			iconP2.setIcon('sayaka');

			whiteShader.strength = 1.0;
			FlxTween.num(1.0, 0.0, 0.75, {ease: FlxEase.quadOut}, function(num:Float)
			{
				whiteShader.strength = num;
			});

			FlxTween.completeTweensOf(healingCircle);
			FlxTween.completeTweensOf(aura);
			FlxTween.tween(healingCircle, {alpha: 0.0}, 0.25, {ease: FlxEase.expoOut});
			FlxTween.tween(aura, {alpha: 0.0}, 0.25, {ease: FlxEase.expoOut});
		}
	}
}
