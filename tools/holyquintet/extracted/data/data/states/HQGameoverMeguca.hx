import util.GenUtil;
import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import funkin.editors.charter.Charter;
import funkin.menus.FreeplayState;
import funkin.menus.StoryMenuState;
import openfl.display.BlendMode;

var canControl:Bool = true;
var godukaPrompt:Bool = false;

FlxG.sound.load(Paths.music("gameover-meguca"));
FlxG.sound.load(Paths.sound("game/gameover/gameoverend-meguca"));
function create()
{
	if (PlayState.deathCounter <= 3 || PlayState.isGauntletMode || godukaEnabled || godukaCooldown > 1)
		godukaPrompt = false;
	else
		godukaPrompt = true;

	camera = gameOverCam = new FlxCamera();
	gameOverCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(gameOverCam, false);

	gf = new Character(1025, 200, 'gf-meguca', true);
	add(gf);
	gf.scale.set(1.5, 1.5);
	gf.playAnim('deathLoop', true);

	// Start Death Scene
	CoolUtil.playMusic(Paths.music("gameover-meguca"), false, 1, true);
	for (strumLine in PlayState.instance.strumLines.members)
		strumLine.vocals?.stop();

	godukaCooldown -= 1;
}

function postCreate()
{
}

function update(elapsed:Float)
{
	if (canControl)
	{
		if (controls.ACCEPT)
		{
			FlxG.sound.music.stop();

			FlxG.sound.play(Paths.sound("game/gameover/gameoverend-meguca"));
			gf.playAnim('deathEnd', true, 'LOCK');
			gf.animation.finishCallback = () ->
			{
				camFadeOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
				camFadeOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
				add(camFadeOverlay);
				camFadeOverlay.scrollFactor.set(0.0, 0.0);
				camFadeOverlay.alpha = 0.0;

				FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 1.5, {
					ease: FlxEase.quadInOut,
					onComplete: function(twn:FlxTween)
					{
						if (!godukaPrompt)
							FlxG.switchState(new PlayState());
						else
						{
							godkuaSubState = new ModSubState("HQGodukaPrompt");
							openSubState(godkuaSubState);
						}
					}
				});
			};

			canControl = false;
		}
	}

	if (controls.BACK)
	{
		if (PlayState.chartingMode && Charter.undos.unsaved)
			game.saveWarn(false);
		else
		{
			godukaEnabled = false;
			godukaCooldown = -1;

			if (Charter.instance != null)
				Charter.instance.__clearStatics();

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();
			FlxG.sound.music = null;

			if (PlayState.isGauntletMode)
				FlxG.switchState(new ModState("HQGauntlet"));
			else
				FlxG.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
		}
	}
}

function confirmSelection()
{
	GenUtil.playUISound('confirm');

	canControl = false;
}
