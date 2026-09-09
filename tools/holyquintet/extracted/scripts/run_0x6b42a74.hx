import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.ui.FlxBar;
import flixel.ui.FlxBarFillDirection;
import funkin.backend.system.Flags;
import funkin.backend.system.framerate.Framerate;

var kadeUIactive:Bool = false;
var kadeSicks:Int = 0;
var kadeGoods:Int = 0;
var kadeBads:Int = 0;
var kadeShits:Int = 0;
var kadeSongLength:Float = 0;
var kadeSongPos:Float = 0;
var kadeHealth:Float = 1.0;
var originalDebugMode:Int = Framerate.debugMode;

function create()
{
	kadeSongLength = FlxG.sound.music.length;

	camUIKade = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camUIKade.bgColor = 0x00000000;
	FlxG.cameras.insert(camUIKade, FlxG.cameras.list.indexOf(camUIKade), false);

	// IM SO LAZY SORRY
	camUIKadeFPS = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camUIKadeFPS.bgColor = 0x00000000;
	FlxG.cameras.insert(camUIKadeFPS, FlxG.cameras.list.indexOf(camUIKadeFPS), false);

	camUIKade.visible = false;
	camUIKadeFPS.visible = false;

	kade_healthBarBG = new FunkinSprite(0, FlxG.height * 0.925).loadSprite(Paths.image('game/healthBar'));
	kade_healthBarBG.screenCenter(FlxAxes.X);
	kade_healthBarBG.scrollFactor.set();
	add(kade_healthBarBG);
	if (Options.downscroll)
		kade_healthBarBG.y = 50;

	kade_healthBar = new FlxBar(kade_healthBarBG.x + 4, kade_healthBarBG.y + 4, FlxBarFillDirection.RIGHT_TO_LEFT, Std.int(kade_healthBarBG.width - 8),
		Std.int(kade_healthBarBG.height - 8), this, 'health', 0, maxHealth);
	kade_healthBar.scrollFactor.set();
	kade_healthBar.createFilledBar(0xFFFF0000, 0xFF00FF00);
	add(kade_healthBar);

	kade_iconP1 = new HealthIcon(boyfriend != null ? 'gf-old' : Flags.DEFAULT_HEALTH_ICON, true);
	kade_iconP2 = new HealthIcon(dad != null ? 'mami-old' : Flags.DEFAULT_HEALTH_ICON, false);
	for (icon in [kade_iconP1, kade_iconP2])
	{
		icon.y = kade_healthBarBG.y - (icon.height / 2);
		add(icon);
	}

	kade_watermark = new FlxText(4, kade_healthBarBG.y + 62, 0, '$curSong - ${PlayState.difficulty} | KE 1.5.4', 16);
	kade_watermark.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	kade_watermark.scrollFactor.set();
	add(kade_watermark);
	if (Options.downscroll)
		kade_watermark.y = 5;

	kade_scoreTxt = new FlxText(FlxG.width / 2 - 235, kade_healthBarBG.y + 62, 0, "", 20);
	kade_scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	add(kade_scoreTxt);
	kade_scoreTxt.x += 100;

	kade_songPosBG = new FunkinSprite(0, 10).loadSprite(Paths.image('game/healthBar'));
	kade_songPosBG.screenCenter(FlxAxes.X);
	kade_songPosBG.scrollFactor.set();
	add(kade_songPosBG);
	if (Options.downscroll)
		kade_songPosBG.y = FlxG.height * 0.9 + 45;

	kade_songPosBar = new FlxBar(kade_songPosBG.x
		+ 4, kade_songPosBG.y
		+ 4, FlxBarFillDirection.LEFT_TO_RIGHT, Std.int(kade_songPosBG.width - 8),
		Std.int(kade_songPosBG.height - 8), null, null, 0, kadeSongLength
		- 1000);
	kade_songPosBar.numDivisions = 1000;
	kade_songPosBar.scrollFactor.set();
	kade_songPosBar.createFilledBar(FlxColor.GRAY, FlxColor.LIME);
	add(kade_songPosBar);

	kade_songPosName = new FlxText(kade_songPosBG.x + (kade_songPosBG.width / 2), kade_songPosBG.y, 0, curSong, 16);
	kade_songPosName.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
	kade_songPosName.scrollFactor.set();
	add(kade_songPosName);
	if (Options.downScroll)
		kade_songPosName.y -= 3;

	kade_fakeFPScounter = new FlxText(10, 3, 128, "FPS: 450", 12);
	kade_fakeFPScounter.setFormat("_sans", 12, FlxColor.WHITE, FlxTextAlign.LEFT);
	kade_fakeFPScounter.scrollFactor.set();
	add(kade_fakeFPScounter);
	kade_fakeFPScounter.cameras = [camUIKadeFPS];

	for (spr in [
		kade_healthBarBG,
		kade_healthBar,
		kade_iconP1,
		kade_iconP2,
		kade_watermark,
		kade_scoreTxt,
		kade_songPosBG,
		kade_songPosBar,
		kade_songPosName
	])
	{
		spr.cameras = [camUIKade];
	}

	comboGroup.y = -150;
}

function onPlayerHit(e)
{
	e.cancel();

	if (e == null)
		return;

	if (e.accuracy == 1.0)
		kadeSicks += 1;
	else if (e.accuracy == 0.75)
		kadeGoods += 1;
	else if (e.accuracy == 0.45)
		kadeBads += 1;
	else if (e.accuracy == 0.45)
		kadeShits += 1;

	if (!e.note.isSustainNote && kadeUIactive)
	{
		displayRating(e.rating, e);
		displayCombo(e);
	}
}

function update(elapsed)
{
	if (!kadeUIactive)
		return;

	kadeSongPos = FlxG.sound.music.time;

	var iconOffset = Flags.ICON_OFFSET;
	var healthBarPercent = kade_healthBar.percent;

	var center:Float = kade_healthBar.x + kade_healthBar.width * FlxMath.remapToRange(healthBarPercent, 0, 100, 1, 0);

	kade_iconP1.x = center - iconOffset;
	kade_iconP2.x = center - (kade_iconP2.width - iconOffset);

	kade_iconP1.health = healthBarPercent / 100;
	kade_iconP2.health = 1 - (healthBarPercent / 100);

	kade_iconP1.setGraphicSize(FlxMath.lerp(kade_iconP1.width, 150, 0.5));
	kade_iconP2.setGraphicSize(FlxMath.lerp(kade_iconP2.width, 150, 0.5));

	kade_iconP1.updateHitbox();
	kade_iconP2.updateHitbox();

	kade_songPosBar.value = FlxG.sound.music.time;

	var kadeFCRank:String = '';

	if (misses == 0 && kadeBads == 0 && kadeShits == 0 && kadeGoods == 0)
		kadeFCRank = "(MFC)";
	else if (misses == 0 && kadeBads == 0 && kadeShits == 0 && kadeGoods >= 1)
		kadeFCRank = "(GFC)";
	else if (misses == 0)
		kadeFCRank = "(FC)";
	else if (misses < 10)
		kadeFCRank = "(SDCB)";
	else
		kadeFCRank = "(Clear)";

	var kadeRanking:String = '';

	var kadeAccuracy:Float = accuracy * 100;

	if ((kadeAccuracy) >= 99.9935)
		kadeRanking = 'AAAAA';
	else if (kadeAccuracy >= 99.980)
		kadeRanking = 'AAAA:';
	else if (kadeAccuracy >= 99.970)
		kadeRanking = 'AAAA.';
	else if (kadeAccuracy >= 99.955)
		kadeRanking = 'AAAA';
	else if (kadeAccuracy >= 99.90)
		kadeRanking = 'AAA:';
	else if (kadeAccuracy >= 99.80)
		kadeRanking = 'AAA.';
	else if (kadeAccuracy >= 99.70)
		kadeRanking = 'AAA';
	else if (kadeAccuracy >= 99)
		kadeRanking = 'AA:';
	else if (kadeAccuracy >= 96.50)
		kadeRanking = 'AA.';
	else if (kadeAccuracy >= 93)
		kadeRanking = 'AA';
	else if (kadeAccuracy >= 90)
		kadeRanking = 'A:';
	else if (kadeAccuracy >= 85)
		kadeRanking = 'A.';
	else if (kadeAccuracy >= 80)
		kadeRanking = 'A';
	else if (kadeAccuracy >= 70)
		kadeRanking = 'B';
	else if (kadeAccuracy >= 60)
		kadeRanking = 'C';
	else if (kadeAccuracy < 60)
		kadeRanking = 'D';

	if (totalAccuracyAmount == 0)
		kade_scoreTxt.text = 'Score:$songScore | Combo Breaks:$misses | Accuracy:0 % | N/A';
	else
		kade_scoreTxt.text = 'Score:$songScore | Combo Breaks:$misses | Accuracy:${FlxMath.roundDecimal(accuracy * 100, 2)} % | $kadeFCRank $kadeRanking';

	camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, 0.95);
	camUIKade.zoom = FlxMath.lerp(1, camUIKade.zoom, 0.95);

	kade_fakeFPScounter.text = 'FPS: ${FlxG.drawFramerate}';

	Framerate.debugMode = 0;
}

function beatHit(curBeat:Int)
{
	if (!kadeUIactive)
		return;

	kade_iconP1.setGraphicSize(Std.int(kade_iconP1.width + 30));
	kade_iconP2.setGraphicSize(Std.int(kade_iconP2.width + 30));

	kade_iconP1.updateHitbox();
	kade_iconP2.updateHitbox();

	if (curBeat % 4 == 0)
	{
		camGame.zoom += 0.015;
		camHUD.zoom += 0.03;
		camUIKade.zoom += 0.03;
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
						kadeUIactive = true;
						camUIKade.visible = true;
						camUIKadeFPS.visible = true;
						camUI.visible = false;

						Framerate.debugMode = 0;

					case 'End':
						kadeUIactive = false;
						camUIKade.visible = false;
						camUIKadeFPS.visible = false;
						camUI.visible = true;

						Framerate.debugMode = originalDebugMode;
				}
		}
	}
}

function destroy()
{
	Framerate.debugMode = originalDebugMode;
}
