import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.options.OptionsMenu;
import hxvlc.flixel.FlxVideoSprite;
import openfl.display.BlendMode;
import ui.ButtonUI;
import util.GenUtil;

public static var ps_curSel:Int = 0;
var canControl:Bool = true;
var menuOptions:Array<String> = ['Resume', 'Restart', 'Settings', 'Quit'];
var menu_Texts:Array<ButtonUI> = [];
var megucaVideoPosition:Float = 0;

function create(e)
{
	e.cancel();

	camera = pauseCam = new FlxCamera();
	pauseCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(pauseCam, false);

	var color:FlxColor = FlxColor.BLACK;
	if (PlayState.instance.dad != null)
		color = PlayState.instance.dad.iconColor;

	bg = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	bg.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(bg);
	bg.alpha = 0.5;

	banner = new FlxSprite(0, 0).loadGraphic(Paths.image('ui/pause/meguca/gradient'));
	add(banner);

	leftWindow = new FunkinSprite(100).loadGraphic(Paths.image('ui/pause/meguca/leftwindow'));
	add(leftWindow);
	leftWindow.screenCenter(FlxAxes.Y);

	for (i in 0...menuOptions.length)
	{
		var menu_Text = new FlxText(leftWindow.x + 20, leftWindow.y + 75 + (i * 50), leftWindow.width - (leftWindow.width * 0.025), menuOptions[i]);
		menu_Text.ID = i;
		menu_Text.setFormat(Paths.font("arial.ttf"), 42, 0xFF880500, FlxTextAlign.LEFT);
		add(menu_Text);
		menu_Texts.push(menu_Text);
	}

	creditsTitle = new FunkinSprite(0, 40).loadGraphic(Paths.image('ui/pause/meguca/name'));
	add(creditsTitle);
	creditsTitle.screenCenter(FlxAxes.X);

	creditsText = new FlxText(leftWindow.x + 8, leftWindow.y + 570, leftWindow.width - (leftWindow.width * 0.025), '');
	creditsText.setFormat(Paths.font("arial.ttf"), 18, 0xFF880500, FlxTextAlign.RIGHT);
	add(creditsText);
	creditsText.text += PlayState.SONG.meta.customValues.artists + ' - Art\n' + PlayState.SONG.meta.customValues.coders + ' - Code\n'
		+ PlayState.SONG.meta.customValues.charters + ' - Chart';

	seekHelp = new FlxText(leftWindow.x + 6, leftWindow.y + 590, leftWindow.width - (leftWindow.width * 0.025),
		'Left/Right UI Directionals - Seek Video\nShift - Increase Seek Speed');
	seekHelp.setFormat(Paths.font("arial.ttf"), 18, 0xFF880500, FlxTextAlign.LEFT);
	add(seekHelp);

	var banner = new FunkinSprite(0, 150).loadGraphic(Paths.image("ui/pause/meguca/banner"), true, 669, 102);
	banner.addAnim('banner', null, 0, false, false, [FlxG.random.int(0, 8)]);
	add(banner);
	banner.screenCenter(FlxAxes.X);
	banner.playAnim('banner');

	megucaVideoAudio = new FlxSound().loadEmbedded(Paths.sound('videos/meguca'));
	megucaVideoAudio.volume = 2.0;
	FlxG.sound.list.add(megucaVideoAudio);

	megucaVideo = GenUtil.createVideo("meguca", 0.5, true, 150, 0);
	megucaVideo.bitmap.onFormatSetup.add(function():Void
	{
		if (megucaVideo.bitmap != null && megucaVideo.bitmap.bitmapData != null)
		{
			megucaVideo.x += 145;
		}
		megucaVideoAudio.play();
	});
	add(megucaVideo).cameras = [pauseCam];
	megucaVideo.play();
	megucaVideo.visible = true;

	seekBar = new FunkinSprite(625, 810).loadGraphic(Paths.image('ui/pause/meguca/seekbar'));
	add(seekBar);

	seekTime = new FlxText(seekBar.x + 10, seekBar.y + 10, 150, '-:--');
	seekTime.setFormat(Paths.font("arial.ttf"), 24, 0xFF880500, FlxTextAlign.LEFT);
	add(seekTime);

	seekCirc = new FunkinSprite(690, 813).loadGraphic(Paths.image('ui/pause/meguca/seekcirc'));
	add(seekCirc);

	updateTimer = new FlxTimer().start(0.1, function(tmr:FlxTimer)
	{
		if (controls.LEFT || controls.RIGHT)
			megucaVideo.bitmap.time = megucaVideoAudio.time = megucaVideoPosition;
	}, 0);

	ps_curSel = 0;

	changeSelection(0);
}

function postCreate()
{
}

function update(elapsed:Float)
{
	// trace(sparksVideo);

	if (canControl)
	{
		if (controls.UP_P)
			changeSelection(-1);
		else if (controls.DOWN_P)
			changeSelection(1);

		if (controls.ACCEPT)
			confirmSelection();

		var scrubSpeed:Float = 10000;
		if (FlxG.keys.pressed.SHIFT)
			scrubSpeed = 100000;

		if (controls.LEFT)
		{
			megucaVideo.pause();
			megucaVideoPosition -= scrubSpeed * elapsed;
			megucaVideoAudio.pause();
		}
		else if (controls.RIGHT)
		{
			megucaVideo.pause();
			megucaVideoPosition += scrubSpeed * elapsed;
			megucaVideoAudio.pause();
		}
		else
		{
			megucaVideoPosition += 1000 * elapsed;

			if (megucaVideoPosition >= megucaVideoAudio.length - 1000)
			{
				megucaVideo.pause();
				megucaVideoAudio.pause();
			}
		}

		if (controls.LEFT_R || controls.RIGHT_R)
		{
			megucaVideo.play();
			megucaVideo.bitmap.time = megucaVideoAudio.time = megucaVideoPosition;
			megucaVideoAudio.play();
		}
	}

	megucaVideoPosition = FlxMath.bound(megucaVideoPosition, 0, megucaVideoAudio.length);

	var addZero:Bool = FlxMath.roundDecimal(megucaVideoPosition / 1000) % 60 < 10;

	var mins:Int = FlxMath.roundDecimal(Math.floor(megucaVideoPosition / 60000));

	seekTime.text = mins
		+ ':'
		+ (addZero ? '0' + FlxMath.roundDecimal(megucaVideoPosition / 1000) % 60 : FlxMath.roundDecimal(megucaVideoPosition / 1000) % 60);

	seekCirc.x = 690 + ((megucaVideoPosition / megucaVideoAudio.length) * 848);
}

function changeSelection(change:Int)
{
	ps_curSel = FlxMath.wrap(ps_curSel + change, 0, menu_Texts.length - 1);

	for (i in 0...menu_Texts.length)
	{
		if (menu_Texts[i].ID == ps_curSel)
			menu_Texts[i].text = '> ' + menuOptions[i];
		else
			menu_Texts[i].text = menuOptions[i];
	}
}

function confirmSelection()
{
	canControl = false;

	switch (ps_curSel)
	{
		case 0:
			close();
		case 1:
			PlayState.deathCounter += 1;
			parentDisabler.reset();
			game.registerSmoothTransition();
			FlxG.resetState();
		case 2:
			FlxG.switchState(new ModState("HQSettings", {fromSong: true}));
		case 3:
			godukaEnabled = false;
			godukaCooldown = -1;
			CoolUtil.playMenuSong(false);
			if (PlayState.isStoryMode)
				FlxG.switchState(new ModState("HQMainMenu"));
			else if (PlayState.isGauntletMode)
				FlxG.switchState(new ModState("HQGauntlet"));
			else
				FlxG.switchState(new ModState("HQFreeplay"));
	}
}

function destroy()
{
	megucaVideoAudio.stop();
	updateTimer.cancel();
}
