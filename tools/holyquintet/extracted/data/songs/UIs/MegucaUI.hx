import ui.JudgementDisplayUI;
import ui.StatTextUI;
import ui.SoulGemUI;
import flixel.math.FlxRect;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.ui.FlxBar;
import flixel.ui.FlxBarFillDirection;
import openfl.display.BlendMode;

var healthDisplay:Float = 1;
var healthGlowing:Bool = false;
public var healthBarGrp:Array<Dynamic> = [];
var iconTweens:Array<FlxTween> = [];
public var statTxtGrp:Array<StatTextUI> = [];
public var scoreGrp:Array<Dynamic> = [];
public var soulGemGrp:Array<Dynamic> = [];
public var soulgemSprite:SoulGemUI;
public var judgementDisplay:JudgementDisplayUI;
public var noteStreakMutliAdd_mainSprite:FunkinSprite;
public var noteStreakMutliAdd_curMultiTxt:FlxText;
var comboMultiTween:FlxTween;
var comboMultiTxtTween:FlxTween;
var soulGemShakeTween:FlxTween;
var soulgemCracked:Bool = false;
public var soulgem_sanityOverlay:FunkinSprite;
public var camUI:FlxCamera;
public var atksSustained:Int = 0;
public var startUIvisablityArgs:Array<Dynanic> = [true, true, true, true, true, 0, false, 4, "linear", "In"];

function create()
{
	camUI = new FlxCamera(0, 0, FlxG.width, FlxG.height);
	camUI.bgColor = 0x00000000;
	FlxG.cameras.insert(camUI, FlxG.cameras.list.indexOf(camHUD), false);

	// Health Bar
	hpbar_Border = new FunkinSprite(125, 0);
	hpbar_Border.loadSprite(Paths.image("game/healthbar/border-meguca"));
	add(hpbar_Border);
	hpbar_Border.screenCenter(FlxAxes.Y);

	hpbar_OppMeter = new FunkinSprite(hpbar_Border.x, hpbar_Border.y);
	hpbar_OppMeter.loadSprite(Paths.image("game/healthbar/meter-meguca"));
	insert(members.indexOf(hpbar_Border) - 1, hpbar_OppMeter);

	hpbar_Meter = new FlxBar(hpbar_Border.x, hpbar_Border.y, FlxBarFillDirection.BOTTOM_TO_TOP, Std.int(hpbar_Border.width), Std.int(hpbar_Border.height),
		this, 'health', 0, maxHealth);
	hpbar_Meter.createImageBar(Paths.image("game/healthbar/meter-meguca"), Paths.image("game/healthbar/meter-meguca"));
	insert(members.indexOf(hpbar_Border) - 1, hpbar_Meter);
	hpbar_Meter.clipRect = new FlxRect(0, 0, Std.int(hpbar_Border.width), Std.int(hpbar_Border.height));
	hpbar_Meter.unbounded = true;

	// Judgement Displayer
	judgementDisplay = new JudgementDisplayUI();
	add(judgementDisplay);
	judgementDisplay.group.scale.set(0.75, 0.75);
	judgementDisplay.group.cameras = [camUI];
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

	iconP1.x = hpbar_Border.y - 64;
	iconP2.x = hpbar_Border.y - 64;

	// Hide Default UI
	for (spr in [healthBar, healthBarBG, scoreTxt, missesTxt, accuracyTxt])
		spr.visible = false;

	// Health Bar
	for (spr in [hpbar_Border, hpbar_OppMeter, hpbar_Meter, iconP1, iconP2])
	{
		spr.cameras = [camUI];
		healthBarGrp.push(spr);
	}

	for (spr in [iconP1, iconP2])
	{
		remove(spr);
		insert(members.indexOf(hpbar_Meter) + 6, spr);
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
	updateIconPositions = updateNewIconPositions;

	executeEvent({name: "UI Visability", time: 0, params: startUIvisablityArgs});
}

function postUpdate(elapsed:Float)
{
	// Health Bar
	hpbar_Meter.clipRect.width = hpbar_Meter.width;
	hpbar_Meter.clipRect.height = hpbar_Meter.height;
	hpbar_Meter.clipRect.x = hpbar_Meter.width + health * 50;
	hpbar_Meter.clipRect.y = 0;
	hpbar_Meter.clipRect = hpbar_Meter.clipRect;

	healthBar.percent = health * 50;
	hpbar_Meter.percent = health * 50;

	// Update Camera
	camUI.zoom = camHUD.zoom * camHUD.zoomMultiplier;
	camUI.angle = camHUD.angle;
	camUI.scroll.x = camHUD.scroll.x;
	camUI.scroll.y = camHUD.scroll.y;

	// Time Bar
	// timebar_Meter.clipRect.width = (Conductor.songPosition / FlxG.sound.music.length) * Std.int(timebar_Meter.width);
	// timebar_Meter.clipRect = timebar_Meter.clipRect;
}

function updateNewIconPositions()
{
	var iconOffset = Flags.ICON_OFFSET;
	var healthBarPercent = hpbar_Meter.percent;

	var center:Float = hpbar_Meter.x + hpbar_Meter.height * FlxMath.remapToRange(healthBarPercent, 0, 100, 1, 0);

	iconP1.y = (center + 60) - 67;
	iconP2.y = (center - 60) - 67;

	iconP1.health = healthBarPercent / 100;
	iconP2.health = 1 - (healthBarPercent / 100);
}

function beatHit(curBeat:Int)
{
}

public function updateScoreTxtPos()
{
}

public function soulGemUpdate()
{
}

public function multiAnimation(type:String)
{
}

public function updateScoreText()
{
}
