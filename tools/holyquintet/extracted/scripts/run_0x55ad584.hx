import ui.JudgementDisplayUI;
import ui.StatTextUI;
import ui.SoulGemUI;
import flixel.math.FlxRect;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.addons.display.FlxPieDial;
import flixel.ui.FlxBar;
import flixel.ui.FlxBarFillDirection;
import openfl.display.BlendMode;

var healthDisplay:Float = 1;
var healthGlowing:Bool = false;
var healthGlowCooldown:Float = -1;
public var healthBarGrp:Array<Dynamic> = [];
var iconTweens:Array<FlxTween> = [];
public var statTxtGrp:Array<StatTextUI> = [];
public var scoreGrp:Array<Dynamic> = [];
public var soulGemGrp:Array<Dynamic> = [];
public var soulgemSprite:SoulGemUI;
public var judgementDisplay:JudgementDisplayUI;
public var noteStreakMutliAdd_mainSprite:FunkinSprite;
var comboMultiTween:FlxTween;
var soulGemShakeTween:FlxTween;
var soulgemCracked:Bool = false;
public var soulgem_sanityOverlay:FunkinSprite;
public var camUI:FlxCamera;
public var atksSustained:Int = 0;
public var startUIvisablityArgs:Array<Dynanic> = [true, true, true, true, true, 0, false, 4, "linear", "In"];

FlxG.sound.load(Paths.sound("game/health_max"));
function create()
{
	camUI = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camUI.bgColor = 0x00000000;
	FlxG.cameras.insert(camUI, FlxG.cameras.list.indexOf(camHUD), false);

	// Health Bar
	hpbar_Border = new FunkinSprite(0, 0);
	hpbar_Border.loadSprite(Paths.image("game/healthbar/border"));
	add(hpbar_Border);
	hpbar_Border.screenCenter();
	if (Options.downscroll)
		hpbar_Border.y = FlxG.height * 0.055;
	else
		hpbar_Border.y = FlxG.height * 0.872;

	hpbar_OppMeter = new FunkinSprite(hpbar_Border.x, hpbar_Border.y);
	hpbar_OppMeter.loadSprite(Paths.image("game/healthbar/meter"));
	insert(members.indexOf(hpbar_Border) - 1, hpbar_OppMeter);

	hpbar_Meter = new FlxBar(hpbar_Border.x, hpbar_Border.y, FlxBarFillDirection.RIGHT_TO_LEFT, Std.int(hpbar_Border.width), Std.int(hpbar_Border.height - 8),
		this, 'health', 0, maxHealth);
	hpbar_Meter.createImageBar(Paths.image("game/healthbar/meter"), Paths.image("game/healthbar/meter"));
	insert(members.indexOf(hpbar_Border) - 1, hpbar_Meter);
	hpbar_Meter.clipRect = new FlxRect(0, 0, Std.int(hpbar_Border.width), Std.int(hpbar_Border.height));
	hpbar_Meter.unbounded = true;

	hpbar_GlowMeter = new FunkinSprite(hpbar_Border.x, hpbar_Border.y);
	hpbar_GlowMeter.loadSprite(Paths.image("game/healthbar/maxglow"));
	insert(members.indexOf(hpbar_Border) - 1, hpbar_GlowMeter);
	hpbar_GlowMeter.clipRect = new FlxRect(0, 0, Std.int(hpbar_Border.width), Std.int(hpbar_Border.height));
	hpbar_GlowMeter.blend = BlendMode.ADD;
	hpbar_GlowMeter.visible = false;

	var newStatus:StatTextUI = new StatTextUI('Breaks', hpbar_Border.y);
	add(newStatus);
	statTxtGrp.push(newStatus);
	newStatus.group.cameras = [camUI];

	var newStatus2:StatTextUI = new StatTextUI('Accuracy', hpbar_Border.y);
	add(newStatus2);
	statTxtGrp.push(newStatus2);
	newStatus2.group.cameras = [camUI];

	var newStatus3:StatTextUI = new StatTextUI('FC Rank', hpbar_Border.y);
	add(newStatus3);
	statTxtGrp.push(newStatus3);
	newStatus3.group.cameras = [camUI];

	// var newStatus:StatTextUI = new StatTextUI('Score Multiplier', hpbar_Border.y);
	// add(newStatus);
	// statTxtGrp.push(newStatus);
	// newStatus.group.cameras = [camUI];

	updateScoreTxtPos();

	// Judgement Displayer
	judgementDisplay = new JudgementDisplayUI();
	add(judgementDisplay);
	judgementDisplay.group.cameras = [camUI];

	// Combo Multiplier
	noteStreakMutliAdd_mainSprite = new FunkinSprite(0, 0);
	noteStreakMutliAdd_mainSprite.loadGraphic(Paths.image("game/combomulti/bars"), true, 253, 101);
	for (i in 0...5)
		noteStreakMutliAdd_mainSprite.addAnim('$i', null, 0, false, false, [i]);
	insert(members.indexOf(hpbar_Border) - 1, noteStreakMutliAdd_mainSprite);
	noteStreakMutliAdd_mainSprite.playAnim('0', true);
	noteStreakMutliAdd_mainSprite.setPosition((hpbar_Border.x + (hpbar_Border.width / 2)) - (noteStreakMutliAdd_mainSprite.width / 2), hpbar_Border.y - 70);
	noteStreakMutliAdd_mainSprite.clipRect = new FlxRect(0, 0, Std.int(noteStreakMutliAdd_mainSprite.width), 0);

	// Score
	score_curScoreTxt = new FlxText(hpbar_Border.x + (hpbar_Border.width * 1.8) / 2, hpbar_Border.y + (hpbar_Border.height * 0.4) / 2, 400, '0000000');
	score_curScoreTxt.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	score_curScoreTxt.borderSize = 3.0;
	add(score_curScoreTxt);
	score_curScoreTxt.origin.y = score_curScoreTxt.height;

	score_reqScoreTxt = new FlxText(score_curScoreTxt.x, score_curScoreTxt.y + score_curScoreTxt.height, 400, '0000000');
	score_reqScoreTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.GRAY, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	score_reqScoreTxt.borderSize = 3.0;
	add(score_reqScoreTxt);

	score_reqScoreWarningTxt = new FlxText(score_curScoreTxt.x, score_curScoreTxt.y - score_reqScoreTxt.height, 400, '');
	score_reqScoreWarningTxt.setFormat(Paths.font("shingo.otf"), 24, 0xFFFF7700, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	score_reqScoreWarningTxt.borderSize = 3.0;
	add(score_reqScoreWarningTxt);

	// Soul Gem
	if (Options.downscroll)
	{
		soulgemSprite = new SoulGemUI();
		add(soulgemSprite);
	}
	else
	{
		soulgemSprite = new SoulGemUI();
		add(soulgemSprite);
	}
	soulGemOriginalPos = [soulgemSprite.group.x, soulgemSprite.group.y];

	soulgem_sanityOverlay = new FunkinSprite(0, 0);
	soulgem_sanityOverlay.loadSprite(Paths.image("game/soulgem/sanityoverlay"));
	add(soulgem_sanityOverlay);
	soulgem_sanityOverlay.alpha = 0.0;
	soulgem_sanityOverlay.blend = BlendMode.MULTIPLY;
	soulgem_sanityOverlay.cameras = [camUI];

	// piedialtest = new FlxPieDial(1200, 500, 128, FlxColor.WHITE, 256, null, true, 0);
	// add(piedialtest);
	// piedialtest.cameras = [camUI];
	// piedialtest.amount = 0.0;
	// piedialtest.angle = -90;
}

function postCreate()
{
	var strumWidth:Float = 1;

	if (playerStrums == null)
		strumWidth = (cpuStrums.members[cpuStrums.length - 1].x + cpuStrums.members[cpuStrums.length - 1].width) - cpuStrums.members[0].x + 40;
	else
		strumWidth = (playerStrums.members[playerStrums.length - 1].x + playerStrums.members[playerStrums.length - 1].width) - playerStrums.members[0].x + 40;

	if (playerStrums == null)
		strumUnderlay = new FlxSprite(cpuStrums.members[0].x - 20, 0).makeGraphic(1, 1, FlxColor.BLACK);
	else
		strumUnderlay = new FlxSprite(playerStrums.members[0].x - 20, 0).makeGraphic(1, 1, FlxColor.BLACK);
	insert(0, strumUnderlay).cameras = [camUI];
	strumUnderlay.alpha = Options.strumUnderlayAlpha / 100;

	strumUnderlay.origin.x = 0;
	strumUnderlay.origin.y = 0;
	strumUnderlay.scale.set(strumWidth, FlxG.height * 1.1);

	iconP1.y = hpbar_Border.y - 50;
	iconP2.y = hpbar_Border.y - 50;

	// Hide Default UI
	for (spr in [healthBar, healthBarBG, scoreTxt, missesTxt, accuracyTxt])
		spr.visible = false;

	// Health Bar
	for (spr in [
		hpbar_Border,
		hpbar_OppMeter,
		hpbar_Meter,
		hpbar_GlowMeter,
		iconP1,
		iconP2,
		noteStreakMutliAdd_mainSprite
	])
	{
		spr.cameras = [camUI];
		healthBarGrp.push(spr);
	}

	for (spr in [iconP1, iconP2])
	{
		remove(spr);
		insert(members.indexOf(hpbar_Meter) + 6, spr);
	}

	for (spr in [score_curScoreTxt, score_reqScoreTxt, score_reqScoreWarningTxt])
	{
		spr.cameras = [camUI];
		scoreGrp.push(spr);
	}

	for (spr in [soulgemSprite.group])
	{
		spr.cameras = [camUI];
		soulGemGrp.push(spr);
	}

	// Health Bar
	var leftColor:Int = dad != null && dad.iconColor != null ? dad.iconColor : 0xFFFF0000;
	var rightColor:Int = boyfriend != null && bf.iconColor != null ? bf.iconColor : 0xFF66FF33;

	if (dad == null && boyfriend != null)
		leftColor = 0xFF520026;

	if (dad == null || boyfriend == null)
	{
		leftColor = 0xFF520026;
		rightColor = dad.iconColor;
	}

	hpbar_OppMeter.color = leftColor;
	hpbar_Meter.color = rightColor;
	hpbar_GlowMeter.color = rightColor;
	updateIconPositions = updateNewIconPositions;

	executeEvent({name: "UI Visability", time: 0, params: startUIvisablityArgs});
}

function postUpdate(elapsed:Float)
{
	// piedialtest.amount += 0.001;

	// Health Bar
	hpbar_Meter.clipRect.width = hpbar_Meter.width;
	hpbar_Meter.clipRect.height = hpbar_Meter.height;
	hpbar_Meter.clipRect.x = hpbar_Meter.width + healthDisplay;
	hpbar_Meter.clipRect.y = 0;
	hpbar_Meter.clipRect = hpbar_Meter.clipRect;

	healthDisplay = CoolUtil.fpsLerp(healthDisplay, (health * 50), 0.3);
	healthBar.percent = healthDisplay;
	hpbar_Meter.percent = healthDisplay;

	hpbar_GlowMeter.clipRect.width = hpbar_GlowMeter.width;
	hpbar_GlowMeter.clipRect.height = hpbar_GlowMeter.height;
	hpbar_GlowMeter.clipRect.x = 0;
	hpbar_GlowMeter.clipRect.y = 0;
	hpbar_GlowMeter.clipRect = hpbar_GlowMeter.clipRect;
	if (!healthGlowing && health > 1.7)
	{
		healthGlowing = true;
		if (hpbar_Meter.alpha >= 0.5 && healthGlowCooldown <= 0 && camUI.visible)
		{
			healthGlowCooldown = 5.0;
			FlxG.sound.play(Paths.sound("game/health_max"), 0.5 * Options.volumeSFX);
		}
		hpbar_GlowMeter.visible = true;
	}
	else if (healthGlowing && health < 1.7)
	{
		healthGlowing = false;
		hpbar_GlowMeter.visible = false;
	}
	healthGlowCooldown -= 1 * elapsed;

	// Combo Multiplier
	noteStreakMutliAdd_mainSprite.clipRect = noteStreakMutliAdd_mainSprite.clipRect;

	// Update Camera
	camUI.zoom = camHUD.zoom * camHUD.zoomMultiplier;
	camUI.angle = camHUD.angle;
	camUI.scroll.x = camHUD.scroll.x;
	camUI.scroll.y = camHUD.scroll.y;

	score_curScoreTxt.text = padScore(songScore);

	if (useTargetScoreMech)
	{
		score_reqScoreTxt.visible = true;
		score_reqScoreWarningTxt.visible = true;
		score_reqScoreTxt.text = padScore(targetScore);

		if (targetScore > songScore)
		{
			score_reqScoreWarningTxt.text = '