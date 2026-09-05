import flixel.addons.display.FlxBackdrop;
import flixel.util.FlxAxes;
import openfl.display.BlendMode;
import sys.FileSystem;

var backingSprite:FlxBackdrop;
var introStrings:Array<String> = [null, 'three', 'two', 'one', 'go'];
var backingSpriteTween:FlxTween = null;
var startCutscene:Bool = false;
var inCutscene:Bool = false;

function create()
{
	startCutscene = PlayState.isStoryMode && !PlayState.seenCutscene;
	if (!Assets.exists(Paths.file('songs/${PlayState.SONG.meta.name}/dialogue.json')))
	{
		startCutscene = false;
	}

	PlayState.seenCutscene = true;

	canReset = false;
	countdownType = 'default';

	if (PlayState.SONG.meta.name == 'meguca')
		countdownType = 'meguca';

	switch (countdownType)
	{
		case 'default':
			graphicCache.cache(Paths.image("game/countdown/countdownbacking"));
			for (i in introStrings)
			{
				if (i == null)
					continue;
				graphicCache.cache(Paths.image("game/countdown/" + i));
				FlxG.sound.load(Paths.sound("countdown/" + i));
			}
		case 'meguca':
			FlxG.sound.load(Paths.sound("countdown/countdown-yotsuba"));

			yotsubaCountdown = new FunkinSprite();
			yotsubaCountdown.loadSprite(Paths.image("game/countdown/yotsuba"));
			yotsubaCountdown.addAnim('start', 'Symbol0', 24, false, false);
			yotsubaCountdown.scale.set(1.55, 1.55);
			yotsubaCountdown.updateHitbox();
			add(yotsubaCountdown);
			yotsubaCountdown.screenCenter(FlxAxes.X);
			yotsubaCountdown.playAnim('start', true);
			yotsubaCountdown.animation.finishCallback = () ->
			{
				yotsubaCountdown.visible = false;
			};
	}
}

function postCreate()
{
	switch (countdownType)
	{
		case 'default':
			var color:FlxColor = FlxColor.WHITE;
			if (dad == null)
				color = bf.iconColor;
			else
				color = dad.iconColor;

			backingSprite = new FlxBackdrop(Paths.image("game/countdown/countdownbacking"), FlxAxes.X, 0, 0);
			backingSprite.color = color;
			backingSprite.alpha = 0.0;
			add(backingSprite);
			backingSprite.blend = BlendMode.ADD;
			backingSprite.velocity.set(50, 0);
			backingSprite.cameras = [camUI];
			backingSprite.screenCenter();
			backingSprite.scale.y = 0.0;
		case 'meguca':
			yotsubaCountdown.cameras = [camHUD];
			remove(yotsubaCountdown);
			insert(9, yotsubaCountdown);

			FlxG.sound.play(Paths.sound("countdown/countdown-yotsuba"), 0.75 * Options.volumeSFX);
	}
}

function onStartCountdown(e)
{
	e.cancel();

	if (e == null)
		return;

	var introLengthMulti:Float = 1.25;
	switch (countdownType)
	{
		case 'default':
			introLengthMulti = 1.25;
		case 'meguca':
			introLengthMulti = 1.5;
	}

	if (!startCutscene)
	{
		inCutscene = false;
		startedCountdown = true;
		Conductor.songPosition = 0;
		Conductor.songPosition -= Conductor.crochet * (introLength * introLengthMulti) - Conductor.songOffset;

		if (introLength > 0)
		{
			var swagCounter:Int = 0;
			startTimer = new FlxTimer().start(Conductor.crochet / 1000, (tmr:FlxTimer) ->
			{
				countdown(swagCounter++);
			}, introLength);
		}
	}
	else
	{
		inCutscene = true;
		persistentUpdate = false;
		paused = true;
		dialogueSubState = new ModSubState("HQDialogue");
		openSubState(dialogueSubState);
	}
}

function onCountdown(e)
{
	e.cancel();

	switch (countdownType)
	{
		case 'default':
			if (e.swagCounter == 0)
			{
				backingSpriteTween = FlxTween.tween(backingSprite, {'scale.y': 1.0, alpha: 0.5}, Conductor.crochet / 500, {
					ease: FlxEase.expoOut
				});
			}

			if (e == null || introStrings[e.swagCounter] == null)
				return;

			var sprite = new FunkinSprite(0, 0);
			sprite.loadSprite(Paths.image("game/countdown/" + introStrings[e.swagCounter]));
			sprite.scrollFactor.set();
			sprite.scale.set(e.scale + (e.swagCounter * 0.15), e.scale + (e.swagCounter * 0.15));
			sprite.updateHitbox();
			sprite.screenCenter();
			sprite.antialiasing = e.antialiasing;
			insert(members.indexOf(backingSprite) + 1, sprite);
			add(sprite);
			sprite.cameras = [camUI];

			tween = FlxTween.tween(sprite, {'scale.x': sprite.scale.x + 0.25, 'scale.y': sprite.scale.y + 0.25, angle: FlxG.random.int(-5, 5)},
				Conductor.crochet / 1250, {
					ease: FlxEase.bounceOut,
					onComplete: function(twn:FlxTween)
					{
						tween = FlxTween.tween(sprite, {y: sprite.y + 150, alpha: 0.0, angle: FlxG.random.int(-5, 5)}, Conductor.crochet / 1000, {
							ease: FlxEase.quadIn,
							onComplete: function(twn:FlxTween)
							{
								sprite.destroy();
								remove(sprite, true);
							}
						});
					}
				});

			if (backingSpriteTween != null)
				backingSpriteTween.cancel();

			if (e.swagCounter == 4)
			{
				backingSpriteTween = FlxTween.tween(backingSprite, {'scale.y': 0.0, alpha: 0.0}, Conductor.crochet / 500, {
					ease: FlxEase.expoIn,
					onComplete: function(twn:FlxTween)
					{
						camZooming = true;
					}
				});
			}

			FlxG.sound.play(Paths.sound("countdown/" + introStrings[e.swagCounter]), e.volume);
		case 'meguca':
			if (e.swagCounter == 4)
			{
				new FlxTimer().start(1.0, function(tmr:FlxTimer)
				{
					camZooming = true;
				});
			}
	}
}
