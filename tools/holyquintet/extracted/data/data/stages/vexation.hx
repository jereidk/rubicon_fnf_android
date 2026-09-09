import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import hxvlc.flixel.FlxVideoSprite;
import openfl.display.BlendMode;
import util.GenUtil;

var impact:FunkinSprite;
var impact2:FunkinSprite;

// BG
var vexBG:FunkinSprite;
var vexBGReflection:FunkinSprite;
public var kyubeySpeaker:FunkinSprite;
public var kyubey:Character;
var vexBG_sayaka:FunkinSprite;
var vexBG_mami:FunkinSprite;
var vexBG_madoka:FunkinSprite;
var vexBG_multi:FunkinSprite;
var vexBG_add:FunkinSprite;
var vexBG_rays:FunkinSprite;
var vexBG_dust:FunkinSprite;
var vexBG_pipes:FunkinSprite;
var vexBGSprs:Array = [];
var camFX:FlxCamera;
var camFXuseHUDzoom:Bool = true;

function create()
{
	startUIvisablityArgs = [true, true, true, false, true, 0, false, 4, "linear", "In"];

	camFX = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camFX.bgColor = 0x00000000;
	FlxG.cameras.remove(camGame, false);
	FlxG.cameras.remove(camHUD, false);
	FlxG.cameras.add(camGame, true);
	FlxG.cameras.add(camFX, false);
	FlxG.cameras.add(camHUD, false);

	vexBG = new FunkinSprite(0, 0);
	vexBG.loadSprite(Paths.image("stages/vexation/vex_ground"));
	vexBG.scale.set(1.75, 1.75);
	vexBG.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), vexBG);

	if (!Options.lowMemoryMode)
	{
		vexBGReflection = new FunkinSprite(0, 0);
		vexBGReflection.loadSprite(Paths.image("stages/vexation/vex_groundref"));
		vexBGReflection.scale.set(1.75, 1.75);
		vexBGReflection.scrollFactor.set(1.0, 1.0);
		insert(members.indexOf(bf), vexBGReflection);
	}

	kyubeySpeaker = new FunkinSprite(1000, 500);
	kyubeySpeaker.loadSprite(Paths.image("game/speakerssmall"));
	kyubeySpeaker.addAnim('bop', 'speaker single instance 1', 24, false, false);
	kyubeySpeaker.scale.set(0.85, 0.85);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(550, 130, 'kyubey-small', false);
	kyubey.scale.set(0.85, 0.85);
	kyubey.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubey);

	vexBG_sayaka = new FunkinSprite(750, 125);
	vexBG_sayaka.loadSprite(Paths.image("stages/vexation/sayaka"));
	vexBG_sayaka.addAnim('bop', 'sayaka_kyokobg', 24, false, false);
	vexBG_sayaka.scale.set(0.95, 0.95);
	vexBG_sayaka.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), vexBG_sayaka);
	vexBG_sayaka.playAnim('bop');

	vexBG_mami = new FunkinSprite(490, 80);
	vexBG_mami.loadSprite(Paths.image("stages/vexation/mami"));
	vexBG_mami.addAnim('bop', 'mami_kyokobg', 24, false, false);
	vexBG_mami.scale.set(0.90, 0.90);
	vexBG_mami.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), vexBG_mami);
	vexBG_mami.playAnim('bop');

	vexBG_madoka = new FunkinSprite(350, 200);
	vexBG_madoka.loadSprite(Paths.image("stages/vexation/madoka"));
	vexBG_madoka.addAnim('bop', 'madoka_kyokobg', 24, false, false);
	vexBG_madoka.scale.set(1.25, 1.25);
	vexBG_madoka.scrollFactor.set(1.0, 1.0);
	add(vexBG_madoka);
	vexBG_madoka.playAnim('bop');

	vexBG_multi = new FunkinSprite(0, 0);
	vexBG_multi.loadSprite(Paths.image("stages/vexation/vex_ovMult"));
	vexBG_multi.scale.set(1.75, 1.75);
	vexBG_multi.scrollFactor.set(1.0, 1.0);
	add(vexBG_multi);
	vexBG_multi.blend = BlendMode.MULTIPLY;
	vexBG_multi.alpha = 0.25;

	vexBG_add = new FunkinSprite(0, 0);
	vexBG_add.loadSprite(Paths.image("stages/vexation/vex_ovAdd"));
	vexBG_add.scale.set(1.75, 1.75);
	vexBG_add.scrollFactor.set(1.0, 1.0);
	add(vexBG_add);
	vexBG_add.blend = BlendMode.ADD;
	vexBG_add.alpha = 0.25;

	vexBG_rays = new FunkinSprite(-150, 0);
	vexBG_rays.loadSprite(Paths.image("stages/vexation/vex_rays"));
	vexBG_rays.scale.set(1.5, 1.5);
	vexBG_rays.scrollFactor.set(1.5, 1.5);
	add(vexBG_rays);
	vexBG_rays.blend = BlendMode.ADD;

	vexBG_dust = new FunkinSprite(0, 0);
	vexBG_dust.loadSprite(Paths.image("stages/vexation/vex_dust"));
	vexBG_dust.scale.set(1.75, 1.75);
	vexBG_dust.scrollFactor.set(1.0, 1.0);
	add(vexBG_dust);
	vexBG_dust.blend = BlendMode.ADD;
	vexBG_dust.alpha = 1.0;

	vexBG_pipes = new FunkinSprite(0, 0);
	vexBG_pipes.loadSprite(Paths.image("stages/vexation/vex_pipes"));
	vexBG_pipes.scale.set(1.35, 1.35);
	vexBG_pipes.scrollFactor.set(1.5, 1.5);
	add(vexBG_pipes);

	for (spr in [
		vexBG,
		kyubeySpeaker,
		kyubey,
		vexBG_sayaka,
		vexBG_mami,
		vexBG_madoka,
		vexBG_multi,
		vexBG_add,
		vexBG_rays,
		vexBG_dust,
		vexBG_pipes
	])
		vexBGSprs.push(spr);

	if (!Options.lowMemoryMode)
		vexBGSprs.push(vexBGReflection);

	if (!Options.lowMemoryMode)
	{
		sparksVideo = GenUtil.createVideo("fire", 1.25, true);
		add(sparksVideo);
		sparksVideo.alpha = 0.0;
		sparksVideo.blend = BlendMode.ADD;
	}

	// First FX
	kyubeyShader = new CustomShader("pureColor");
	kyubeyShader.colSet = true;
	kyubeyShader.funnyColor = [0.75, 0.75, 0.75, 1.0];

	kyokoShader = new CustomShader("pureColor");
	kyokoShader.colSet = true;
	kyokoShader.funnyColor = [0.647, 0.224, 0.353, 1.0];

	gfShader = new CustomShader("pureColor");
	gfShader.colSet = true;
	gfShader.funnyColor = [0.647, 0.0, 0.302, 1.0];

	kyubeySilo = new Character(600, 200, 'kyubey-small', false);
	add(kyubeySilo);
	kyubeySilo.alpha = 0.0;
	kyubeySilo.useRenderTexture = true;
	kyubeySilo.cameras = [camFX];
	kyubeySilo.shader = kyubeyShader;

	kyokoSilo = new Character(800, 150, 'kyoko-base', false);
	add(kyokoSilo);
	kyokoSilo.alpha = 0.0;
	kyokoSilo.useRenderTexture = true;
	kyokoSilo.cameras = [camFX];
	kyokoSilo.shader = kyokoShader;

	gfSilo = new Character(800, 200, 'gf-base', true);
	add(gfSilo);
	gfSilo.alpha = 0.0;
	gfSilo.useRenderTexture = true;
	gfSilo.cameras = [camFX];
	gfSilo.shader = gfShader;

	// Second FX
	cutinBG = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	cutinBG.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(cutinBG);
	cutinBG.alpha = 0.0;
	cutinBG.cameras = [camFX];

	cutinBlue = new FlxBackdrop(Paths.image('stages/vexation/cutinblue'), FlxAxes.X, 0, 0);
	add(cutinBlue);
	cutinBlue.alpha = 0.0;
	cutinBlue.y = 150;
	cutinBlue.velocity.set(5000, 0);
	cutinBlue.cameras = [camFX];

	kyokoCutIn = new Character(250, -200, 'kyoko-base-cutin', false);
	add(kyokoCutIn);
	kyokoCutIn.alpha = 0.0;
	kyokoCutIn.cameras = [camFX];

	cutinRed = new FlxBackdrop(Paths.image('stages/vexation/cutinred'), FlxAxes.X, 0, 0);
	add(cutinRed);
	cutinRed.alpha = 0.0;
	cutinRed.y = 575;
	cutinRed.velocity.set(-5000, 0);
	cutinRed.cameras = [camFX];

	gfCutIn = new Character(1100, 175, 'gf-base-cutin', true);
	add(gfCutIn);
	gfCutIn.alpha = 0.0;
	gfCutIn.cameras = [camFX];

	camFX.visible = true;
}

function postCreate()
{
	if (Options.downscroll)
	{
		firstText = new FlxText(1200, 800, 500, '▼ ${i18n.tr('Gameplay/Vexation/GoFirst')} ▼');
		firstText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER);
		firstText.borderSize = 3.0;
		add(firstText);
		firstText.cameras = [camUI];
		FlxTween.tween(firstText, {y: firstText.y - 10}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	}
	else
	{
		firstText = new FlxText(1200, 250, 500, '▲ ${i18n.tr('Gameplay/Vexation/GoFirst')} ▲');
		firstText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER);
		firstText.borderSize = 3.0;
		add(firstText);
		firstText.cameras = [camUI];
		FlxTween.tween(firstText, {y: firstText.y - 10}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
	}

	if (Options.middleScroll)
	{
		firstText.screenCenter(FlxAxes.X);
	}

	if (!Options.lowMemoryMode)
	{
		reflectionPlayer = new Character(bf.x, bf.y + 1175, 'gf-base', true);
		insert(members.indexOf(vexBGReflection), reflectionPlayer);
		reflectionPlayer.alpha = 0.5;
		reflectionPlayer.flipY = true;
		reflectionPlayer.useRenderTexture = true;

		reflectionOpponent = new Character(dad.x, dad.y + 660, 'kyoko-base', false);
		insert(members.indexOf(vexBGReflection), reflectionOpponent);
		reflectionOpponent.alpha = 0.5;
		reflectionOpponent.flipY = true;
		reflectionOpponent.useRenderTexture = true;
	}
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	if (!Options.lowMemoryMode)
	{
		reflectionPlayer.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);
		reflectionOpponent.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
	}

	if (camFX.visible)
	{
		kyubeySilo.playAnim(kyubey.getAnimName(), true, null, false, kyubey.globalCurFrame);
		kyokoSilo.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
		gfSilo.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);

		kyokoCutIn.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
		gfCutIn.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);

		if (camFXuseHUDzoom)
			camFX.zoom = camHUD.zoom * camHUD.zoomMultiplier;
	}
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		kyubeySpeaker.playAnim('bop', true);
		vexBG_sayaka.playAnim('bop', true);
		vexBG_mami.playAnim('bop', true);
		vexBG_madoka.playAnim('bop', true);
	}
}

function stepHit(curStep:Int)
{
}

function onGamePause(event)
{
}

function onSubstateClose(event)
{
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Light":
				switch (params[1])
				{
					case "Dim":
						for (spr in vexBGSprs)
							spr.color = 0xFF141414;

						vexBG_multi.visible = false;
						vexBG_add.visible = false;
						vexBG_rays.visible = false;
						vexBG_dust.visible = false;
						vexBG_pipes.visible = false;

					case "Bright":
						for (spr in vexBGSprs)
							spr.color = FlxColor.WHITE;

						vexBG_multi.alpha = 0.25;
						vexBG_add.alpha = 0.25;
						vexBG_rays.alpha = 1.0;
						vexBG_dust.alpha = 1.0;
						vexBG_pipes.alpha = 1.0;
						vexBG_multi.visible = true;
						vexBG_add.visible = true;
						vexBG_rays.visible = true;
						vexBG_dust.visible = true;
						vexBG_pipes.visible = true;

						if (!Options.lowMemoryMode)
						{
							if (sparksVideo.visible)
							{
								sparksVideo.alpha = 1.0;
								sparksVideo.resume();
							}
						}

					case "Tween Dim":
						for (spr in [
							vexBG,
							kyubeySpeaker,
							kyubey,
							vexBG_sayaka,
							vexBG_mami,
							vexBG_madoka,
							vexBG_pipes
						])
							FlxTween.color(spr, Conductor.stepCrochet * params[2] / 1000, spr.color, 0xFF141414, {ease: FlxEase.quadInOut});

						if (!Options.lowMemoryMode)
							FlxTween.color(vexBGReflection, Conductor.stepCrochet * params[2] / 1000, vexBGReflection.color, 0xFF141414,
								{ease: FlxEase.quadInOut});

						for (spr in [vexBG_multi, vexBG_add, vexBG_rays, vexBG_dust, vexBG_pipes])
							FlxTween.tween(spr, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadInOut});

						if (!Options.lowMemoryMode) FlxTween.tween(sparksVideo, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000,
							{ease: FlxEase.quadInOut});
				}
			case "FX 1":
				switch (params[1])
				{
					case "Start":
						camFX.visible = true;
						kyokoSilo.x = 1000;
						gfSilo.x = 400;

					case "Kyoko Show":
						FlxTween.tween(kyokoSilo, {x: 300, alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});

					case "Girlfriend Show":
						FlxTween.tween(gfSilo, {x: 1000, alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadOut});

					case "Kyubey Show":
						FlxTween.tween(kyubeySilo, {alpha: 0.25}, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadOut});

					case "Slow Zoom":
						camFXuseHUDzoom = false;
						FlxTween.tween(kyubeySilo, {alpha: 0.75}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(kyokoSilo, {alpha: 0.5}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(gfSilo, {alpha: 0.5}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});
						FlxTween.tween(camFX, {zoom: 1.5, 'scroll.y': 50}, Conductor.stepCrochet * 132 / 1000, {ease: FlxEase.quadInOut});

					case "End FX":
						FlxTween.tween(camFX, {zoom: 2.5, 'scroll.y': 75}, Conductor.stepCrochet * 8 / 1000, {
							ease: FlxEase.expoIn,
							onComplete: function(twn:FlxTween)
							{
								camFXuseHUDzoom = true;
								camFX.visible = false;
								kyubeySilo.visible = false;
								kyokoSilo.visible = false;
								gfSilo.visible = false;
							}
						});
				}

			case "FX 2":
				switch (params[1])
				{
					case "Start":
						camFX.zoom = 1.0;
						camFX.scroll.y = 0;
						camFX.visible = true;
						gfCutIn.x = 1400;
						kyokoCutIn.x = 50;

						FlxTween.tween(cutinBG, {alpha: 0.75}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});

						FlxTween.tween(gfCutIn, {x: 1000}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.expoOut});
						FlxTween.tween(kyokoCutIn, {x: 400}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.expoOut});

						for (spr in [cutinBlue, cutinRed, gfCutIn, kyokoCutIn])
						{
							spr.alpha = 0.0;
							spr.scale.y = 0.0;
							FlxTween.tween(spr, {'scale.y': 1.0, alpha: 1.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						}
					case "End":
						camFX.zoom = 1.0;
						camFX.scroll.y = 0;
						camFX.visible = true;
						gfCutIn.x = 1000;
						kyokoCutIn.x = 400;

						FlxTween.tween(cutinBG, {alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});

						FlxTween.tween(gfCutIn, {x: 400}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						FlxTween.tween(kyokoCutIn, {x: 1400}, Conductor.stepCrochet * 8 / 1000, {
							ease: FlxEase.expoOut,
							onComplete: function(twn:FlxTween)
							{
								camFX.visible = false;
							}
						});

						for (spr in [cutinBlue, cutinRed, gfCutIn, kyokoCutIn])
						{
							spr.alpha = 1.0;
							spr.scale.y = 1.0;
							FlxTween.tween(spr, {'scale.y': 0.0, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {ease: FlxEase.expoOut});
						}
				}

			case "Sparks":
				switch (params[1])
				{
					case "Start":
						if (!Options.lowMemoryMode)
						{
							sparksVideo.play();
							sparksVideo.visible = true;
							FlxTween.tween(sparksVideo, {alpha: 1.0}, Conductor.stepCrochet * 16 / 1000, {ease: FlxEase.quadInOut});
						}

					case "End":
						if (!Options.lowMemoryMode)
						{
							sparksVideo.pause();
							sparksVideo.alpha = 0.0;
							sparksVideo.visible = false;
						}
				}
			case "Hide Text":
				FlxTween.tween(firstText, {alpha: 0.0}, Conductor.stepCrochet * params[1] / 1000, {ease: FlxEase.sineInOut});
		}
	}
}

function onGamePause(e)
{
	if (!Options.lowMemoryMode)
	{
		if (sparksVideo.visible)
			sparksVideo.pause();
	}
}

function onSubstateClose(e)
{
	if (paused)
	{
		if (!Options.lowMemoryMode)
		{
			if (sparksVideo.visible)
				sparksVideo.resume();
		}
	}
}
