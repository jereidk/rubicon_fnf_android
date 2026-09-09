import util.GenUtil;
import flixel.addons.display.FlxBackdrop;
import flixel.math.FlxRect;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxTextAlign;
import funkin.options.OptionsMenu;
import openfl.display.BlendMode;
import haxe.Json;
import sys.io.File;
import ui.LogEntryUI;

// i wanna rewrite this entire thing but i dont wanna delay the mod anymore :/

var canControl:Bool = true;
var portraits:Array<Portrait> = [];
var dialogueBox:FunkinSprite;
var dialogueJson:String = '';
var dialogues = [];
var finishedTyping:Bool = false;
var dontAllowSkip:Bool = false;
var inLog:Bool = false;
var logTexts:String = '';
var outfitPrefix:String = '';
var mechVideo:FlxVideoSprite;
var showMechanicVideo:Bool = false;
var vidLoopPoint:Int = 0;
var showingVideo:Bool = false;
var logEntries:Array<LogEntry> = [];
var currentEntry:Int = 0;
var overlay:FlxSprite;

FlxG.sound.load(Paths.sound("game/dialogue/next"));
function create()
{
	camera = dialogueCam = new FlxCamera();
	dialogueCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(dialogueCam, false);

	portraitsCam = dialogueCam = new FlxCamera();
	portraitsCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(portraitsCam, false);

	camUI = dialogueCam = new FlxCamera();
	camUI.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(camUI, false);

	overlayCam = new FlxCamera();
	overlayCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(overlayCam, false);

	logCam = new FlxCamera();
	logCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(logCam, false);

	dialogueJson = Json.parse(Assets.getText(Paths.dialogue(PlayState.SONG.meta.name)));

	var translatedName:String = PlayState.SONG.meta.displayName;
	if (PlayState.SONG.meta.name == 'eternalstar')
		translatedName = 'EternalStar';

	for (i in 0...dialogueJson.dialogue.length)
	{
		var messageData = {
			name: dialogueJson.dialogue[i].name,
			expression: dialogueJson.dialogue[i].expression,
			text: i18n.tr('Dialogue/${translatedName}/${dialogueJson.dialogue[i].dialogue}'),
			action: dialogueJson.dialogue[i].action,
			params: dialogueJson.dialogue[i].params
		}
		dialogues.push(messageData);
	}

	if (PlayState.SONG.meta.name == 'partea')
		outfitPrefix = '-casual';

	switch (PlayState.SONG.meta.name)
	{
		case "resonance":
			PlayState.instance.graphicCache.cache(Paths.image("game/dialogue/screens/res_gertrud"));
			PlayState.instance.graphicCache.cache(Paths.image("game/dialogue/screens/res_gertrud_ow"));
		case "vexation":
			showMechanicVideo = true;

			FlxG.sound.load(Paths.sound("videos/kyoko_mechscreen"));
			mechVideo = new FlxVideoSprite(0, 0);
			mechVideo.antialiasing = true;
			mechVideo.bitmap.onFormatSetup.add(function():Void
			{
				if (mechVideo.bitmap != null && mechVideo.bitmap.bitmapData != null)
				{
					final scale:Float = Math.min((FlxG.width / mechVideo.bitmap.bitmapData.width) * 1.0,
						(FlxG.height / mechVideo.bitmap.bitmapData.height) * 1.0);

					mechVideo.setGraphicSize(mechVideo.bitmap.bitmapData.width * scale, mechVideo.bitmap.bitmapData.height * scale);
					mechVideo.updateHitbox();
					mechVideo.screenCenter();
				}
			});
			mechVideo.load(Paths.video("kyoko_mech"));
			mechVideo.bitmap.onEndReached.add(() ->
			{
				mechVideo.stop();
				mechVideo.play();
				mechVideo.bitmap.time = 3937;
				mechVideoAudio.play();
				mechVideoAudio.time = 3937;
			});

			mechVideoAudio = new FlxSound().loadEmbedded(Paths.sound('videos/kyoko_mechscreen'));
			mechVideoAudio.volume = 0.75;
			FlxG.sound.list.add(mechVideoAudio);
		case "out-of-time":
			showMechanicVideo = true;

			FlxG.sound.load(Paths.sound("videos/kyoko_mechscreen"));
			mechVideo = new FlxVideoSprite(0, 0);
			mechVideo.antialiasing = true;
			mechVideo.bitmap.onFormatSetup.add(function():Void
			{
				if (mechVideo.bitmap != null && mechVideo.bitmap.bitmapData != null)
				{
					final scale:Float = Math.min((FlxG.width / mechVideo.bitmap.bitmapData.width) * 1.0,
						(FlxG.height / mechVideo.bitmap.bitmapData.height) * 1.0);

					mechVideo.setGraphicSize(mechVideo.bitmap.bitmapData.width * scale, mechVideo.bitmap.bitmapData.height * scale);
					mechVideo.updateHitbox();
					mechVideo.screenCenter();
				}
			});
			mechVideo.load(Paths.video("homura_mechscreen"));
			mechVideo.bitmap.onEndReached.add(() ->
			{
				mechVideo.stop();
				mechVideo.play();
				mechVideo.bitmap.time = 2300;
				mechVideoAudio.play();
				mechVideoAudio.time = 2300;
			});

			mechVideoAudio = new FlxSound().loadEmbedded(Paths.sound('videos/homura_mechscreen'));
			mechVideoAudio.volume = 0.75;
			FlxG.sound.list.add(mechVideoAudio);
	}

	if (Options.gameplayShaders)
	{
		boilIntroShader = new CustomShader('wave');
		boilIntroShader.strength = 0.25;
		boilIntroShader.speed = 5.0;
	}

	dialogueMusic = new FlxSound();
	dialogueMusic.loadEmbedded(Paths.music('dialogue-${PlayState.SONG.meta.name}'), true, true);
	dialogueMusic.volume = 0.75;
	dialogueMusic.fadeIn(1.0, 0.0, 0.75);
	FlxG.sound.list.add(dialogueMusic);

	bg = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	bg.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(bg);
	bg.alpha = 1.0;

	background = new FunkinSprite(0, 0);
	background.loadSprite(Paths.image('ui/freeplay/backgrounds/${PlayState.SONG.meta.name}'));
	background.scale.set(1.5, 1.5);
	add(background);
	background.screenCenter();

	diamondBG = new FlxBackdrop(Paths.image('game/dialogue/bgscroll'), FlxAxes.XY, 0, 0);
	diamondBG.alpha = 0.25;
	add(diamondBG);
	diamondBG.velocity.set(15, 15);

	// Resonance
	labyrinth = new FunkinSprite(0, 0);
	labyrinth.loadSprite(Paths.image('game/dialogue/screens/labyrinth'));
	add(labyrinth);
	labyrinth.screenCenter();
	labyrinth.scale.set(1.15, 1.15);
	labyrinth.alpha = 0.0;
	if (Options.gameplayShaders)
		labyrinth.shader = boilIntroShader;

	witches = new FunkinSprite(0, 0);
	witches.loadSprite(Paths.image('game/dialogue/screens/witches'));
	add(witches);
	witches.screenCenter();
	witches.scale.set(1.25, 1.25);
	witches.alpha = 0.0;
	if (Options.gameplayShaders)
		witches.shader = boilIntroShader;

	griefseed = new FunkinSprite(0, 0);
	griefseed.loadSprite(Paths.image('game/dialogue/screens/griefseed'));
	add(griefseed);
	griefseed.screenCenter();
	griefseed.x -= 50;
	griefseed.scale.set(1.1, 1.1);
	griefseed.alpha = 0.0;
	if (Options.gameplayShaders)
		griefseed.shader = boilIntroShader;

	magicalgirls = new FunkinSprite(0, 0);
	magicalgirls.loadSprite(Paths.image('game/dialogue/screens/magicalgirls'));
	add(magicalgirls);
	magicalgirls.screenCenter();
	magicalgirls.scale.set(1.25, 1.25);
	magicalgirls.alpha = 0.0;
	magicalgirls.x -= 75;
	magicalgirls.y -= 75;
	if (Options.gameplayShaders)
		magicalgirls.shader = boilIntroShader;

	gertrudGraphic = new FunkinSprite(0, 0);
	gertrudGraphic.loadSprite(Paths.image('game/dialogue/screens/res_gertrud'));
	add(gertrudGraphic);
	gertrudGraphic.screenCenter();
	gertrudGraphic.alpha = 0.0;

	cutsceneGraphic = new FunkinSprite(0, 0);
	cutsceneGraphic.loadSprite(Paths.image('ui/freeplay/backgrounds/${PlayState.SONG.meta.name}'));
	add(cutsceneGraphic);
	cutsceneGraphic.screenCenter();
	cutsceneGraphic.alpha = 0.0;

	dialogueBox = new FunkinSprite(100, 700);
	dialogueBox.loadSprite(Paths.image("game/dialogue/dialoguebox-none"));
	add(dialogueBox);
	dialogueBox.cameras = [camUI];
	dialogueBox.color = FlxColor.BLACK;
	dialogueBox.alpha = 0.25;

	btnLog = new FunkinSprite(dialogueBox.x, dialogueBox.y + 325);
	btnLog.loadSprite(Paths.image("game/dialogue/info"));
	add(btnLog);
	btnLog.x = dialogueBox.x + dialogueBox.width / 2 - btnLog.width / 2;
	btnLog.cameras = [camUI];

	btnLogText = new FlxText(btnLog.x + 60, btnLog.y + 10, btnLog.width - 100, i18n.tr('Dialogue/Log'));
	btnLogText.setFormat(Paths.font("shingo.otf"), 20, FlxColor.WHITE, FlxTextAlign.CENTER);
	add(btnLogText);
	btnLogText.cameras = [camUI];

	btnLogKeyText = new FlxText(btnLog.x + 10, btnLog.y + 7, 0, 'L');
	btnLogKeyText.setFormat(Paths.font("shingo.otf"), 24, 0xFF0D090D, FlxTextAlign.CENTER);
	add(btnLogKeyText);
	btnLogKeyText.cameras = [camUI];

	btnSkip = new FunkinSprite(dialogueBox.x, dialogueBox.y + 325);
	btnSkip.loadSprite(Paths.image("game/dialogue/info"));
	add(btnSkip);
	btnSkip.x = dialogueBox.x + dialogueBox.width / 2 - btnSkip.width / 2;
	btnSkip.cameras = [camUI];

	btnSkipText = new FlxText(btnSkip.x + 60, btnSkip.y + 10, btnSkip.width - 100, i18n.tr('Dialogue/Skip'));
	btnSkipText.setFormat(Paths.font("shingo.otf"), 20, FlxColor.WHITE, FlxTextAlign.CENTER);
	add(btnSkipText);
	btnSkipText.cameras = [camUI];

	btnSkipKeyText = new FlxText(btnSkip.x + 10, btnSkip.y + 7, 0, 'K');
	btnSkipKeyText.setFormat(Paths.font("shingo.otf"), 24, 0xFF0D090D, FlxTextAlign.CENTER);
	add(btnSkipKeyText);
	btnSkipKeyText.cameras = [camUI];

	for (spr in [btnLog, btnLogText, btnLogKeyText])
		spr.x -= 200;
	for (spr in [btnSkip, btnSkipText, btnSkipKeyText])
		spr.x += 200;

	dialogueText = new FlxTypeText(dialogueBox.x + 50, dialogueBox.y + 50, dialogueBox.width - 100, "");
	dialogueText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	dialogueText.borderSize = 3.0;
	add(dialogueText);
	dialogueText.completeCallback = () -> finishTyping();
	dialogueText.cameras = [camUI];

	speakerText = new FlxText(dialogueBox.x, dialogueBox.y - 25, dialogueBox.width, '');
	speakerText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	speakerText.borderSize = 3.0;
	add(speakerText);
	speakerText.cameras = [camUI];
	speakerText.alpha = 0.0;

	speakerTextBackdrop = new FlxText(dialogueBox.x, dialogueBox.y - 20, dialogueBox.width, '');
	speakerTextBackdrop.setFormat(Paths.font("shingo.otf"), 42, 0xFF000000, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF000000);
	speakerTextBackdrop.borderSize = 3.0;
	insert(members.indexOf(speakerText), speakerTextBackdrop);
	speakerTextBackdrop.cameras = [camUI];
	speakerTextBackdrop.alpha = 0.0;

	speakerTextBG = new FunkinSprite();
	speakerTextBG.loadSprite(Paths.image("game/dialogue/namebgfade"));
	insert(members.indexOf(dialogueText), speakerTextBG);
	speakerTextBG.setPosition(speakerText.x
		+ speakerText.width / 2
		- speakerTextBG.width / 2,
		speakerText.y
		+ speakerText.height / 2
		- speakerTextBG.height / 2);
	speakerTextBG.scale.set(15, 1);
	speakerTextBG.cameras = [camUI];
	speakerTextBG.alpha = 0.0;

	for (spr in [speakerTextBG, speakerText, speakerTextBackdrop])
	{
		spr.x -= 50;
	}

	nextArrow = new FunkinSprite(dialogueText.x + dialogueText.width - 50, dialogueText.y + dialogueText.height + 125);
	nextArrow.loadSprite(Paths.image("game/dialogue/nextarrow"));
	add(nextArrow);
	nextArrow.alpha = 0.0;
	nextArrow.cameras = [camUI];

	gfLine1 = new FunkinSprite(1425, 875);
	gfLine1.loadSprite(Paths.image("game/dialogue/gflinebehind"));
	add(gfLine1);
	gfLine1.cameras = [camUI];

	gfPortrait = new GFPortrait();
	add(gfPortrait);
	gfPortrait.cameras = [camUI];

	gfLine2 = new FunkinSprite(1425, 875);
	gfLine2.loadSprite(Paths.image("game/dialogue/gfportraitoutline"));
	add(gfLine2);
	gfLine2.cameras = [camUI];

	for (spr in [background, diamondBG, gfLine1, gfPortrait, gfLine2])
		spr.alpha = 0.0;

	for (spr in [
		gfLine1,
		gfPortrait,
		gfLine2,
		dialogueBox,
		dialogueText,
		nextArrow,
		btnLog,
		btnLogText,
		btnLogKeyText,
		btnSkip,
		btnSkipText,
		btnSkipKeyText
	])
		spr.x += 200;

	dialogueText.start(0.02);
	progressDialogue();

	if (showMechanicVideo)
		add(mechVideo).cameras = [overlayCam];

	overlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	overlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(overlay);
	overlay.cameras = [camUI];
	overlay.alpha = 0.0;

	for (i in 0...dialogueJson.dialogue.length)
	{
		entryLog = new LogEntryUI(dialogueJson.dialogue[i], i);
		add(entryLog);
		logEntries.push(entryLog);

		entryLog.group.cameras = [logCam];
		// entryLog.group.setPosition(0, 150 + (i * 200));
		entryLog.group.screenCenter(FlxAxes.X);

		entryLog.visible = false;
	}

	helpTxt = new FlxText(15, 15, FlxG.width, i18n.tr('Dialogue/LogHelp'));
	helpTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	helpTxt.borderSize = 3.0;
	add(helpTxt);
	helpTxt.cameras = [camUI];
	helpTxt.alpha = 0.0;
}

function postCreate()
{
	new FlxTimer().start(0.05, function(tmr:FlxTimer)
	{
		if (FlxG.keys.pressed.K && !inLog && !dontAllowSkip)
		{
			FlxG.sound.play(Paths.sound("game/dialogue/next"), 0.5 * Options.volumeSFX);
			progressDialogue();
			dialogueText.skip();
		}
	}, 0);
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;

	if (controls.ACCEPT && !inLog && !dontAllowSkip)
	{
		if (finishedTyping)
		{
			FlxG.sound.play(Paths.sound("game/dialogue/next"), 0.5 * Options.volumeSFX);
			progressDialogue();
		}
		else
		{
			finishedTyping = true;
			dialogueText.skip();
		}
	}

	if (FlxG.keys.justPressed.L && !inLog && !dontAllowSkip)
	{
		logCam.scroll.y = 0;
		inLog = true;
		helpTxt.alpha = 1.0;
		checkLog();
	}

	if (controls.BACK && inLog && !dontAllowSkip)
	{
		inLog = false;
		overlay.alpha = 0.0;
		helpTxt.alpha = 0.0;
		for (i in 0...logEntries.length)
		{
			logEntries[i].visible = false;
		}
	}

	if (controls.UP && inLog)
	{
		logCam.scroll.y = FlxMath.bound(logCam.scroll.y - (1000 * elapsed), 0, 200 * (FlxMath.bound(currentEntry - 4, 0, 999)));
	}
	if (controls.DOWN && inLog)
	{
		logCam.scroll.y = FlxMath.bound(logCam.scroll.y + (1000 * elapsed), 0, 200 * (FlxMath.bound(currentEntry - 4, 0, 999)));
	}

	if (controls.ACCEPT && showingVideo && showMechanicVideo)
	{
		endMechanicVideo();
	}

	if (FlxMath.roundDecimal(totalElapsed % 0.30, 2) == 0 && Options.gameplayShaders)
	{
		boilIntroShader.time = FlxG.random.int(0, 2500);
	}
}

function switchToNormal(?quick:Bool = false)
{
	var time:Float = 1.0;
	if (quick)
		time = 0.0001;

	var targetAlpha:Float = 1.0;
	for (spr in [background, speakerText, gfLine1, gfPortrait, gfLine2, diamondBG, dialogueBox])
	{
		FlxTween.cancelTweensOf(spr, ['alpha']);
		FlxTween.tween(spr, {alpha: 1.0}, time, {ease: FlxEase.expoOut});
	}
	FlxTween.tween(diamondBG, {alpha: 0.25}, time, {ease: FlxEase.expoOut});

	dialogueBox.color = FlxColor.BLACK;
	FlxTween.color(dialogueBox, time, dialogueBox.color, FlxColor.WHITE, {ease: FlxEase.expoOut});
	FlxTween.color(dialogueText, time, dialogueText.color, 0xFF0D090D, {ease: FlxEase.expoOut});

	FlxTween.tween(cutsceneGraphic, {alpha: 0.0}, time, {ease: FlxEase.expoOut});

	for (spr in [
		gfLine1,
		gfPortrait,
		gfLine2,
		dialogueBox,
		dialogueText,
		nextArrow,
		btnLog,
		btnLogText,
		btnLogKeyText,
		speakerText,
		speakerTextBackdrop,
		speakerTextBG,
		btnSkip,
		btnSkipText,
		btnSkipKeyText
	])
		FlxTween.tween(spr, {x: spr.x - 250}, time, {ease: FlxEase.expoOut});

	dialogueText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.LEFT);
}

function finishTyping()
{
	if (!dontAllowSkip)
	{
		nextArrow.alpha = 1.0;

		gfPortrait.animation.curAnim.looped = false;

		for (portrait in portraits)
			portrait.animation.curAnim.looped = false;

		finishedTyping = true;
	}
}

function progressDialogue()
{
	nextArrow.alpha = 0.0;

	if (dialogues.length > 0)
	{
		finishedTyping = false;
		curDialogue = dialogues[0];

		switch (curDialogue.action)
		{
			case 'gotonormal':
				switchToNormal(false);

			case 'gotonormalintro':
				switchToNormal(true);

			case 'witches':
				FlxTween.tween(witches, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, 2.0, {ease: FlxEase.quadOut});
				FlxTween.tween(labyrinth, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, 2.0, {ease: FlxEase.quadOut, startDelay: 1.8});

			case 'griefseed':
				for (spr in [witches, labyrinth])
				{
					FlxTween.cancelTweensOf(spr);
					spr.alpha = 1.0;
					spr.scale.set(1.0, 1.0);
				}

				FlxTween.tween(witches, {alpha: 0.0, 'scale.x': 0.95, 'scale.y': 0.95}, 1.0, {ease: FlxEase.quadIn});
				FlxTween.tween(labyrinth, {alpha: 0.0, 'scale.x': 0.95, 'scale.y': 0.95}, 1.0, {ease: FlxEase.quadIn});
				FlxTween.tween(griefseed, {
					y: griefseed.y - 25,
					alpha: 1.0,
					'scale.x': 1.0,
					'scale.y': 1.0
				}, 2.0, {ease: FlxEase.quadOut, startDelay: 0.0});

			case 'magicalgirls':
				FlxTween.cancelTweensOf(griefseed);

				gertrudGraphic.scale.x = 1.1;
				gertrudGraphic.scale.y = 1.1;
				FlxTween.tween(gertrudGraphic, {'scale.x': 1.0, 'scale.y': 1.0, alpha: 1.0}, 3.0, {ease: FlxEase.quadOut, startDelay: 2.5});

				FlxTween.tween(magicalgirls, {alpha: 1.0, 'scale.x': 1.0, 'scale.y': 1.0}, 2.0, {ease: FlxEase.quadOut});
				FlxTween.tween(magicalgirls, {y: magicalgirls.y + 50}, 2.0, {ease: FlxEase.quadOut});
				FlxTween.tween(griefseed, {
					alpha: 0.0
				}, 1.0, {ease: FlxEase.quadOut});

			case 'graphic':
				cutsceneGraphic.loadSprite(Paths.image('game/dialogue/screens/${curDialogue.params[0]}'));
				cutsceneGraphic.alpha = 0.0;
				cutsceneGraphic.screenCenter();

				switch (curDialogue.params[1])
				{
					case 'fadein':
						FlxTween.tween(cutsceneGraphic, {alpha: 1.0}, 1.0, {ease: FlxEase.quadInOut});
					case 'shake':
						cutsceneGraphic.alpha = 1.0;
						cutsceneGraphic.scale.set(1.1, 1.1);
						FlxTween.tween(cutsceneGraphic, {'scale.x': 1.0, 'scale.y': 1.0}, 1.0, {ease: FlxEase.expoOut});
						FlxTween.num(15, 0.0, 1.5, {ease: FlxEase.expoOut}, function(num:Float)
						{
							var randomizedXpos:Float = FlxG.random.float(-num, num);
							var randomizedYPos:Float = FlxG.random.float(-num, num);
							cutsceneGraphic.offset.x = cutsceneGraphic.x + randomizedXpos;
							cutsceneGraphic.offset.y = cutsceneGraphic.y + randomizedYPos;
						});
				}

				if (curDialogue.params[0] == 'res_gertrud_ow')
				{
					gertrudGraphic.visible = false;
					magicalgirls.visible = false;
					witches.visible = false;
					labyrinth.visible = false;
				}

			case 'fadeout':
				dontAllowSkip = true;

				for (spr in [
					dialogueBox,
					dialogueText,
					speakerTextBG,
					speakerText,
					speakerTextBackdrop,
					btnLog,
					btnLogText,
					btnLogKeyText,
					btnSkip,
					btnSkipText,
					btnSkipKeyText
				])
				{
					spr.visible = false;
				}

				for (spr in [witches, labyrinth, magicalgirls, griefseed, cutsceneGraphic])
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 0.0}, 1.0, {ease: FlxEase.quadInOut});
				}

				new FlxTimer().start(curDialogue.params[0], function(tmr:FlxTimer)
				{
					dontAllowSkip = false;
					progressDialogue();
				});

			case 'fadein':
				dontAllowSkip = true;

				new FlxTimer().start(curDialogue.params[0], function(tmr:FlxTimer)
				{
					dontAllowSkip = false;
					progressDialogue();

					for (spr in [
						dialogueBox,
						dialogueText,
						speakerTextBG,
						speakerText,
						speakerTextBackdrop,
						btnLog,
						btnLogText,
						btnLogKeyText,
						btnSkip,
						btnSkipText,
						btnSkipKeyText
					])
					{
						spr.visible = true;
					}
				});

			case 'unshilo':
				for (portrait in portraits)
					portrait.shilo = false;
		}

		if (curDialogue.action != 'fadein' && curDialogue.action != 'fadeout')
		{
			currentEntry += 1;

			var pushPortrait:Bool = true;
			for (portrait in portraits)
			{
				if (portrait.name == curDialogue.name)
					pushPortrait = false;
			}
			if (pushPortrait && curDialogue.name != 'girlfriend' && curDialogue.name != '')
				adjustPortrait('add', curDialogue.name, null);

			dialogueText.resetText(curDialogue.text);
			dialogueText.start(0.015);
			updateSpeakerText(curDialogue.name);
			adjustPortrait('light', curDialogue.name, null);
			adjustPortrait('expression', curDialogue.name, curDialogue.expression);

			if (curDialogue.action == 'overwritename')
			{
				curDialogue.name = '???';
				updateSpeakerText('unknown');
			}
		}
	}

	if (dialogues.length <= 0)
	{
		dontAllowSkip = true;
		canControl = false;
		dialogueMusic.fadeOut(2.5, 0.0);
		fadeoutSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
		fadeoutSprite.scale.set(FlxG.width * 2, FlxG.height * 2);
		add(fadeoutSprite).cameras = [overlayCam];
		fadeoutSprite.alpha = 0.0;

		FlxTween.tween(fadeoutSprite, {alpha: 1.0}, 2.0, {
			ease: FlxEase.quadInOut,
			startDelay: 0.75,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(0.5, function(tmr:FlxTimer)
				{
					if (showMechanicVideo)
					{
						displayMechanicVideo();
					}
					else
					{
						inCutscene = false;
						PlayState.instance.startCountdown();
						close();
					}
				});
			}
		});
	}

	dialogues?.shift();
}

function confirmSelection()
{
	GenUtil.playUISound('confirm');

	canControl = false;
}

function adjustPortrait(action:String, arg1:String, arg2:String)
{
	switch (action)
	{
		case 'add':
			var portrait = new Portrait(arg1, false);
			portrait.position = portraits.length;
			insert(members.indexOf(dialogueBox), portrait);
			portraits.push(portrait);
			portrait.cameras = [portraitsCam];

		case 'light':
			for (portrait in portraits)
			{
				if (portrait.name == arg1)
				{
					portrait.color = portrait.shilo ? FlxColor.BLACK : FlxColor.WHITE;
					FlxTween.cancelTweensOf(portrait, ['scale.x', 'scale.y']);
					portrait.scale.set(1.15, 1.25);
					talkingTween = FlxTween.tween(portrait, {'scale.x': 1.2, 'scale.y': 1.2}, 1.0, {ease: FlxEase.expoOut});
					targetPortrait = portrait;
					targetPortrait.lastTalked = 0;
					if (curDialogue.action != null)
					{
						if (curDialogue.action[0] == 'shake')
							portrait.shaking = true;
					}
				}
				else
				{
					portrait.color = portrait.shilo ? FlxColor.BLACK : FlxColor.GRAY;
					portrait.lastTalked += 1;
					portrait.shaking = false;
				}
			}

			for (i in 0...portraits.length)
			{
				remove(portraits[i]);

				if (portraits[i].name == arg1)
				{
					insert(members.indexOf(dialogueBox), portraits[i]);
				}
				else
				{
					insert(members.indexOf(dialogueBox) - (1 + portraits[i].lastTalked), portraits[i]);
				}
			}

			if (arg1 == 'girlfriend')
			{
				gfPortrait.color = gfPortrait.shilo ? FlxColor.BLACK : FlxColor.WHITE;
				FlxTween.cancelTweensOf(gfPortrait, ['scale.x', 'scale.y']);
				gfPortrait.scale.set(1.15, 1.25);
				gfPortrait.scale.set(1.15, 1.25);
				talkingTween = FlxTween.tween(gfPortrait, {'scale.x': 1.2, 'scale.y': 1.2}, 1.0, {ease: FlxEase.expoOut});
			}
			else
			{
				gfPortrait.color = gfPortrait.shilo ? FlxColor.BLACK : FlxColor.GRAY;
			}

		case 'expression':
			for (portrait in portraits)
			{
				if (portrait.name == arg1)
					portrait.playAnim(arg2);
				// else
				//	portrait.playAnim('normal' + outfitPrefix);
			}

			for (portrait in portraits)
			{
				if (arg1 == 'sayaka' && arg2 == 'yay')
				{
					// FlxTween.cancelTweensOf(portrait, ['y']);
					// FlxTween.tween(portrait, {y: portrait.y - 25}, 1.5, {ease: FlxEase.expoOut, type: FlxTween.PINGPONG});
				}
			}

			if (arg1 == 'girlfriend')
				gfPortrait.playAnim(arg2);
			else
				gfPortrait.playAnim('normal' + outfitPrefix);

			var loopAnim:Bool = true;
			if (arg2 == 'catch' || arg2 == 'ow' || arg2 == 'throw')
				loopAnim = false;

			gfPortrait.animation.curAnim.looped = loopAnim;
			for (portrait in portraits)
				portrait.animation.curAnim.looped = loopAnim;
	}
}

function updateSpeakerText(newSpeaker:String)
{
	switch (newSpeaker)
	{
		case 'girlfriend':
			speakerText.text = 'Girlfriend';
			speakerText.borderColor = 0xFFD00D2B;
			speakerTextBackdrop.color = 0xFF98144F;

		case 'sayaka':
			speakerText.text = 'Sayaka Miki';
			speakerText.borderColor = 0xFF72AEDA;
			speakerTextBackdrop.color = 0xFF465FB0;

		case 'mami':
			speakerText.text = 'Mami Tomoe';
			speakerText.borderColor = 0xFFFFEC76;
			speakerTextBackdrop.color = 0xFFC49544;

		case 'madoka':
			speakerText.text = 'Madoka Kaname';
			speakerText.borderColor = 0xFFFBA8BC;
			speakerTextBackdrop.color = 0xFFA14E8C;

		case 'kyoko':
			speakerText.text = 'Kyoko Sakura';
			speakerText.borderColor = 0xFFA83658;
			speakerTextBackdrop.color = 0xFF75102E;

		case 'homura':
			speakerText.text = 'Homura Akemi';
			speakerText.borderColor = 0xFF3A3A3A;
			speakerTextBackdrop.color = 0xFF262626;

		case 'nagisa':
			speakerText.text = 'Nagisa Momoe';
			speakerText.borderColor = 0xFFFFA6AC;
			speakerTextBackdrop.color = 0xFFE05B70;

		case 'unknown':
			speakerText.text = '???';
			speakerText.borderColor = 0xFF0D090D;
			speakerTextBackdrop.color = 0xFF0D090D;
	}

	speakerTextBackdrop.text = speakerText.text;
	speakerTextBackdrop.borderColor = speakerTextBackdrop.color;
	speakerTextBG.color = speakerTextBackdrop.color;

	if (curDialogue.name != '' && curDialogue.name != null)
	{
		for (spr in [speakerTextBG, speakerTextBackdrop, speakerText])
		{
			FlxTween.cancelTweensOf(spr);
			FlxTween.tween(spr, {alpha: 1.0}, 1.0, {ease: FlxEase.expoOut});
		}
	}
	else
	{
		for (spr in [speakerTextBG, speakerTextBackdrop, speakerText])
		{
			FlxTween.cancelTweensOf(spr);
			FlxTween.tween(spr, {alpha: 0.0}, 1.0, {ease: FlxEase.expoOut});
		}
	}
}

var overlayLogText:FlxText;
var logEntry:Array<LogEntry> = [];

function checkLog()
{
	overlay.alpha = 0.75;

	var dist:Float = 0;
	var distDifferences:Array<Float> = [];

	var whateverman:Int = logEntries.length - 1;

	for (i in 0...logEntries.length)
	{
		var totalDiff:Float = 0;

		logEntries[whateverman - i].group.y = -25 + dist;

		dist += 200;
		totalDiff += 200;

		if (currentEntry - 1 >= i)
		{
			logEntries[i].visible = true;
		}
		else
		{
			logEntries[i].visible = false;
		}

		distDifferences.push(totalDiff);
	}

	for (i in 0...logEntries.length)
	{
		logEntries[i].group.y -= 200 * (whateverman - currentEntry);
	}
}

function displayMechanicVideo()
{
	showingVideo = true;
	mechVideo.play();
	mechVideoAudio.play();
}

function endMechanicVideo()
{
	showingVideo = false;
	GenUtil.playUISound('confirm');
	mechVideo.pause();
	mechVideoAudio.pause();

	FlxTween.tween(mechVideo, {alpha: 0.0}, 2.0, {
		ease: FlxEase.quadInOut,
		onComplete: function(twn:FlxTween)
		{
			new FlxTimer().start(0.5, function(tmr:FlxTimer)
			{
				inCutscene = false;
				PlayState.instance.startCountdown();
				close();
			});
		}
	});
}

class Portrait extends FunkinSprite
{
	var speaking:Bool = false;
	var talkingTween:FlxTween;
	var name:String = '';
	var position:Int = 0;
	var lastTalked:Int = 0;

	var shilo:Bool = false;

	var shaking:Bool = false;
	var originalOffsets:Float<Array> = [];

	public function new(?character:String = '', ?isGirlfriend:Bool = false)
	{
		super();

		name = character;
		isGF = isGirlfriend;

		switch (character)
		{
			case 'sayaka':
				loadSprite(Paths.image("game/dialogue/portraits/sayaka"));
				addAnim('normal', 'sayaka', 8, true, false, [0]);
				addAnim('happy', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("1..3"));
				addAnim('laugh', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("4..6"));
				addAnim('yeah', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("7..9"));
				addAnim('think', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("10..12"));
				addAnim('ehh', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("13..15"));
				addAnim('mic', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("16..18"));
				addAnim('angry', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("19..21"));
				addAnim('pissed', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("22..24"));
				addAnim('yay', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("25..27"));
				addAnim('normal-casual', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("28..28"));
				addAnim('talk-casual', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("29..31"));
				addAnim('joy-casual', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("32..34"));
				addAnim('ehh-casual', 'sayaka', 8, true, false, CoolUtil.parseNumberRange("35..37"));
				playAnim('normal');
				offset.x = 110;
				offset.y = -550;

			case 'madoka':
				loadSprite(Paths.image("game/dialogue/portraits/madoka"));
				addAnim('normal', 'madoka', 8, true, false, [0]);
				addAnim('nervous', 'madoka', 8, true, false, CoolUtil.parseNumberRange("1..3"));
				addAnim('ok', 'madoka', 8, true, false, CoolUtil.parseNumberRange("4..6"));
				addAnim('omg', 'madoka', 8, true, false, CoolUtil.parseNumberRange("7..9"));
				addAnim('what', 'madoka', 8, true, false, CoolUtil.parseNumberRange("10..12"));
				addAnim('mic', 'madoka', 8, true, false, CoolUtil.parseNumberRange("13..15"));
				addAnim('catch', 'madoka', 24, false, false, CoolUtil.parseNumberRange("26..34"));
				addAnim('normal-casual', 'madoka', 8, true, false, [16]);
				addAnim('yay-casual', 'madoka', 8, true, false, CoolUtil.parseNumberRange("17..19"));
				addAnim('ehh-casual', 'madoka', 8, true, false, CoolUtil.parseNumberRange("20..22"));
				addAnim('eating-casual', 'madoka', 8, true, false, CoolUtil.parseNumberRange("23..25"));
				playAnim('normal');
				offset.x = 550;
				offset.y = -550;

			case 'mami':
				loadSprite(Paths.image("game/dialogue/portraits/mami"));
				addAnim('normal', 'mami', 8, true, false, [0]);
				addAnim('shock', 'mami', 8, true, false, CoolUtil.parseNumberRange("1..3"));
				addAnim('hmm', 'mami', 8, true, false, CoolUtil.parseNumberRange("4..7"));
				addAnim('intro', 'mami', 8, true, false, CoolUtil.parseNumberRange("8..10"));
				addAnim('yes', 'mami', 8, true, false, CoolUtil.parseNumberRange("11..13"));
				addAnim('ehh', 'mami', 8, true, false, CoolUtil.parseNumberRange("14..16"));
				addAnim('normal-casual', 'mami', 8, true, false, [17]);
				addAnim('mic-casual', 'mami', 8, true, false, CoolUtil.parseNumberRange("18..20"));
				addAnim('think-casual', 'mami', 8, true, false, CoolUtil.parseNumberRange("21..23"));
				addAnim('ehh-casual', 'mami', 8, true, false, CoolUtil.parseNumberRange("24..26"));
				addAnim('talk-casual', 'mami', 8, true, false, CoolUtil.parseNumberRange("27..29"));
				addAnim('food-casual', 'mami', 8, true, false, CoolUtil.parseNumberRange("30..32"));
				playAnim('normal');
				offset.x = 1000;
				offset.y = -525;

			case 'kyoko':
				loadSprite(Paths.image("game/dialogue/portraits/kyoko"));
				addAnim('normal', 'kyoko', 8, true, false, [0]);
				addAnim('talk', 'kyoko', 8, true, false, CoolUtil.parseNumberRange("1..3"));
				addAnim('down', 'kyoko', 8, true, false, CoolUtil.parseNumberRange("4..6"));
				addAnim('fist', 'kyoko', 8, true, false, CoolUtil.parseNumberRange("7..9"));
				addAnim('annoyed', 'kyoko', 8, true, false, CoolUtil.parseNumberRange("10..12"));
				playAnim('normal');
				offset.x = 100;
				offset.y = 50;
				shilo = true;

			case 'homura':
				loadSprite(Paths.image("game/dialogue/portraits/homura"));
				addAnim('normal', 'homura', 8, true, false, [0]);
				addAnim('cross', 'homura', 8, true, false, CoolUtil.parseNumberRange("1..3"));
				addAnim('annoyed', 'homura', 8, true, false, CoolUtil.parseNumberRange("4..6"));
				addAnim('looking', 'homura', 8, true, false, CoolUtil.parseNumberRange("7..9"));
				addAnim('point', 'homura', 8, true, false, CoolUtil.parseNumberRange("10..12"));
				addAnim('awkward', 'homura', 8, true, false, CoolUtil.parseNumberRange("13..15"));
				addAnim('micstare', 'homura', 8, true, false, [16]);
				addAnim('mic', 'homura', 8, true, false, CoolUtil.parseNumberRange("17..19"));
				addAnim('gun', 'homura', 8, true, false, CoolUtil.parseNumberRange("20..22"));
				playAnim('normal');
				offset.x = 525;
				offset.y = 100;

			case 'nagisa':
				loadSprite(Paths.image("game/dialogue/portraits/nagisa"));
				addAnim('normal', 'nagisa', 8, true, false, [0]);
				addAnim('normal-casual', 'nagisa', 8, true, false, [0]);
				addAnim('yay', 'nagisa', 8, true, false, [1]);
				addAnim('think', 'nagisa', 8, true, false, CoolUtil.parseNumberRange("2..5"));
				addAnim('twiddle', 'nagisa', 8, true, false, [6]);
				addAnim('excited', 'nagisa', 8, true, false, CoolUtil.parseNumberRange("7..9"));
				playAnim('normal');
				offset.x = 950;
				offset.y = 130;
		}

		originalOffsets = [offset.x, offset.y];
		scale.set(1.2, 1.2);

		if (!isGF)
		{
			origin.x = width / 4;
			origin.y = height;
			alpha = 0.0;
			y += 1075;
			FlxTween.tween(this, {y: y - 100, alpha: 1.0}, 0.75, {ease: FlxEase.expoOut});
		}

		if (Options.gameplayShaders)
		{
			boilShader = new CustomShader('wave');
			boilShader.strength = 0.15;
			boilShader.speed = 5.0;
			shader = boilShader;
		}
	}

	var totalElapsed:Float = 0.0;

	override function update(elapsed)
	{
		super.update(elapsed);

		if (shaking)
		{
			offset.x = originalOffsets[0] + FlxG.random.int(-5, 5);
			offset.y = originalOffsets[1] + FlxG.random.int(-5, 5);
		}
		else
		{
			offset.x = originalOffsets[0];
			offset.y = originalOffsets[1];
		}

		if (FlxMath.roundDecimal(totalElapsed % 0.30, 2) == 0 && Options.gameplayShaders)
		{
			boilShader.time = totalElapsed;
		}

		if (!isGF)
		{
			switch (portraits.length)
			{
				case 1:
					if (position == 0)
						x = CoolUtil.fpsLerp(x, -40, 0.1);
				case 2:
					if (position == 0)
						x = CoolUtil.fpsLerp(x, 20 - 250, 0.1);
					if (position == 1)
						x = CoolUtil.fpsLerp(x, -40 + 250, 0.1);
				case 3:
					if (position == 0)
						x = CoolUtil.fpsLerp(x, 20 - 350, 0.1);
					if (position == 1)
						x = CoolUtil.fpsLerp(x, -40 + 350, 0.1);
					if (position == 2)
						x = CoolUtil.fpsLerp(x, -40, 0.1);
				case 4:
					if (position == 0)
						x = CoolUtil.fpsLerp(x, 20 - 500, 0.1);
					if (position == 1)
						x = CoolUtil.fpsLerp(x, -120 + 500, 0.1);
					if (position == 2)
						x = CoolUtil.fpsLerp(x, -40 - 150, 0.1);
					if (position == 3)
						x = CoolUtil.fpsLerp(x, -40 + 150, 0.1);
			}
		}

		totalElapsed += elapsed;
	}
}

function destroy()
{
	dialogueMusic.stop();
}

class GFPortrait extends Portrait
{
	public function new()
	{
		super('girlfriend', true);

		loadSprite(Paths.image("game/dialogue/portraits/girlfriend"));
		addAnim('normal', 'GirlfriendF/gf', 8, true, false, [0]);
		addAnim('talk', 'GirlfriendF/gf', 8, true, false, CoolUtil.parseNumberRange("1..3"));
		addAnim('duh', 'GirlfriendF/gf', 8, true, false, [4]);
		addAnim('mic', 'GirlfriendF/gf', 8, true, false, [5]);
		addAnim('uhh', 'GirlfriendF/gf', 8, true, false, [6]);
		addAnim('stupid', 'GirlfriendF/gf', 8, true, false, [7]);
		addAnim('stress', 'GirlfriendF/gf', 8, true, false, CoolUtil.parseNumberRange("8..10"));
		addAnim('owo', 'GirlfriendF/gf', 8, true, false, [11]);
		addAnim('ow', 'GirlfriendF/gf', 24, false, false, CoolUtil.parseNumberRange("12..13"));
		addAnim('normal-casual', 'GirlfriendF/gf', 8, true, false, [14]);
		addAnim('mic-casual', 'GirlfriendF/gf', 8, true, false, [15]);
		addAnim('smile-casual', 'GirlfriendF/gf', 8, true, false, [16]);
		addAnim('woah-casual', 'GirlfriendF/gf', 8, true, false, [17]);
		addAnim('eating-casual', 'GirlfriendF/gf', 8, true, false, [18]);
		addAnim('yes-casual', 'GirlfriendF/gf', 8, true, false, [19]);
		addAnim('throw', 'GirlfriendF/gf', 24, false, false, CoolUtil.parseNumberRange("20..30"));
		playAnim('normal');
		offset.x = 1450;
		offset.y = -100;

		originalOffsets = [offset.x, offset.y];

		x = 970;
		y = 1260;

		origin.x = width / 4;
		origin.y = height;
	}
}
