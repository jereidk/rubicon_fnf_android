import hxvlc.flixel.FlxVideoSprite;
import openfl.display.BlendMode;

importScript('data/scripts/dropshadow-effect');
var flashbackVideo:FlxVideoSprite;
public var kyubey:Character;
public var kyubeySpeaker:Character;
var bnwShader:CustomShader;
var camFX:FlxCamera;

function create()
{
	startUIvisablityArgs = [true, true, true, true, true, 0, false, 4, "linear", "In"];

	camFX = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camFX.bgColor = 0x00000000;
	FlxG.cameras.remove(camGame, false);
	FlxG.cameras.remove(camHUD, false);
	FlxG.cameras.add(camGame, true);
	FlxG.cameras.add(camFX, false);
	FlxG.cameras.add(camHUD, false);

	// BG Sprites
	ootBG_sky = new FunkinSprite(300, -100);
	ootBG_sky.loadSprite(Paths.image("stages/out-of-time/sky"));
	ootBG_sky.scale.set(2.25, 2.25);
	ootBG_sky.scrollFactor.set(0.1, 0.1);
	insert(members.indexOf(bf), ootBG_sky);

	ootBG_arches = new FunkinSprite(-50, -400);
	ootBG_arches.loadSprite(Paths.image("stages/out-of-time/arches"));
	ootBG_arches.scale.set(1.05, 1.05);
	ootBG_arches.scrollFactor.set(0.3, 0.3);
	insert(members.indexOf(bf), ootBG_arches);

	ootBG_Bbuildings = new FunkinSprite(-250, -550);
	ootBG_Bbuildings.loadSprite(Paths.image("stages/out-of-time/farbuildings"));
	ootBG_Bbuildings.scale.set(1.0, 1.0);
	ootBG_Bbuildings.scrollFactor.set(0.5, 0.5);
	insert(members.indexOf(bf), ootBG_Bbuildings);

	ootBG_buildings = new FunkinSprite(0, -350);
	ootBG_buildings.loadSprite(Paths.image("stages/out-of-time/buildings"));
	ootBG_buildings.scale.set(1.1, 1.1);
	ootBG_buildings.scrollFactor.set(0.7, 0.7);
	insert(members.indexOf(bf), ootBG_buildings);

	ootBG_Lbackground = new FunkinSprite(-600, -600);
	ootBG_Lbackground.loadSprite(Paths.image("stages/out-of-time/leftbg"));
	ootBG_Lbackground.scale.set(1.0, 1.0);
	ootBG_Lbackground.scrollFactor.set(0.8, 0.8);
	insert(members.indexOf(bf), ootBG_Lbackground);

	ootBG_RBuilding = new FunkinSprite(2100, -575);
	ootBG_RBuilding.loadSprite(Paths.image("stages/out-of-time/rightbuilding"));
	ootBG_RBuilding.scale.set(1.0, 1.0);
	ootBG_RBuilding.scrollFactor.set(0.8, 0.8);
	insert(members.indexOf(bf), ootBG_RBuilding);

	ootBG_Below = new FunkinSprite(-500, 0);
	ootBG_Below.loadSprite(Paths.image("stages/out-of-time/below"));
	ootBG_Below.scale.set(1.25, 1.25);
	ootBG_Below.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ootBG_Below);

	if (!Options.lowMemoryMode)
	{
		auroraVideo = new FlxVideoSprite(0, 0);
		auroraVideo.antialiasing = true;
		auroraVideo.bitmap.onFormatSetup.add(function():Void
		{
			if (auroraVideo.bitmap != null && auroraVideo.bitmap.bitmapData != null)
			{
				final scale:Float = Math.min((FlxG.width / auroraVideo.bitmap.bitmapData.width) * 1.75,
					(FlxG.height / auroraVideo.bitmap.bitmapData.height) * 1.75);

				auroraVideo.setGraphicSize(auroraVideo.bitmap.bitmapData.width * scale, auroraVideo.bitmap.bitmapData.height * scale);
				auroraVideo.updateHitbox();
				auroraVideo.screenCenter();
				auroraVideo.x += 150;
				auroraVideo.y -= 1000;
			}
		});
		insert(members.indexOf(bf), auroraVideo);
		auroraVideo.load(Paths.video("aurora-midsong"), ['input-repeat=99999']);
		auroraVideo.alpha = 0.0;
		auroraVideo.blend = BlendMode.ADD;
		auroraVideo.play();
		auroraVideo.pause();

		flashbackVideo = new FlxVideoSprite(0, 0);
		flashbackVideo.antialiasing = true;
		flashbackVideo.bitmap.onFormatSetup.add(function():Void
		{
			if (flashbackVideo.bitmap != null && flashbackVideo.bitmap.bitmapData != null)
			{
				final scale:Float = Math.min(FlxG.width / flashbackVideo.bitmap.bitmapData.width, FlxG.height / flashbackVideo.bitmap.bitmapData.height);

				flashbackVideo.setGraphicSize(flashbackVideo.bitmap.bitmapData.width * (scale * 1.25),
					flashbackVideo.bitmap.bitmapData.height * (scale * 1.25));
				flashbackVideo.updateHitbox();
				flashbackVideo.screenCenter();
				flashbackVideo.x += 150;
				flashbackVideo.y -= 1000;
			}
		});
		insert(members.indexOf(bf), flashbackVideo);
		flashbackVideo.load(Paths.video("flashback-midsong"));
		flashbackVideo.alpha = 0.0;
		flashbackVideo.visible = false;
		flashbackVideo.blend = BlendMode.ADD;
		flashbackVideo.play();
	}

	ootBG_Ground = new FunkinSprite(0, 0);
	ootBG_Ground.loadSprite(Paths.image("stages/out-of-time/ground"));
	ootBG_Ground.scale.set(1.25, 1.25);
	ootBG_Ground.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ootBG_Ground);

	kyubeySpeaker = new FunkinSprite(1200, -130);
	kyubeySpeaker.loadSprite(Paths.image("game/speakerssmall"));
	kyubeySpeaker.addAnim('bop', 'speaker single instance 1', 24, false, false);
	kyubeySpeaker.scale.set(0.9, 0.9);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(715, -490, 'kyubey-small', false);
	kyubey.scale.set(0.95, 0.95);
	kyubey.scrollFactor.set(1.0, 1.0);
	add(kyubey);

	ootBG_FClouds = new FunkinSprite(-50, 40);
	ootBG_FClouds.loadSprite(Paths.image("stages/out-of-time/frontclouds"));
	ootBG_FClouds.scale.set(1.5, 1.5);
	ootBG_FClouds.scrollFactor.set(1.2, 1.2);
	add(ootBG_FClouds);

	// Event
	introGradient = new FunkinSprite(1000, -1000);
	introGradient.loadSprite(Paths.image("stages/out-of-time/introgradient"));
	introGradient.scale.set(9.0, 8.0);
	introGradient.scrollFactor.set(1.0, 1.0);
	introGradient.blend = BlendMode.MULTIPLY;
	introGradient.color = 0xFF2A213D;
	insert(members.indexOf(ootBG_Below), introGradient);

	if (!Options.lowMemoryMode)
	{
		clock_back = new FunkinSprite(0, 0);
		clock_back.loadSprite(Paths.image("stages/out-of-time/clock/c_back"));
		add(clock_back);
		clock_back.screenCenter();
		clock_back.alpha = 0.0;
		clock_back.blend = BlendMode.ADD;
		clock_back.cameras = [camFX];

		clock_base = new FunkinSprite(0, 0);
		clock_base.loadSprite(Paths.image("stages/out-of-time/clock/c_base"));
		add(clock_base);
		clock_base.screenCenter();
		clock_base.cameras = [camFX];

		clock_hourHand = new FunkinSprite(0, 0);
		clock_hourHand.loadSprite(Paths.image("stages/out-of-time/clock/c_hrhand"));
		add(clock_hourHand);
		clock_hourHand.screenCenter();
		clock_hourHand.cameras = [camFX];

		clock_minuteHand = new FunkinSprite(0, 0);
		clock_minuteHand.loadSprite(Paths.image("stages/out-of-time/clock/c_minhand"));
		add(clock_minuteHand);
		clock_minuteHand.screenCenter();
		clock_minuteHand.cameras = [camFX];

		for (spr in [clock_back, clock_base, clock_hourHand, clock_minuteHand])
			spr.visible = false;
	}

	vignette = new FunkinSprite(0, 0);
	vignette.loadSprite(Paths.image("game/overlay"));
	vignette.scale.set(1.5, 1.5);
	vignette.zoomFactor = 0.0;
	vignette.scrollFactor.set(0.0, 0.0);
	add(vignette);
	vignette.alpha = 0.75;
	vignette.color = FlxColor.BLACK;
	vignette.screenCenter();

	ootBG_sky.color = FlxColor.BLACK;
}

function postCreate()
{
	if (Options.gameplayShaders)
	{
		var dropShadow = getDropShadow(boyfriend);
		dropShadow.setAdjustColor(-5, -15, 0, -15);
		dropShadow.color = 0xFF564A6B;
		dropShadow.angle = 145;
		dropShadow.distance = 15;
		dropShadow.curZoom = 1;
		dropShadow.threshold = 0.25;
		dropShadow.antialiasAmt = 4;

		var dropShadow2 = getDropShadow(dad);
		dropShadow2.setAdjustColor(-5, -15, 0, -15);
		dropShadow2.color = 0xFF564A6B;
		dropShadow2.angle = 65;
		dropShadow2.distance = 15;
		dropShadow2.curZoom = 1;
		dropShadow2.threshold = 0.1;
		dropShadow2.antialiasAmt = 4;

		boilShader = new CustomShader('wave');
		boilShader.strength = 0.5;
		boilShader.speed = 1.0;

		ootBG_sky.shader = boilShader;
	}

	if (!Options.lowMemoryMode)
	{
		auroraVideo.play();
		auroraVideo.pause();
		flashbackVideo.play();
		flashbackVideo.pause();
	}

	FlxG.camera.filters ??= [];

	if (Options.gameplayShaders)
		bnwShader = new CustomShader("Grayscale");

	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		bloomShader.amt = -0.05;
	}

	if (Options.gameplayShaders)
	{
		rainShader = new CustomShader("rain");
		FlxG.camera.addShader(rainShader);
		rainShader.iTimescale = 0.25;
	}
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	if (Options.gameplayShaders)
	{
		rainShader.iTime = totalElapsed;
		boilShader.time = totalElapsed;
	}
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		kyubeySpeaker.playAnim('bop', true);
	}
}

function stepHit(curStep:Int)
{
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Flashback":
				if (!Options.lowMemoryMode)
				{
					if (params[1] == 'Start')
					{
						flashbackVideo.visible = true;
						flashbackVideo?.play();
						FlxTween.tween(flashbackVideo, {alpha: 0.3}, 1.5, {ease: FlxEase.quadIn});
					}
					else if (params[1] == 'End')
					{
						FlxTween.tween(flashbackVideo, {alpha: 0.0}, 1.5, {ease: FlxEase.quadIn});
					}
				}
			case "BG Light":
				if (params[1] == 'On')
				{
					if (params[2] == 0 || params[2] == '')
					{
						ootBG_sky.color = FlxColor.WHITE;
						introGradient.alpha = 0.0;
					}
					else
					{
						introGradient.alpha = 1.0;
						FlxTween.tween(introGradient, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
						FlxTween.color(ootBG_sky, Conductor.stepCrochet * (params[2] * 1.25) / 1000, FlxColor.BLACK, FlxColor.WHITE, {ease: FlxEase.quadInOut});
					}
				}
				else if (params[1] == 'Off')
				{
					if (params[2] == 0 || params[2] == '')
					{
						ootBG_sky.color = FlxColor.BLACK;
						introGradient.alpha = 1.0;
					}
					else
					{
						introGradient.alpha = 0.0;
						FlxTween.tween(introGradient, {alpha: 1.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
						FlxTween.color(ootBG_sky, Conductor.stepCrochet * (params[2] * 1.25) / 1000, FlxColor.WHITE, FlxColor.BLACK, {ease: FlxEase.quadInOut});
					}
				}

			case "Aurora":
				if (!Options.lowMemoryMode)
				{
					if (params[1] == "Fade In")
					{
						auroraVideo?.play();
						FlxTween.tween(auroraVideo, {alpha: 1.0}, 1.5, {ease: FlxEase.quadInOut});
					}
					else if (params[1] == "Fade Out")
					{
						FlxTween.tween(auroraVideo, {alpha: 0.0}, 1.5, {ease: FlxEase.quadInOut});
					}
					else if (params[1] == "Instant")
					{
						auroraVideo?.play();
						auroraVideo.alpha = 1.0;
					}
				}

			case "Kyubey Mid-Anim":
				kyubey.danceOnBeat = false;
				kyubey.playAnim('ootmidanim', true);
				kyubey.animation.finishCallback = () ->
				{
					kyubey.visible = false;
				};
			case "Kyubey Layer":
				remove(kyubey);
				insert(members.indexOf(ootBG_Below), kyubey);

			case "Clock":
				if (!Options.lowMemoryMode)
				{
					if (params[1] == "Show")
					{
						clock_hourHand.angle = (Date.now().getHours() * 30 + (Date.now().getMinutes() * 0.5));
						clock_minuteHand.angle = (Date.now().getMinutes() * 6);

						for (spr in [clock_back, clock_base, clock_hourHand, clock_minuteHand])
							spr.visible = true;

						FlxTween.tween(clock_back, {alpha: 1.0}, 0.75, {ease: FlxEase.expoIn, startDelay: 0.5});

						FlxTween.tween(camFX, {zoom: 1.25}, 0.75, {ease: FlxEase.expoIn, startDelay: 0.5});
					}

					if (params[1] == "Tick")
					{
						FlxTween.tween(clock_hourHand, {angle: clock_hourHand.angle + 0.5}, 0.10, {ease: FlxEase.elasticOut});
						FlxTween.tween(clock_minuteHand, {angle: clock_minuteHand.angle + 6}, 0.10, {ease: FlxEase.elasticOut});
					}

					if (params[1] == "Hide")
					{
						for (spr in [clock_back, clock_base, clock_hourHand, clock_minuteHand])
							spr.visible = false;
					}
				}

			case "Rain":
				if (params[1] == "Start")
				{
					if (Options.gameplayShaders)
					{
						FlxTween.num(0.0, 0.015, 3, {
							ease: FlxEase.quadInOut
						}, function(num:Float)
						{
							rainShader.iIntensity = num;
						});
					}
				}
				else if (params[1] == "End")
				{
					if (Options.gameplayShaders)
					{
						FlxTween.num(0.015, 0.0, 3, {
							ease: FlxEase.quadInOut
						}, function(num:Float)
						{
							rainShader.iIntensity = num;
						});
					}
				}
		}
	}
}

function onPlayerHit(e)
{
	e.cancel();

	if (e.noteType == 'Timestop Note')
	{
		if (Options.gameplayShaders)
		{
			for (spr in [
				ootBG_sky,
				ootBG_arches,
				ootBG_Bbuildings,
				ootBG_buildings,
				ootBG_Lbackground,
				ootBG_RBuilding,
				ootBG_Below,
				ootBG_Ground,
				introGradient
			])
			{
				spr.shader = bnwShader;
			}

			if (Options.gameplayShaders)
				auroraVideo.shader = bnwShader;
		}

		if (!Options.lowMemoryMode)
		{
			if (auroraVideo.alpha != 0.0)
				auroraVideo.pause();
		}
	}
}

function clearStatusEffect(statusEffect:String)
{
	switch (statusEffect)
	{
		case 'timeStop':
			if (Options.gameplayShaders)
			{
				for (spr in [
					ootBG_sky,
					ootBG_arches,
					ootBG_Bbuildings,
					ootBG_buildings,
					ootBG_Lbackground,
					ootBG_RBuilding,
					ootBG_Below,
					ootBG_Ground,
					introGradient
				])
				{
					spr.shader = null;
					if (spr == ootBG_sky)
						spr.shader = boilShader;
				}

				if (Options.gameplayShaders)
					auroraVideo.shader = null;
			}

			if (!Options.lowMemoryMode)
			{
				if (auroraVideo.alpha != 0.0)
					auroraVideo.resume();
			}
	}
}

function onGamePause(e)
{
	if (!Options.lowMemoryMode)
	{
		auroraVideo.pause();
		flashbackVideo.pause();
	}
}

function onSubstateClose(e)
{
	if (paused)
	{
		if (!Options.lowMemoryMode)
		{
			if (timeStop_Dura == -1)
				auroraVideo.resume();

			if (flashbackVideo.visible)
				flashbackVideo.resume();
		}
	}
}
