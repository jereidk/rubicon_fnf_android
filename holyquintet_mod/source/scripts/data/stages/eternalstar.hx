import openfl.display.BlendMode;

public var kyubey:Character;
public var kyubeySpeaker:Character;
var vibe:Bool = false;
var vibeLightStopped:Bool = false;
var danceLeft:Bool = false;

function create()
{
	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		bloomShader.amt = 0.0;
	}

	esBG_bg = new FunkinSprite(-300, -800);
	esBG_bg.loadSprite(Paths.image("stages/eternal-star/background"));
	esBG_bg.scale.set(1.4, 1.4);
	esBG_bg.scrollFactor.set(0.5, 0.5);
	insert(members.indexOf(bf), esBG_bg);

	esBG_obj1 = new FunkinSprite(-300, -1000);
	esBG_obj1.loadSprite(Paths.image("stages/eternal-star/objects1"));
	esBG_obj1.scale.set(1.2, 1.2);
	esBG_obj1.scrollFactor.set(0.7, 0.7);
	insert(members.indexOf(bf), esBG_obj1);

	esBG_obj2 = new FunkinSprite(-300, -700);
	esBG_obj2.loadSprite(Paths.image("stages/eternal-star/objects2"));
	esBG_obj2.scale.set(1.2, 1.2);
	esBG_obj2.scrollFactor.set(0.85, 0.85);
	insert(members.indexOf(bf), esBG_obj2);

	esBG_Floor = new FunkinSprite(-800, -500);
	esBG_Floor.loadSprite(Paths.image("stages/eternal-star/floor"));
	esBG_Floor.scale.set(1.1, 1.1);
	esBG_Floor.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), esBG_Floor);

	esBG_Sayaka = new FunkinSprite(-650, -650);
	esBG_Sayaka.loadSprite(Paths.image("stages/eternal-star/sayaka"));
	esBG_Sayaka.addAnim('bop', 'SayakaES', 24, true, false, CoolUtil.parseNumberRange("0..13"));
	esBG_Sayaka.addAnim('bop-vibe', 'SayakaES', 24, true, false, CoolUtil.parseNumberRange("14..26"));
	esBG_Sayaka.scale.set(0.80, 0.80);
	esBG_Sayaka.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), esBG_Sayaka);
	esBG_Sayaka.playAnim('bop', true);

	esBG_Mami = new FunkinSprite(1300, -600);
	esBG_Mami.loadSprite(Paths.image("stages/eternal-star/mami"));
	esBG_Mami.addAnim('bop', 'MamiES', 24, true, false, CoolUtil.parseNumberRange("0..13"));
	esBG_Mami.addAnim('bop-vibe', 'MamiES', 24, true, false, CoolUtil.parseNumberRange("14..27"));
	esBG_Mami.addAnim('bop-vibe-r', 'MamiES', 24, true, false, CoolUtil.parseNumberRange("28..41"));
	esBG_Mami.scale.set(0.80, 0.80);
	esBG_Mami.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), esBG_Mami);
	esBG_Mami.playAnim('bop', true);

	kyubeySpeaker = new FunkinSprite(300, -350);
	kyubeySpeaker.loadSprite(Paths.image("game/speakersmain"));
	kyubeySpeaker.addAnim('bop', 'speaker dancing beat0', 24, false, false);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(375, -920, 'kyubey-big', false);
	kyubey.scrollFactor.set(1.0, 1.0);
	kyubey.scale.set(0.85, 0.85);
	insert(members.indexOf(bf), kyubey);

	esBG_ForeGroundL = new FunkinSprite(-850, -75);
	esBG_ForeGroundL.loadSprite(Paths.image("stages/eternal-star/foreground_l"));
	esBG_ForeGroundL.scale.set(1.5, 1.5);
	esBG_ForeGroundL.scrollFactor.set(1.0, 1.0);
	add(esBG_ForeGroundL);

	esBG_ForeGroundR = new FunkinSprite(1400, -75);
	esBG_ForeGroundR.loadSprite(Paths.image("stages/eternal-star/foreground_r"));
	esBG_ForeGroundR.scale.set(1.5, 1.5);
	esBG_ForeGroundR.scrollFactor.set(1.0, 1.0);
	add(esBG_ForeGroundR);

	esBG_ForeGroundR = new FunkinSprite(1400, -75);
	esBG_ForeGroundR.loadSprite(Paths.image("stages/eternal-star/foreground_r"));
	esBG_ForeGroundR.scale.set(1.5, 1.5);
	esBG_ForeGroundR.scrollFactor.set(1.0, 1.0);
	add(esBG_ForeGroundR);

	// Event
	introGradient = new FunkinSprite(1000, -500);
	introGradient.loadSprite(Paths.image("stages/eternal-star/introgradient"));
	introGradient.scale.set(8.0, 8.0);
	introGradient.scrollFactor.set(1.0, 1.0);
	introGradient.blend = BlendMode.MULTIPLY;
	introGradient.color = 0xFF2A213D;
	insert(members.indexOf(bf), introGradient);

	spotlight = new FunkinSprite(-200, -450);
	spotlight.loadSprite(Paths.image("stages/eternal-star/light"));
	spotlight.scale.set(1.5, 1.5);
	spotlight.scrollFactor.set(1.0, 1.0);
	add(spotlight);
	spotlight.alpha = 0.0;
	spotlight.blend = BlendMode.ADD;

	pillsF = new FunkinSprite(-200, -2200);
	pillsF.loadSprite(Paths.image("stages/eternal-star/pillsfront"));
	pillsF.scale.set(1.75, 1.75);
	pillsF.scrollFactor.set(1.5, 1.5);
	add(pillsF);
	pillsF.visible = false;

	lightBallB = new FunkinSprite(-550, -300);
	lightBallB.loadSprite(Paths.image("stages/eternal-star/lightballback"));
	lightBallB.scale.set(1.25, 1.25);
	lightBallB.scrollFactor.set(1.5, 1.5);
	insert(members.indexOf(esBG_Floor), lightBallB);
	lightBallB.visible = false;

	lightBallF = new FunkinSprite(-550, -700);
	lightBallF.loadSprite(Paths.image("stages/eternal-star/lightballfront"));
	lightBallF.scale.set(1.25, 1.25);
	lightBallF.scrollFactor.set(1.5, 1.5);
	insert(members.indexOf(esBG_Floor), lightBallF);
	lightBallF.visible = false;

	vignette = new FunkinSprite(0, 0);
	vignette.loadSprite(Paths.image("game/overlay"));
	vignette.scale.set(1.5, 1.5);
	vignette.zoomFactor = 0.0;
	vignette.scrollFactor.set(0.0, 0.0);
	add(vignette);
	vignette.alpha = 0.0;
	vignette.cameras = [camHUD];
	vignette.color = 0xFFFF42EC;
	vignette.blend = BlendMode.ADD;
	vignette.screenCenter();

	strumLines.members[1].characters[1].visible = false;
}

function postCreate()
{
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "BG Light":
				if (params[1] == 'On')
				{
					if (params[2] == 0 || params[2] == '')
					{
						introGradient.alpha = 0.0;
					}
					else
					{
						introGradient.alpha = 1.0;
						FlxTween.tween(introGradient, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
					}
					dad.color = FlxColor.WHITE;
					bf.color = FlxColor.WHITE;
				}
				else if (params[1] == 'Off')
				{
					if (params[2] == 0 || params[2] == '')
					{
						introGradient.alpha = 1.0;
					}
					else
					{
						introGradient.alpha = 0.0;
						FlxTween.tween(introGradient, {alpha: 1.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
					}
				}

			case 'Darken Character':
				if (params[2] == 0 || params[2] == null)
					params[2] = 0.0001;

				switch (params[1])
				{
					case 'Madoka':
						FlxTween.color(dad, Conductor.stepCrochet * params[2] / 1000, FlxColor.WHITE, FlxColor.GRAY, {ease: FlxEase.quadInOut});
					case 'Girlfriend':
						FlxTween.color(bf, Conductor.stepCrochet * params[2] / 1000, FlxColor.WHITE, FlxColor.GRAY, {ease: FlxEase.quadInOut});
				}

			case 'Transition Girlfriend':
				{
					strumLines.members[1].characters[0].visible = false;
					strumLines.members[1].characters[1].visible = true;
					strumLines.members[1].characters[1].playAnim('transition', true);
					strumLines.members[1].characters[1].animation.finishCallback = () ->
					{
						strumLines.members[1].characters[1].dance();
					};
				}

			case 'Brighten Character':
				if (params[2] == 0 || params[2] == null)
					params[2] = 0.0001;

				switch (params[1])
				{
					case 'Madoka':
						FlxTween.color(dad, Conductor.stepCrochet * params[2] / 1000, FlxColor.GRAY, FlxColor.WHITE, {ease: FlxEase.quadInOut});
					case 'Girlfriend':
						FlxTween.color(bf, Conductor.stepCrochet * params[2] / 1000, FlxColor.GRAY, FlxColor.WHITE, {ease: FlxEase.quadInOut});
				}

			case "Spotlight":
				if (params[2] == 0 || params[2] == null)
					params[2] = 0.0001;

				switch (params[1])
				{
					case 'Madoka':
						FlxTween.tween(spotlight, {x: -200, alpha: 0.5}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
					case 'Girlfriend':
						FlxTween.tween(spotlight, {x: 930, alpha: 0.5}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
					case 'Hide':
						spotlight.visible = false;
				}

			case 'Pills':
				if (params[2] == 0 || params[2] == null)
					params[2] = 0.0001;

				switch (params[1])
				{
					case 'Appear':
						pillsF.visible = true;
						pillsF.moves = true;
						pillsF.velocity.y = 150;
						pillsF.acceleration.y = 1;

					case 'Fall':
						FlxTween.num(1, 1500, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.expoIn}, function(num:Float)
						{
							pillsF.acceleration.y = num;
						});
				}

			case 'Light Ball':
				if (params[2] == 0 || params[2] == null)
					params[2] = 0.0001;

				switch (params[1])
				{
					case 'Appear':
						lightBallB.visible = true;
						lightBallB.moves = true;
						lightBallB.velocity.y = -200;
						lightBallB.acceleration.y = 2;

						lightBallF.visible = true;
						lightBallF.moves = true;
						lightBallF.velocity.y = -150;
						lightBallF.acceleration.y = 1;

						if (Options.gameplayShaders)
						{
							FlxTween.num(0, -0.1, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadIn}, function(num:Float)
							{
								bloomShader.amt = num;
							});
						}
				}

			case 'Bloom Fade':
				if (params[1] == 0 || params[1] == null)
					params[1] = 0.0001;

				if (Options.gameplayShaders)
				{
					FlxTween.num(bloomShader.amt, 0.0, Conductor.stepCrochet * params[1] / 1000, {ease: FlxEase.quadIn}, function(num:Float)
					{
						bloomShader.amt = num;
					});
				}

			case 'Vibe':
				switch (params[1])
				{
					case 'Start':
						vibe = true;
						esBG_Sayaka.playAnim('bop-vibe', true);
						esBG_Mami.playAnim('bop-vibe', true);

						FlxTween.cancelTweensOf(vignette);
						vignette.alpha = (Options.flashingLights ? 1.0 : 0.5);
						FlxTween.tween(vignette, {alpha: 0.5}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});

					case 'Stop Light':
						vibeLightStopped = true;
						FlxTween.tween(vignette, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});
				}
		}
	}
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		danceLeft = !danceLeft;

		kyubeySpeaker.playAnim('bop', true);
		esBG_Sayaka.playAnim(vibe ? 'bop-vibe' : 'bop', true);
		if (vibe)
		{
			esBG_Mami.playAnim(danceLeft ? 'bop-vibe' : 'bop-vibe-r', true);
		}
		else
			esBG_Mami.playAnim('bop', true);
	}
	if ((curBeat % 4) == 0)
	{
		if (vibe && !vibeLightStopped)
		{
			FlxTween.cancelTweensOf(vignette);
			vignette.alpha = (Options.flashingLights ? 1.0 : 0.5);
			FlxTween.tween(vignette, {alpha: 0.5}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});
		}
	}
}

function onGamePause(e)
{
}

function onSubstateClose(e)
{
	if (paused)
	{
	}
}
