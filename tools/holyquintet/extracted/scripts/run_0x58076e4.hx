import ui.SongInfoUI;
import flixel.addons.display.FlxBackdrop;
import funkin.menus.FreeplayState.FreeplaySonglist;
import funkin.savedata.FunkinSave;
import openfl.display.BlendMode;
import util.GenUtil;
import funkin.backend.utils.DiscordUtil;
import gamejolt.GameJolt;
import gamejolt.GJRequest;
import gamejolt.types.RequestType;
import openfl.display.BitmapData;
import BlurFilter;

public static var fp_curSel:Int = 0;
var canControl:Bool = true;
var songData:FreeplaySonglist;
var songs:FreeplaySonglist;
var curSong:Null<ChartMetaData>;
var portrait:FunkinSprite;
var songInfos:Array<SongInfoUI> = [];
var scroll_OffsetX:Float = 0;
var scroll_OffsetY:Float = 0;
var songInfos_OriginalX:Array<Float> = [];
var songInfos_OriginalY:Array<Float> = [];
var scroll_Tweens:Array<FlxTween> = [];
var confirmingSong:Bool = false;
var transTweens:Array<FlxTween> = [];
var transSounds:Array<FlxSound> = [];
var diffTweens:Array<FlxTween> = [];
public static var curDiff:Int = 1;
var diffName:String = 'hard';
var backgrounds:Array<String> = [];
var unlockingSong:Bool = false;
var onLocked:Bool = false;
var onUnlockable:Bool = false;
var currentSongInfo:SongInfoUI;

// leaderboard
var blur:BlurFilter;
var lbuiCam:FlxCamera;
var leaderboardstuff:Array<Dynamic> = [];
var lbgroup:FlxSpriteGroup;
var lbData:Dynamic;
var profilePictures:Array<FunkinSprite> = [];
var gjlbids:Array<Dynamic> = [];
var gjlbdata:Dynamic;
var inLeaderBoards:Bool = false;
var randomizing:Bool = false;
var loadedLeaderboards:Bool = false;

FlxG.sound.load(Paths.sound('ui/freeplay/diff_easy'));
FlxG.sound.load(Paths.sound('ui/freeplay/diff_hard'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_add'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_base'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca_vo1'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca_vo2'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca_vo3'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca_vo4'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_meguca_vo5'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_reconnect'));
FlxG.sound.load(Paths.sound('ui/freeplay/fp_out-of-time'));
FlxG.sound.load(Paths.sound('ui/freeplay/lock_break'));
function create()
{
	DiscordUtil.changePresenceSince("In Freeplay", null);
	CoolUtil.playMenuSong(true);

	songData = FreeplaySonglist.get();
	songs = songData.songs;

	// im lazy idgaf rn
	blur = new BlurFilter(0.0);
	for (cam in FlxG.cameras.list)
	{
		if (cam != lbuiCam)
			blur.apply(cam);
	}

	lbuiCam = new FlxCamera();
	lbuiCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(lbuiCam, false);
	lbuiCam.zoom = 1.0;

	bg = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/backgrounds/empty'));
	bg.scale.set(2.0, 2.0);
	add(bg);
	bg.screenCenter();

	bg_Back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back'));
	add(bg_Back);
	bg_Back.flipX = true;
	bg_Back.blend = BlendMode.MULTIPLY;

	for (i in 0...songs.length)
	{
		songBg = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/backgrounds/${songs[i].name}'));
		songBg.scale.set(2.0, 2.0);
		songBg.ID = i;
		insert(members.indexOf(bg) + 1, songBg);
		backgrounds.push(songBg);
		songBg.screenCenter();
		songBg.alpha = 0.0;

		var songinfo = new SongInfoUI((100 + (25 * i)), (465 + (180 * i)), songs[i]);
		songinfo.ID = i;
		add(songinfo);
		songInfos.push(songinfo);

		songInfos_OriginalX.push(songinfo.group.x);
		songInfos_OriginalY.push(songinfo.group.y);
	}

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	helpTxt = new FlxText(bg_BtmBanner.x + 15, bg_BtmBanner.y + 22, FlxG.width,
		'L - ${i18n.tr('Gauntlet/ModeSelector/Leaderboards')} \nR - ${i18n.tr('Freeplay/Random')}');
	helpTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	helpTxt.borderSize = 3.0;
	add(helpTxt);

	portrait = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/portraits/madoka'));
	portrait.scale.set(1.30, 1.30);
	portrait.updateHitbox();
	portrait.setPosition((FlxG.width - (portrait.width / 2)) * 2.15, (FlxG.height - (portrait.height / 2)) * 2);
	portrait.y -= bg_BtmBanner.height;
	insert(members.indexOf(bg_BtmBanner), portrait);
	portrait.alpha = 0.0;

	diff_base = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/difficulty/difficulty_base'));
	diff_base.setPosition((FlxG.width - (diff_base.width / 2)) * 0.25, (FlxG.height - (diff_base.height / 2)) * 0.15);
	add(diff_base);

	diff_portrait = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/difficulty/difficulty_portrait'), true, 326, 160);
	diff_portrait.addAnim('easy', null, 0, false, false, [0]);
	diff_portrait.addAnim('hard', null, 0, false, false, [1]);
	diff_portrait.setPosition(diff_base.x, diff_base.y - 89);
	add(diff_portrait);
	diff_portrait.pixelPerfectRender = true;
	diff_portrait.playAnim('hard');

	diff_portraitAdd = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/difficulty/difficulty_portrait_add'), true, 326, 160);
	diff_portraitAdd.addAnim('easy', null, 0, false, false, [0]);
	diff_portraitAdd.addAnim('hard', null, 0, false, false, [1]);
	diff_portraitAdd.setPosition(diff_base.x, diff_base.y - 89);
	add(diff_portraitAdd);
	diff_portraitAdd.blend = BlendMode.ADD;
	diff_portraitAdd.pixelPerfectRender = true;
	diff_portraitAdd.playAnim('hard');

	diff_text = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/difficulty/difficulty_text'), true, 326, 85);
	diff_text.addAnim('easy', null, 0, false, false, [0]);
	diff_text.addAnim('hard', null, 0, false, false, [1]);
	diff_text.setPosition(diff_base.x, diff_base.y);
	add(diff_text);
	diff_text.playAnim('hard');

	diff_textAdd = new FunkinSprite().loadGraphic(Paths.image('ui/freeplay/difficulty/difficulty_text_add'), true, 326, 85);
	diff_textAdd.addAnim('easy', null, 0, false, false, [0]);
	diff_textAdd.addAnim('hard', null, 0, false, false, [1]);
	diff_textAdd.setPosition(diff_base.x, diff_base.y);
	add(diff_textAdd);
	diff_textAdd.blend = BlendMode.ADD;
	diff_textAdd.playAnim('hard');

	fadeoutSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	fadeoutSprite.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(fadeoutSprite);
	fadeoutSprite.alpha = 0.0;

	changeSelection(0);

	changeDiff(0);

	if (FlxG.save.data.viewedMenu.contains(1))
	{
		FlxG.save.data.viewedMenu.remove(1);
		FlxG.save.flush();
	}

	lbgroup = new FlxSpriteGroup();
	add(lbgroup);
}

function changeSelection(change:Int)
{
	if (change != 0)
		GenUtil.playUISound('move');

	fp_curSel = FlxMath.wrap(fp_curSel + change, 0, songInfos.length - 1);

	onLocked = true;
	onUnlockable = false;
	for (i in 0...songInfos.length)
	{
		if (songInfos[i].ID == fp_curSel && !songInfos[i].locked)
		{
			onLocked = false;
		}
		if (songInfos[i].ID == fp_curSel && songInfos[i].unlockable)
		{
			onUnlockable = true;
		}
	}

	updatePortrait();

	curSong = songs[fp_curSel];

	scroll_OffsetX = -25 * fp_curSel;
	scroll_OffsetY = 180 * fp_curSel;

	for (tween in scroll_Tweens)
	{
		tween?.cancel();
	}

	for (i in 0...songInfos.length)
	{
		if (songInfos[i].ID == fp_curSel)
		{
			songInfos[i].selected = true;
			currentSongInfo = songInfos[i];
		}
		else
			songInfos[i].selected = false;

		scroll_Tweens.push(FlxTween.tween(songInfos[i].group,
			{x: songInfos_OriginalX[i] + scroll_OffsetX, y: songInfos_OriginalY[i] - scroll_OffsetY, alpha: 1.0}, 0.5, {ease: FlxEase.expoOut}));
	}
}

function changeDiff(change:Int)
{
	if (change != 0)
		GenUtil.playUISound('move');

	curDiff = FlxMath.wrap(curDiff + change, 0, 1);

	switch (curDiff)
	{
		case 0:
			diff_portrait.playAnim('easy');
			diff_portraitAdd.playAnim('easy');
			diff_text.playAnim('easy');
			diff_textAdd.playAnim('easy');
			diffName = 'easy';
		case 1:
			diff_portrait.playAnim('hard');
			diff_portraitAdd.playAnim('hard');
			diff_text.playAnim('hard');
			diff_textAdd.playAnim('hard');
			diffName = 'hard';
	}

	if (change != 0)
		FlxG.sound.play(Paths.sound('ui/freeplay/diff_' + diffName), 1.0 * Options.volumeSFX);

	for (twn in diffTweens)
	{
		twn.cancel();
	}

	diff_base.setPosition((FlxG.width - (diff_base.width / 2)) * 0.25, ((FlxG.height - (diff_base.height / 2)) * 0.15) + 15);
	diff_portrait.setPosition(diff_base.x, diff_base.y - 89);
	diff_portraitAdd.setPosition(diff_base.x, diff_base.y - 89);
	diff_text.setPosition(diff_base.x, diff_base.y);
	diff_textAdd.setPosition(diff_base.x, diff_base.y);

	diff_portraitAdd.alpha = 1.0;
	diff_textAdd.alpha = 1.0;

	diffTweens.push(FlxTween.tween(diff_base, {y: diff_base.y - 15}, 0.35, {ease: FlxEase.cubeOut}));
	diffTweens.push(FlxTween.tween(diff_portrait, {y: diff_portrait.y - 15}, 0.35, {ease: FlxEase.cubeOut}));
	diffTweens.push(FlxTween.tween(diff_portraitAdd, {y: diff_portraitAdd.y - 15, alpha: 0.0}, 0.35, {ease: FlxEase.cubeOut}));
	diffTweens.push(FlxTween.tween(diff_text, {y: diff_text.y - 15}, 0.35, {ease: FlxEase.cubeOut}));
	diffTweens.push(FlxTween.tween(diff_textAdd, {y: diff_textAdd.y - 15, alpha: 0.0}, 0.35, {ease: FlxEase.cubeOut}));

	for (i in 0...songInfos.length)
	{
		songInfos[i].updateData(diffName);
	}
}

function updatePortrait()
{
	FlxTween.cancelTweensOf(portrait);
	portrait.alpha = 0.0;
	portrait.color = FlxColor.BLACK;

	if (songs[fp_curSel].customValues.portrait != 'none')
	{
		portrait.loadGraphic(Paths.image('ui/freeplay/portraits/' + songs[fp_curSel].customValues.portrait));
		portrait.scale.set(1.30, 1.30);
		portrait.updateHitbox();
		portrait.setPosition((FlxG.width - (portrait.width / 2)) * 0.7, bg_BtmBanner.y - portrait.height);

		portrait.x += 50;
		FlxTween.tween(portrait, {x: portrait.x - 50, alpha: 1.0}, 0.75, {ease: FlxEase.backOut});

		if (!onLocked)
			portrait.color = FlxColor.WHITE;
	}

	for (bg in backgrounds)
	{
		FlxTween.cancelTweensOf(bg);

		if (bg.ID == fp_curSel && !onLocked)
		{
			FlxTween.tween(bg, {alpha: 1.0}, 0.5, {ease: FlxEase.quadOut});
		}
		else
		{
			FlxTween.tween(bg, {alpha: 0.0}, 0.5, {ease: FlxEase.quadIn});
		}
	}
}

function confirmSelection()
{
	GenUtil.playUISound('confirm');

	if (!confirmingSong)
	{
		confirmingSong = true;
		canControl = false;

		FlxG.sound.music?.fadeOut(1.5, 0.0);

		FlxG.camera.filters ??= [];
		if (Options.gameplayShaders)
		{
			bloomShader = new CustomShader("Bloom");
			FlxG.camera.addShader(bloomShader);
			transTweens.push(FlxTween.num(-0.15, 0.0, 1.5, {
				ease: FlxEase.quadOut
			}, function(num:Float)
			{
				bloomShader.amt = num;
			}));
		}

		transTweens.push(FlxTween.num(FlxG.camera.zoom + 0.05, 1.0, 0.5, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				transTweens.push(FlxTween.num(FlxG.camera.zoom, 5.0, 1.5, {
					ease: FlxEase.expoIn,
					onComplete: function(twn:FlxTween)
					{
						PlayState.isStoryMode = false;
						PlayState.isGauntletMode = false;
						PlayState.loadSong(curSong.name, diffName, curSong.variant, false, false);
						FlxG.switchState(new PlayState());
					}
				}, function(num:Float)
				{
					FlxG.camera.zoom = num;
				}));
			}
		}, function(num:Float)
		{
			FlxG.camera.zoom = num;
		}));

		transTweens.push(FlxTween.tween(fadeoutSprite, {alpha: 1.0}, 1.0, {ease: FlxEase.cubeIn, startDelay: 0.75}));

		if (curSong.name != 'reconnect')
			transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_base'), false, true));

		switch (curSong.name)
		{
			case 'out-of-time':
				transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_out-of-time'), false, true));
			case 'meguca':
				transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_meguca'), false, true));
				transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_meguca_vo' + FlxG.random.int(1, 5)), false, true));
			case 'reconnect':
				transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_reconnect'), false, true));
			default:
				transSounds.push(new FlxSound().loadEmbedded(Paths.sound('ui/freeplay/fp_add'), false, true));
		}
		for (snd in transSounds)
		{
			snd.volume = 0.9 * Options.volumeSFX;
			if (curSong.name != 'reconnect')
				snd.pitch += FlxG.random.float(-0.05, 0.05);
			snd?.play();
		}
	}
}

function backSelection()
{
	GenUtil.playUISound('back');

	if (confirmingSong)
	{
		confirmingSong = false;
		canControl = true;

		FlxG.sound.music?.fadeIn(0.5, FlxG.sound.music.volume, 0.7);

		if (Options.gameplayShaders)
			FlxG.camera.filters?.pop();

		for (twn in transTweens)
		{
			twn.cancel();
		}
		transTweens = [];

		transTweens.push(FlxTween.num(FlxG.camera.zoom, 1.0, 0.75, {
			ease: FlxEase.expoOut
		}, function(num:Float)
		{
			FlxG.camera.zoom = num;
		}));

		transTweens.push(FlxTween.tween(fadeoutSprite, {alpha: 0.0}, 1.5, {ease: FlxEase.expoOut}));

		for (snd in transSounds)
		{
			snd?.stop();
			snd?.destroy();
		}
		transSounds = [];
	}
	else
	{
		FlxG.switchState(new ModState("HQMainMenu"));
	}
}

function update(elapsed:Float)
{
	if (canControl && !inLeaderBoards && !randomizing)
	{
		if (controls.UP_P)
			changeSelection(-1);
		else if (controls.DOWN_P)
			changeSelection(1);

		if (controls.LEFT_P)
			changeDiff(-1);
		else if (controls.RIGHT_P)
			changeDiff(1);

		if (FlxG.keys.justPressed.L && !onLocked && loadedLeaderboards)
		{
			showLeaderboards();
		}
		else if (FlxG.keys.justPressed.L && !onLocked && !loadedLeaderboards)
		{
			for (i in 0...songs.length)
			{
				gjlbids.push(RequestType.SCORES_FETCH(false, songs[i].customValues.gjid, 10, false));
			}

			var grabScores:GJRequest = new GJRequest(RequestType.BATCH(false, false, gjlbids));
			grabScores.onComplete.add(function(res)
			{
				gjlbdata = res;

				loadedLeaderboards = true;
				showLeaderboards();
			});
			grabScores.onError.add(function(e)
			{
				loadedLeaderboards = false;
			});
			grabScores.send(false);
		}

		if (FlxG.keys.justPressed.R)
		{
			var loops:Int = 0;
			randomizing = true;
			new FlxTimer().start(0.05, function(tmr:FlxTimer)
			{
				changeSelection(FlxG.random.int(1, 2));
				tmr.time += 0.01;

				loops += 1;
				if (tmr.loops == loops)
				{
					randomizing = false;
				}
			}, FlxG.random.int(10, 15));
		}

		if (FlxG.keys.justPressed.P && Options.devMode)
		{
			for (i in 0...songs.length)
			{
				FlxG.save.data.unlockableSongs.push(songs[i].name);
			}
			FlxG.resetState();
		}

		if (FlxG.keys.justPressed.O && Options.devMode)
		{
			FlxG.save.data.unlockableSongs = [];
			FlxG.save.data.unlockedSongs = [];
			FlxG.resetState();
		}

		if (FlxG.keys.justPressed.B)
		{
			// for (key in FunkinSave.highscores.keys())
			//	FunkinSave.highscores.remove(key);
			// FunkinSave.highscores = null;
		}

		if (FlxG.keys.justPressed.ENTER)
		{
			if (onLocked && onUnlockable)
			{
				canControl = false;
				unlockingSong = true;
				currentSongInfo.unlockAnimation();
				new FlxTimer().start(0.6, function(tmr:FlxTimer)
				{
					FlxG.save.data.unlockedSongs.push(currentSongInfo.songDataP.name);
					unlockingSong = false;
					currentSongInfo.locked = false;
					currentSongInfo.unlockable = false;
					onUnlockable = false;
					genLockBreak();
					changeSelection(0);
					for (i in 0...songInfos.length)
						songInfos[i].updateData(diffName);

					canControl = true;
				});
			}
			else if (onLocked)
				GenUtil.playUISound('error');
			else
				confirmSelection();
		}
	}

	if (controls.BACK && !unlockingSong && !inLeaderBoards)
	{
		backSelection();
	}
	else if (controls.BACK && inLeaderBoards)
	{
		exitLeaderboards();
	}

	// trace(onLocked + ' ' + onUnlockable);
}

// This part is being handled here cuz moves wasn't working on the effect group so until I find a fix it'll be here instead...

function genLockBreak()
{
	var creationPosition:Array<Float> = [currentSongInfo.group.x + 475, currentSongInfo.group.y + 65];
	var offset:Array<Float> = [0, 0];
	var vel:Array<Float> = [0, 0];
	for (i in 1...12)
	{
		switch (i)
		{
			case 7:
				offset = [3, -57];
				vel = [0, -50];
			case 6:
				offset = [11, -39];
				vel = [25, -25];
			case 5:
				offset = [-9, -52];
				vel = [-25, -30];
			case 4:
				offset = [11, -6];
				vel = [50, 15];
			case 3:
				offset = [-19, -43];
				vel = [-50, 15];
			case 2:
				offset = [-15, 0];
				vel = [-50, 50];
			default:
				offset = [0, 0];
				vel = [0, 50];
		}
		var lock_piece = new FunkinSprite(creationPosition[0] + offset[0], creationPosition[1] + offset[1]);
		if (i <= 7)
			lock_piece.loadSprite(Paths.image('ui/common/lock_pieces/lockpiece$i'));
		else
		{
			lock_piece.loadSprite(Paths.image('ui/common/lock_pieces/sudopiece${FlxG.random.int(1, 2)}'));
			vel = [FlxG.random.float(-25, 25), FlxG.random.float(-100, 50)];
		}
		add(lock_piece);
		lock_piece.moves = true;
		lock_piece.velocity.x = (vel[0] + FlxG.random.float(-15, 15)) * 5;
		lock_piece.velocity.y = (vel[1] + FlxG.random.float(-15, 15)) * 5;
		lock_piece.acceleration.x = vel[0];
		lock_piece.acceleration.y = 1000;
		lock_piece.angularVelocity = FlxG.random.int(0, 150);
		lock_piece.angularAcceleration = FlxG.random.int(0, 500);

		new FlxTimer().start(1.75, function(tmr:FlxTimer)
		{
			lock_piece.destroy();
			remove(lock_piece, true);
		});
	}
}

function showLeaderboards()
{
	inLeaderBoards = true;

	for (cam in FlxG.cameras.list)
	{
		if (cam != lbuiCam)
			blur.set(15.0);
	}

	overlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	overlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	lbgroup.add(overlay).cameras = [lbuiCam];
	overlay.alpha = 0.65;

	overlayLeaderboardTxt = new FlxText(0, 0, FlxG.width, i18n.tr('Gauntlet/LeaderboardTop10'));
	overlayLeaderboardTxt.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	overlayLeaderboardTxt.borderSize = 2.0;
	lbgroup.add(overlayLeaderboardTxt).cameras = [lbuiCam];
	overlayLeaderboardTxt.screenCenter();
	overlayLeaderboardTxt.y -= 400;

	for (i in 0...gjlbdata.responses[fp_curSel].scores.length)
	{
		var startingY:Float = 225 + (85 * i);

		overlay = new FlxSprite(0, startingY).makeGraphic(1, 1, FlxColor.BLACK);
		overlay.scale.set(FlxG.width * 0.5, FlxG.height * 0.065);
		lbgroup.add(overlay).cameras = [lbuiCam];
		overlay.screenCenter(FlxAxes.X);
		overlay.alpha = 0.75;

		nameTxt = new FlxText(0, 0, 960 - 20, gjlbdata.responses[fp_curSel].scores[i].user, false);
		nameTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		nameTxt.borderSize = 2.0;
		lbgroup.add(nameTxt).cameras = [lbuiCam];
		GenUtil.alignToCenter(nameTxt, overlay);
		nameTxt.y -= 10;
		// nameTxt.x += 5;

		durationAgoTxt = new FlxText(0, 0, 960 - 20, gjlbdata.responses[fp_curSel].scores[i].stored, false);
		durationAgoTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.GRAY, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		durationAgoTxt.borderSize = 2.0;
		lbgroup.add(durationAgoTxt).cameras = [lbuiCam];
		GenUtil.alignToCenter(durationAgoTxt, overlay);
		durationAgoTxt.y += 15;
		// durationAgoTxt.x += 5;

		scoreTxt = new FlxText(0, 0, 960 - 20, FlxStringUtil.formatMoney(gjlbdata.responses[fp_curSel].scores[i].score, false));
		scoreTxt.setFormat(Paths.font("shingo.otf"), 48, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		scoreTxt.borderSize = 2.0;
		lbgroup.add(scoreTxt).cameras = [lbuiCam];
		GenUtil.alignToCenter(scoreTxt, overlay);
	}
}

function exitLeaderboards()
{
	for (cam in FlxG.cameras.list)
	{
		if (cam != lbuiCam)
			blur.set(0.0);
	}

	lbgroup.clear();

	inLeaderBoards = false;
}
