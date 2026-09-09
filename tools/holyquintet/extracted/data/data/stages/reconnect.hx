import flixel.addons.display.FlxBackdrop;
import hxvlc.flixel.FlxVideoSprite;
import openfl.display.BlendMode;
import util.GenUtil;

importScript('data/scripts/kadeHUD');
public var kyubey:Character;
public var kyubeySpeaker:Character;
var transitionVideo:FlxVideoSprite;

graphicCache.cache(Paths.image("game/splashes/og"));
function create()
{
	startUIvisablityArgs = [true, true, true, true, true, 0, false, 4, "linear", "In"];

	// BG Sprites
	reconBG_Below = new FunkinSprite(0, -600);
	reconBG_Below.loadSprite(Paths.image("stages/reconnect/bg"));
	reconBG_Below.scale.set(2.5, 2.5);
	reconBG_Below.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), reconBG_Below);

	reconBG_BelowMask = new FunkinSprite(0, -600);
	reconBG_BelowMask.loadSprite(Paths.image("stages/reconnect/bgmask"));
	reconBG_BelowMask.scale.set(2.5, 2.5);
	reconBG_BelowMask.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), reconBG_BelowMask);

	reconBG_Kanae = new FunkinSprite(1200, -450);
	reconBG_Kanae.loadSprite(Paths.image("stages/reconnect/kanae"));
	reconBG_Kanae.addAnim('bop', 'kanae idle0', 24, true, false);
	reconBG_Kanae.scale.set(1.25, 1.25);
	insert(members.indexOf(bf), reconBG_Kanae);
	reconBG_Kanae.alpha = 0.5;
	reconBG_Kanae.playAnim('bop');

	kyubeySpeaker = new FunkinSprite(800, -130);
	kyubeySpeaker.loadSprite(Paths.image("game/speakerssmall"));
	kyubeySpeaker.addAnim('bop', 'speaker single instance 1', 24, true, false);
	kyubeySpeaker.scale.set(0.9, 0.9);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(315, -490, 'kyubey-small', false);
	kyubey.scale.set(0.95, 0.95);
	kyubey.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubey);

	reconBG_Sayaka = new FunkinSprite(1400, -350);
	reconBG_Sayaka.loadSprite(Paths.image("stages/reconnect/sayaka"));
	reconBG_Sayaka.addAnim('bop', 'sayaka', 24, false, false);
	reconBG_Sayaka.scale.set(1.35, 1.35);
	insert(members.indexOf(bf), reconBG_Sayaka);
	reconBG_Sayaka.playAnim('bop');

	reconBG_Kyoko = new FunkinSprite(1850, -325);
	reconBG_Kyoko.loadSprite(Paths.image("stages/reconnect/kyoko"));
	reconBG_Kyoko.addAnim('bop', 'kyoko', 24, false, false);
	reconBG_Kyoko.scale.set(1.35, 1.35);
	insert(members.indexOf(bf), reconBG_Kyoko);
	reconBG_Kyoko.playAnim('bop');

	reconBG_Madoka = new FunkinSprite(-150, -325);
	reconBG_Madoka.loadSprite(Paths.image("stages/reconnect/madoka"));
	reconBG_Madoka.addAnim('bop', 'madoka', 24, false, false);
	reconBG_Madoka.scale.set(1.35, 1.35);
	insert(members.indexOf(bf), reconBG_Madoka);
	reconBG_Madoka.playAnim('bop');

	reconBG_Homura = new FunkinSprite(-475, -125);
	reconBG_Homura.loadSprite(Paths.image("stages/reconnect/homura"));
	reconBG_Homura.addAnim('bop', 'homura', 24, false, false);
	reconBG_Homura.scale.set(1.75, 1.75);
	add(reconBG_Homura);
	reconBG_Homura.playAnim('bop');

	if (!Options.lowMemoryMode)
	{
		reflectionKyubey = new Character(kyubey.x + 1060, kyubey.y + 200, 'kyubey-small', true);
		insert(members.indexOf(kyubey), reflectionKyubey);
		reflectionKyubey.alpha = 0.1;
		reflectionKyubey.blend = BlendMode.ADD;
		reflectionKyubey.flipX = false;
		reflectionKyubey.flipY = true;
		reflectionKyubey.useRenderTexture = true;

		reflectionSpeaker = new FunkinSprite(kyubeySpeaker.x, kyubeySpeaker.y + 210);
		reflectionSpeaker.loadSprite(Paths.image("game/speakerssmall"));
		reflectionSpeaker.addAnim('bop', 'speaker single instance 1', 24, true, false);
		reflectionSpeaker.scale.set(0.9, 0.9);
		reflectionSpeaker.scrollFactor.set(1.0, 1.0);
		insert(members.indexOf(kyubeySpeaker), reflectionSpeaker);
		reflectionSpeaker.playAnim('bop');
		reflectionSpeaker.alpha = 0.1;
		reflectionSpeaker.blend = BlendMode.ADD;
		reflectionSpeaker.flipY = true;

		reflectionSayaka = new FunkinSprite(reconBG_Sayaka.x, reconBG_Sayaka.y + 525);
		reflectionSayaka.loadSprite(Paths.image("stages/reconnect/sayaka"));
		reflectionSayaka.addAnim('bop', 'sayaka', 24, false, false);
		reflectionSayaka.scale.set(1.35, 1.35);
		insert(members.indexOf(reconBG_Sayaka), reflectionSayaka);
		reflectionSayaka.playAnim('bop');
		reflectionSayaka.alpha = 0.1;
		reflectionSayaka.blend = BlendMode.ADD;
		reflectionSayaka.flipY = true;

		reflectionKyoko = new FunkinSprite(reconBG_Kyoko.x, reconBG_Kyoko.y + 660);
		reflectionKyoko.loadSprite(Paths.image("stages/reconnect/kyoko"));
		reflectionKyoko.addAnim('bop', 'kyoko', 24, false, false);
		reflectionKyoko.scale.set(1.35, 1.35);
		insert(members.indexOf(reconBG_Kyoko), reflectionKyoko);
		reflectionKyoko.playAnim('bop');
		reflectionKyoko.alpha = 0.1;
		reflectionKyoko.flipY = true;

		reflectionMadoka = new FunkinSprite(reconBG_Madoka.x, reconBG_Madoka.y + 500);
		reflectionMadoka.loadSprite(Paths.image("stages/reconnect/madoka"));
		reflectionMadoka.addAnim('bop', 'madoka', 24, false, false);
		reflectionMadoka.scale.set(1.35, 1.35);
		insert(members.indexOf(reconBG_Madoka), reflectionMadoka);
		reflectionMadoka.playAnim('bop');
		reflectionMadoka.alpha = 0.1;
		reflectionMadoka.blend = BlendMode.ADD;
		reflectionMadoka.flipY = true;

		reflectionPlayer = new Character(bf.x, bf.y + 1175, 'gf-base', true);
		insert(members.indexOf(bf), reflectionPlayer);
		reflectionPlayer.alpha = 0.5;
		reflectionPlayer.blend = BlendMode.ADD;
		reflectionPlayer.flipY = true;
		reflectionPlayer.useRenderTexture = true;

		reflectionOpponent = new Character(dad.x, dad.y + 790, 'mami-base', false);
		insert(members.indexOf(dad), reflectionOpponent);
		reflectionOpponent.alpha = 0.5;
		reflectionOpponent.blend = BlendMode.ADD;
		reflectionOpponent.flipY = true;
		reflectionOpponent.useRenderTexture = true;

		reconBG_BelowReflection = new FunkinSprite(0, 355);
		reconBG_BelowReflection.loadSprite(Paths.image("stages/reconnect/bgreflective"));
		reconBG_BelowReflection.scale.set(2.5, 2.5);
		reconBG_BelowReflection.scrollFactor.set(1.0, 1.0);
		insert(members.indexOf(dad), reconBG_BelowReflection);
	}

	// OG Sprites
	reconBGOG_BG = new FunkinSprite(-500, -1000);
	reconBGOG_BG.loadSprite(Paths.image("stages/reconnect/og/BG"));
	reconBGOG_BG.scale.set(1.25, 1.25);
	reconBGOG_BG.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), reconBGOG_BG);

	reconBGOG_Girls = new FunkinSprite(-300, -550);
	reconBGOG_Girls.loadSprite(Paths.image("stages/reconnect/og/BGGirlsDance"));
	reconBGOG_Girls.addAnim('bop', 'girls dancing instance 1', 24, false, false);
	reconBGOG_Girls.scale.set(1.0, 1.0);
	reconBGOG_Girls.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), reconBGOG_Girls);

	reconBGOG_BG.visible = false;
	reconBGOG_Girls.visible = false;

	strumLines.members[0].characters[1].visible = false;
	strumLines.members[1].characters[1].visible = false;

	// Event
	if (!Options.lowMemoryMode)
	{
		spotsBack = new FlxBackdrop(Paths.image('stages/reconnect/spotsback'), FlxAxes.XY, 0, 0);
		insert(members.indexOf(reconBG_Below) + 1, spotsBack);
		spotsBack.blend = BlendMode.ADD;
		spotsBack.alpha = 0.0;
		spotsBack.scrollFactor.set(1.5, 1.5);
		spotsBack.velocity.set(25, 50);

		spotsFront = new FlxBackdrop(Paths.image('stages/reconnect/spotsfront'), FlxAxes.XY, 0, 0);
		add(spotsFront);
		spotsFront.blend = BlendMode.ADD;
		spotsFront.alpha = 0.0;
		spotsFront.scrollFactor.set(0.5, 0.5);
		spotsFront.velocity.set(75, 100);
	}
}

function postCreate()
{
	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		bloomShader.amt = 0.0;
	}

	// Event
	if (!Options.lowMemoryMode)
	{
		transitionVideo = GenUtil.createVideo("reconnect_transition-midsong", 1.0, false);
		insert(0, transitionVideo);
		transitionVideo.blend = BlendMode.ADD;
		transitionVideo.cameras = [camHUD];

		transitionOutVideo = GenUtil.createVideo("reconnect_transition_out-midsong", 1.0, false);
		insert(0, transitionOutVideo);
		transitionOutVideo.blend = BlendMode.ADD;
		transitionOutVideo.cameras = [camHUD];
	}

	logo = new FunkinSprite(0, 0);
	logo.loadSprite(Paths.image("stages/reconnect/logo"));
	add(logo);
	logo.alpha = 0.0;
	logo.cameras = [camUI];
	logo.screenCenter(FlxAxes.XY);
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	Options.gpuOnlyBitmaps = true;
	totalElapsed += elapsed;

	if (!Options.lowMemoryMode)
	{
		reflectionPlayer.playAnim(bf.getAnimName(), true, null, false, bf.globalCurFrame);
		reflectionOpponent.playAnim(dad.getAnimName(), true, null, false, dad.globalCurFrame);
	}
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		kyubeySpeaker.playAnim('bop', true);
		reconBG_Sayaka.playAnim('bop', true);
		reconBG_Kyoko.playAnim('bop', true);
		reconBG_Madoka.playAnim('bop', true);
		reconBG_Homura.playAnim('bop', true);
		reconBGOG_Girls.playAnim('bop', true);

		if (!Options.lowMemoryMode)
		{
			reflectionSayaka.playAnim('bop', true);
			reflectionKyoko.playAnim('bop', true);
			reflectionMadoka.playAnim('bop', true);
			reflectionSpeaker.playAnim('bop', true);
		}
	}
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "OG":
				switch (params[1])
				{
					case 'Start':
						strumLines.members[0].characters[0].visible = false;
						strumLines.members[1].characters[0].visible = false;
						for (spr in [
							reconBG_Below,
							reconBG_BelowMask,
							kyubeySpeaker,
							kyubey,
							reconBG_Sayaka,
							reconBG_Kyoko,
							reconBG_Madoka,
							reconBG_Homura,
							reconBG_Kanae
						])
							spr.visible = false;

						if (!Options.lowMemoryMode)
						{
							for (spr in [
								spotsBack,
								spotsFront,
								reflectionPlayer,
								reflectionOpponent,
								reflectionSayaka,
								reflectionKyoko,
								reflectionMadoka,
								reconBG_BelowReflection
							])
								spr.visible = false;
						}

						strumLines.members[0].characters[1].visible = true;
						strumLines.members[1].characters[1].visible = true;
						for (spr in [reconBGOG_BG, reconBGOG_Girls])
							spr.visible = true;

						for (strum in strumLines.members[1])
							updateStrumSkin(strum, true);

						iconP1.setIcon('gf-old');
						iconP2.setIcon('mami-old');

						health = 1;

						camZoomLerp = 0.5;
						doIconBop = true;

						healthBar.createFilledBar(0xFFFF0000, 0xFF00FF00);
						healthBar.updateBar();

					case 'End':
						strumLines.members[0].characters[0].visible = true;
						strumLines.members[1].characters[0].visible = true;
						for (spr in [
							reconBG_Below,
							reconBG_BelowMask,
							kyubeySpeaker,
							kyubey,
							reconBG_Sayaka,
							reconBG_Kyoko,
							reconBG_Madoka,
							reconBG_Homura,
							reconBG_Kanae
						])
							spr.visible = true;

						if (!Options.lowMemoryMode)
						{
							for (spr in [
								spotsBack,
								spotsFront,
								reflectionPlayer,
								reflectionOpponent,
								reflectionSayaka,
								reflectionKyoko,
								reflectionMadoka,
								reconBG_BelowReflection
							])
								spr.visible = true;
						}

						strumLines.members[0].characters[1].visible = false;
						strumLines.members[1].characters[1].visible = false;
						for (spr in [reconBGOG_BG, reconBGOG_Girls])
							spr.visible = false;

						for (strum in strumLines.members[1])
							updateStrumSkin(strum, false);

						iconP1.setIcon('gf');
						iconP2.setIcon('mami');

						camZoomLerp = Flags.DEFAULT_ZOOM_LERP;
						doIconBop = false;

						healthBar.createFilledBar(dad.iconColor, bf.iconColor);
						healthBar.updateBar();
				}
			case "Transition Video":
				if (!Options.lowMemoryMode)
				{
					switch (params[1])
					{
						case 'Appear':
							transitionVideo.play();
							transitionVideo.visible = true;

						case 'Disappear':
							transitionOutVideo.play();
							transitionOutVideo.visible = true;
					}
				}
			case "Spots":
				switch (params[1])
				{
					case 'Appear':
						if (!Options.lowMemoryMode)
						{
							FlxTween.tween(spotsBack, {alpha: 0.25}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadOut});
							FlxTween.tween(spotsFront, {alpha: 0.5}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadOut});
						}

						if (Options.gameplayShaders)
						{
							FlxTween.num(0.0, -0.10, Conductor.stepCrochet * params[2] / 1000, {
								ease: FlxEase.quadInOut
							}, function(num:Float)
							{
								bloomShader.amt = num;
							});
						}

					case 'Disappear':
						if (!Options.lowMemoryMode)
						{
							FlxTween.tween(spotsBack, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadIn});
							FlxTween.tween(spotsFront, {alpha: 0.0}, Conductor.stepCrochet * params[2] / 1000, {ease: FlxEase.quadOut});
						}

						if (Options.gameplayShaders)
						{
							FlxTween.num(-0.10, 0.0, Conductor.stepCrochet * params[2] / 1000, {
								ease: FlxEase.quadInOut
							}, function(num:Float)
							{
								bloomShader.amt = num;
							});
						}
				}
			case "Logo":
				switch (params[1])
				{
					case 'Show':
						FlxTween.tween(logo, {alpha: 1.0}, Conductor.stepCrochet * 32 / 1000, {ease: FlxEase.quadOut});

					case 'Hide':
						logo.alpha = 0.0;
				}
		}
	}
}

function onGamePause(e)
{
	if (!Options.lowMemoryMode)
	{
		if (transitionVideo.visible)
			transitionVideo.pause();
		if (transitionOutVideo.visible)
			transitionOutVideo.pause();
	}
}

function onSubstateClose(e)
{
	if (paused)
	{
		if (!Options.lowMemoryMode)
		{
			if (transitionVideo.visible)
				transitionVideo.resume();
			if (transitionOutVideo.visible)
				transitionOutVideo.resume();
		}
	}
}

function updateStrumSkin(strumTarget:Strum, useOG:Bool)
{
	if (useOG)
	{
		var dirs:Array<String> = ['left', 'down', 'up', 'right', 'left', 'down'];

		strumTarget.frames = Paths.getSparrowAtlas('game/notes/og');
		strumTarget.animation.addByPrefix('static', 'arrow' + dirs[strumTarget.ID].toUpperCase());
		strumTarget.animation.addByPrefix('pressed', '${dirs[strumTarget.ID]} press', 24, false);
		strumTarget.animation.addByPrefix('confirm', '${dirs[strumTarget.ID]} confirm', 24, false);
		strumTarget.playAnim('static', true);
		strumTarget.x -= 15;
	}
	else
	{
		var dirs:Array<String> = ['left', 'down', 'up', 'right', 'left', 'down'];

		strumTarget.frames = Paths.getSparrowAtlas('game/notes/default');
		strumTarget.animation.addByPrefix('static', 'arrow' + dirs[strumTarget.ID].toUpperCase());
		strumTarget.animation.addByPrefix('pressed', '${dirs[strumTarget.ID]} press', 24, false);
		strumTarget.animation.addByPrefix('confirm', '${dirs[strumTarget.ID]} confirm', 24, false);
		strumTarget.updateHitbox();
		strumTarget.playAnim('static', true);
		strumTarget.x += 15;
	}
}

function onNoteCreation(e)
{
	if (e.note.strumTime >= Conductor.stepCrochet * 527 && e.note.strumTime <= Conductor.stepCrochet * 783)
	{
		e.noteSprite = 'game/notes/og';
		e.note.splash = 'og';
		if (Options.downscroll)
			e.note.gapFix = -150;
	}
}
