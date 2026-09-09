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
		firstText = new FlxText(1200, 800, 500, '