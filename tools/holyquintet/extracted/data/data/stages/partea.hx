import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.addons.display.FlxBackdrop;

public var kyubey:Character;
public var kyubeySpeaker:Character;
var sayakaPartea:Character;
var nagisaBopTween:FlxTween;
var nagisaYOffset:Float = 0;

function create()
{
	startUIvisablityArgs = [true, true, true, true, true, 0, false, 4, "linear", "In"];

	ptBG_bgcity = new FunkinSprite(-270, -550);
	ptBG_bgcity.loadSprite(Paths.image("stages/partea/city"));
	ptBG_bgcity.scale.set(1.0, 1.0);
	ptBG_bgcity.scrollFactor.set(0.7, 0.7);
	insert(members.indexOf(bf), ptBG_bgcity);

	ptBG_bg = new FunkinSprite(-300, -800);
	ptBG_bg.loadSprite(Paths.image("stages/partea/inside"));
	ptBG_bg.scale.set(1.1, 1.1);
	ptBG_bg.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_bg);

	ptBG_object = new FunkinSprite(-150, -700);
	ptBG_object.loadSprite(Paths.image("stages/partea/int_object"));
	ptBG_object.scale.set(0.9, 0.9);
	ptBG_object.scrollFactor.set(0.9, 0.9);
	insert(members.indexOf(bf), ptBG_object);

	ptBG_couch = new FunkinSprite(-350, -350);
	ptBG_couch.loadSprite(Paths.image("stages/partea/couch"));
	ptBG_couch.scale.set(1.1, 1.1);
	ptBG_couch.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_couch);

	ptBG_madoka = new FunkinSprite(550, -540);
	ptBG_madoka.loadSprite(Paths.image("stages/partea/madoka"));
	ptBG_madoka.addAnim('bop', 'madoka_mami_vibe instance 1', 24, true, false);
	ptBG_madoka.scale.set(0.9, 0.9);
	ptBG_madoka.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_madoka);
	ptBG_madoka.playAnim('bop');

	ptBG_nagisa = new FunkinSprite(-50, -475);
	ptBG_nagisa.loadSprite(Paths.image("stages/partea/nagisa"));
	ptBG_nagisa.addAnim('bop', 'nagisa vibe instance 1', 24, true, false);
	ptBG_nagisa.scale.set(0.9, 0.9);
	ptBG_nagisa.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_nagisa);
	ptBG_nagisa.playAnim('bop');

	ptBG_sayaka = new FunkinSprite(-425, -525);
	ptBG_sayaka.loadSprite(Paths.image("stages/partea/sayaka"));
	ptBG_sayaka.addAnim('bop', 'sayaka_mami_vibe instance 1', 24, true, false);
	ptBG_sayaka.scale.set(0.9, 0.9);
	ptBG_sayaka.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_sayaka);
	ptBG_sayaka.playAnim('bop');

	kyubeySpeaker = new FunkinSprite(410, -425);
	kyubeySpeaker.loadSprite(Paths.image("game/speakerssmall"));
	kyubeySpeaker.addAnim('bop', 'speaker single instance 1', 24, false, false);
	kyubeySpeaker.scale.set(0.75, 0.75);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(-20, -825, 'kyubey-small', false);
	kyubey.scale.set(0.75, 0.75);
	kyubey.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubey);

	ptBG_table = new FunkinSprite(-250, 50);
	ptBG_table.loadSprite(Paths.image("stages/partea/table"));
	ptBG_table.scale.set(1.1, 1.1);
	ptBG_table.scrollFactor.set(1.25, 1.25);
	add(ptBG_table);

	introDarkness = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	introDarkness.scale.set(FlxG.width * 6, FlxG.height * 6);
	insert(members.indexOf(bf), introDarkness);
	introDarkness.alpha = 1.0;

	ptBG_bandInside = new FunkinSprite(-800, -1600);
	ptBG_bandInside.loadSprite(Paths.image("stages/partea/insideband"));
	ptBG_bandInside.scale.set(1.0, 1.0);
	ptBG_bandInside.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), ptBG_bandInside);
	ptBG_bandInside.visible = false;

	ptBG_bandCurtain = new FunkinSprite(-800, -1600);
	ptBG_bandCurtain.loadSprite(Paths.image("stages/partea/curtain"));
	ptBG_bandCurtain.scale.set(1.0, 1.0);
	ptBG_bandCurtain.scrollFactor.set(1.2, 1.2);
	add(ptBG_bandCurtain);
	ptBG_bandCurtain.visible = false;

	whiteShader = new CustomShader("WhiteOverlay");
	whiteShader.strength = 1.0;

	dad.shader = whiteShader;
	bf.shader = whiteShader;

	if (Options.gameplayShaders)
	{
		rainShader = new CustomShader("rain");
		FlxG.camera.addShader(rainShader);
		rainShader.iTimescale = 0.25;
		rainShader.iIntensity = 0.00;

		bnwShader = new CustomShader("Grayscale");
		bnwShader.grayness = 1.0;
		FlxG.camera.addShader(bnwShader);

		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		bloomShader.amt = 0.0;
	}
}

function postCreate()
{
	mamiPartea = strumLines.members[0].characters[1];
	gfPartea = strumLines.members[1].characters[1];
	madokaPartea = strumLines.members[2].characters[0];
	sayakaPartea = strumLines.members[3].characters[0];
	kyubeyPartea = strumLines.members[4].characters[0];
	nagisaPartea = strumLines.members[5].characters[0];

	for (char in [mamiPartea, gfPartea, madokaPartea, sayakaPartea, kyubeyPartea, nagisaPartea])
	{
		char.visible = false;
	}

	mamiPartea.x -= 100;
	gfPartea.x += 250;
	kyubeyPartea.setPosition(145, -450);

	madokaPartea.scale.set(0.85, 0.85);
	sayakaPartea.scale.set(0.85, 0.85);
	kyubeyPartea.scale.set(0.85, 0.85);
	nagisaPartea.scale.set(1.25, 1.25);

	remove(madokaPartea);
	insert(members.indexOf(bf), madokaPartea);

	remove(sayakaPartea);
	insert(members.indexOf(dad), sayakaPartea);

	remove(nagisaPartea);
	insert(members.indexOf(bf) + 50, nagisaPartea);

	ptBG_smoke = new FlxBackdrop(Paths.image("stages/partea/smoke"), FlxAxes.X, 0, 0);
	insert(members.indexOf(nagisaPartea), ptBG_smoke);
	ptBG_smoke.alpha = 0.0;
	ptBG_smoke.velocity.set(-15, 0);
	ptBG_smoke.y -= 50;

	ptBG_bandSpotlight = new FunkinSprite(-700, -625);
	ptBG_bandSpotlight.loadSprite(Paths.image("stages/partea/spotlight"));
	ptBG_bandSpotlight.scale.set(3.5, 3.5);
	// pt_bandSpotlight.scrollFactor.set(1.25, 1.25);
	insert(members.indexOf(nagisaPartea), ptBG_bandSpotlight);
	ptBG_bandSpotlight.alpha = 0.0;
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	// camGame.zoom = 0.65;

	if (Options.gameplayShaders)
	{
		rainShader.iTime = totalElapsed;
	}

	totalElapsed += elapsed;

	ptBG_bandSpotlight.y += Math.sin(totalElapsed) * 0.75;
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		kyubeySpeaker.playAnim('bop', true);

		nagisaPartea.y = -250 + nagisaYOffset;
		FlxTween.tween(nagisaPartea, {y: nagisaPartea.y - 25}, 0.5, {ease: FlxEase.expoOut});
	}
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Intro":
				dad.visible = false;
				bf.visible = false;

				madokaPartea.visible = true;

				madokaPartea.x -= 500;
				mamiPartea.x += 100;
				gfPartea.x -= 250;
				mamiPartea.alpha = 0.0;
				gfPartea.alpha = 0.0;

				gfPartea.shader = whiteShader;
				mamiPartea.shader = whiteShader;
				madokaPartea.shader = whiteShader;

			case "Mid Intro":
				gfPartea.useRenderTexture = true;
				gfPartea.visible = true;
				mamiPartea.useRenderTexture = true;
				mamiPartea.visible = true;
				FlxTween.tween(gfPartea, {alpha: 1.0}, 3.5);
				FlxTween.tween(mamiPartea, {alpha: 1.0}, 3.5);

			case "End Intro":
				dad.visible = true;
				bf.visible = true;
				madokaPartea.visible = false;
				madokaPartea.x += 500;
				mamiPartea.x -= 100;
				gfPartea.x += 250;
				gfPartea.visible = false;
				mamiPartea.visible = false;
				mamiPartea.alpha = 1.0;
				gfPartea.alpha = 1.0;
				gfPartea.shader = null;
				mamiPartea.shader = null;
				madokaPartea.shader = null;

			case "Rain":
				if (Options.gameplayShaders)
				{
					FlxTween.num(rainShader.iIntensity, params[1], params[2], {
						ease: FlxEase.quadInOut
					}, function(num:Float)
					{
						rainShader.iIntensity = num;
					});
				}

			case "Char Visible":
				if (params[1] == 'true')
					dad.visible = true;
				else
					dad.visible = false;

				if (params[2] == 'true')
					bf.visible = true;
				else
					bf.visible = false;

			case "Start Retro":
				whiteShader.strength = 1.0;

				if (Options.gameplayShaders)
				{
					bnwShader.grayness = 1.0;
				}
				introDarkness.alpha = 1.0;

			case "Stop Retro":
				whiteShader.strength = 0.0;

				if (Options.gameplayShaders)
				{
					bnwShader.grayness = 0.0;
				}
				introDarkness.alpha = 0.0;

			case "Setup Position":
				bf.useRenderTexture = true;
				bf.alpha = 0.0;
				bf.scale.set(1.25, 1.25);
				bf.x -= 150;
				bf.y -= 50;

				introDarkness.alpha = 1.0;

				FlxTween.tween(bf, {x: bf.x - 200}, 11.0);
				FlxTween.tween(bf, {alpha: 0.25}, 5.0, {ease: FlxEase.quadInOut, startDelay: 1.0});

			case "Pre Partea":
				bf.setPosition(800, -390);

				for (spr in [
					ptBG_bgcity,
					ptBG_bg,
					ptBG_object,
					ptBG_couch,
					ptBG_madoka,
					ptBG_nagisa,
					ptBG_sayaka,
					kyubeySpeaker,
					kyubey,
					ptBG_table
				])
					spr.visible = false;

				ptBG_bandInside.visible = true;
				ptBG_bandCurtain.visible = true;

				dad.visible = false;
				bf.visible = false;
				for (char in [mamiPartea, gfPartea, madokaPartea, sayakaPartea, kyubeyPartea, nagisaPartea])
				{
					char.visible = true;
					char.color = FlxColor.BLACK;
				}

				nagisaPartea.visible = false;

				ptBG_bandInside.color = FlxColor.GRAY;
				ptBG_bandCurtain.color = FlxColor.BLACK;

				introDarkness.alpha = 0.0;

				ptBG_smoke.alpha = 0.50;
				ptBG_bandSpotlight.alpha = 0.65;

			// FlxTween.tween(nagisaPartea, {x: nagisaPartea.x + 2500}, 19.0);

			case "Move Spotlight":
				FlxTween.tween(ptBG_bandSpotlight, {x: ptBG_bandSpotlight.x + 1200}, 2.0, {ease: FlxEase.quadInOut});

			case "Move Back Spotlight":
				FlxTween.tween(ptBG_bandSpotlight, {x: ptBG_bandSpotlight.x - 1200}, 2.0, {ease: FlxEase.quadInOut});

			case "Move Center Spotlight":
				FlxTween.tween(ptBG_bandSpotlight, {x: -50}, 4.0, {ease: FlxEase.quadInOut});

			case "Spotlight Stop":
				FlxTween.tween(ptBG_bandSpotlight, {'scale.x': 5.0, 'scale.y': 5.0, alpha: 0.0}, Conductor.stepCrochet * 10 / 1000, {ease: FlxEase.expoIn});

				if (Options.gameplayShaders)
				{
					FlxTween.num(bnwShader.grayness, 0.0, Conductor.stepCrochet * 10 / 1000, {ease: FlxEase.expoIn}, function(num:Float)
					{
						bnwShader.grayness = num;
					});
				}

				for (spr in [mamiPartea, gfPartea, madokaPartea, sayakaPartea, kyubeyPartea])
				{
					FlxTween.color(spr, Conductor.stepCrochet * 10 / 1000, spr.color, FlxColor.WHITE, {ease: FlxEase.expoIn});
				}

				FlxTween.tween(ptBG_smoke, {alpha: 0.0}, Conductor.stepCrochet * 10 / 1000, {ease: FlxEase.expoIn});

				if (Options.gameplayShaders)
				{
					FlxTween.num(0, -1.0, Conductor.stepCrochet * 10 / 1000, {ease: FlxEase.expoIn}, function(num:Float)
					{
						bloomShader.amt = num;
					});
				}

			case "Partea":
				dad.visible = false;
				bf.visible = false;
				for (char in [mamiPartea, gfPartea, madokaPartea, sayakaPartea, kyubeyPartea, nagisaPartea])
				{
					char.visible = true;
				}

				ptBG_bandInside.color = FlxColor.WHITE;
				ptBG_bandCurtain.color = FlxColor.WHITE;

				nagisaPartea.color = FlxColor.WHITE;

				FlxTween.tween(nagisaPartea, {x: nagisaPartea.x + 3700}, 18.0);

				if (Options.gameplayShaders)
				{
					bloomShader.amt = 0.0;
				}

			case "Nagisa Cycle":
				nagisaYOffset = -150;

				nagisaPartea.x = -1200;
				FlxTween.tween(nagisaPartea, {x: nagisaPartea.x + 3700}, 18.0);

			case "End Partea":
				if (Options.gameplayShaders)
				{
					bloomShader.amt = 0.0;
				}

				bf.setPosition(800, -390);
				bf.scale.set(1.0, 1.0);
				bf.shader = null;
				bf.alpha = 1.0;
				dad.shader = null;

				for (spr in [
					ptBG_bgcity,
					ptBG_bg,
					ptBG_object,
					ptBG_couch,
					ptBG_madoka,
					ptBG_nagisa,
					ptBG_sayaka,
					kyubeySpeaker,
					kyubey,
					ptBG_table,
					bf,
					dad
				])
					spr.visible = true;

				ptBG_bandInside.visible = false;
				ptBG_bandCurtain.visible = false;

				dad.visible = true;
				bf.visible = true;
				for (char in [mamiPartea, gfPartea, madokaPartea, sayakaPartea, kyubeyPartea, nagisaPartea])
				{
					char.visible = false;
				}

				ptBG_smoke.visible = false;
				ptBG_bandSpotlight.visible = false;
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
