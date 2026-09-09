import flixel.addons.display.FlxBackdrop;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.options.OptionsMenu;
import openfl.display.BlendMode;
import BlurFilter;
import ui.ButtonUI;

public static var ps_curSel:Int = 0;
var canControl:Bool = true;
var menuOptions:Array<String> = ['Resume', 'Restart', 'Settings', 'Quit'];
var menu_Buttons:Array<ButtonUI> = [];
var blur:BlurFilter;
var pauseMusic:FlxSound;

function create(e)
{
	e.cancel();

	camera = pauseCam = new FlxCamera();
	pauseCam.bgColor = FlxColor.TRANSPARENT;
	FlxG.cameras.add(pauseCam, false);

	var color:FlxColor = FlxColor.BLACK;
	if (PlayState.instance.dad != null)
		color = PlayState.instance.dad.iconColor;

	bg = new FlxSprite(0, 0).makeGraphic(1, 1, color);
	bg.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(bg);
	bg.blend = BlendMode.ADD;
	bg.alpha = 0.5;

	spots = new FlxBackdrop(Paths.image('ui/pause/spots'), FlxAxes.XY, 0, 0);
	spots.alpha = 0.25;
	spots.blend = BlendMode.ADD;
	add(spots);
	spots.velocity.set(15, 25);

	back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back'));
	add(back);
	back.flipX = true;
	back.blend = BlendMode.MULTIPLY;

	for (i in 0...menuOptions.length)
	{
		var menu_Button = new ButtonUI(50 + (40 * i), 175 + (150 * i), 'basic');
		menu_Button.ID = i;
		menu_Button.text = i18n.tr('Gameplay/Pause/${menuOptions[i]}');
		add(menu_Button);
		menu_Buttons.push(menu_Button);

		menu_Button.group.y += 65;
	}

	var pauseName:String = 'gf';
	if (PlayState.instance.dad != null)
		pauseName = PlayState.instance.dad.curCharacter;

	switch (pauseName)
	{
		case 'gf-base':
			pauseName = 'gf';
		case 'sayaka-base':
			pauseName = 'sayaka';
		case 'madoka-base':
			pauseName = 'madoka';
		case 'kyoko-base':
			pauseName = 'kyoko';
		case 'mami-base':
			pauseName = 'mami';
		case 'homura-base':
			pauseName = 'homura';
	}

	pauseChar = new FunkinSprite();
	pauseChar.loadSprite(Paths.image("ui/pause/" + pauseName));
	pauseChar.addAnim('bop', 'bop', 24, true, false);
	pauseChar.scale.set(0.9, 0.9);
	pauseChar.updateHitbox();
	pauseChar.setPosition((FlxG.width - (pauseChar.width / 2)) * 0.5, (FlxG.height - (pauseChar.height / 2)) * 0.25);
	add(pauseChar);
	pauseChar.playAnim('bop');

	switch (pauseName)
	{
		case 'gf':
			pauseChar.y += 125;
	}

	creditsBG = new FunkinSprite().loadGraphic(Paths.image('ui/pause/creditsbg'));
	creditsBG.setPosition((FlxG.width - creditsBG.width) * 1, (FlxG.height - (creditsBG.height / 2)) * 0.80);
	add(creditsBG);

	creditsText = new FlxText(creditsBG.x - 974, creditsBG.y + (creditsBG.height * 0.115), creditsBG.width + (creditsBG.width * 2), '');
	creditsText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	creditsText.borderSize = 3.5;
	add(creditsText);
	creditsText.text += PlayState.SONG.meta.customValues.artists + ' - Art\n' + PlayState.SONG.meta.customValues.coders + ' - Code\n'
		+ PlayState.SONG.meta.customValues.charters + ' - Chart';

	creditsMusicBG = new FunkinSprite().loadGraphic(Paths.image('ui/pause/creditsbg'));
	creditsMusicBG.setPosition((FlxG.width - creditsMusicBG.width) * 1, (FlxG.height - (creditsMusicBG.height / 2)) * 0.15);
	add(creditsMusicBG);

	creditsMusicNameText = new FlxText(creditsMusicBG.x, creditsMusicBG.y + (creditsMusicBG.height * 0.115),
		creditsMusicBG.width - (creditsMusicBG.width * 0.025), '');
	creditsMusicNameText.setFormat(Paths.font("shingo.otf"), 64, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	creditsMusicNameText.borderSize = 3.5;
	add(creditsMusicNameText);
	creditsMusicNameText.text = PlayState.SONG.meta.displayName;

	creditsMusicCompText = new FlxText(creditsMusicBG.x, creditsMusicNameText.y + creditsMusicNameText.height,
		creditsMusicBG.width - (creditsMusicBG.width * 0.025), '');
	creditsMusicCompText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	creditsMusicCompText.borderSize = 3.5;
	add(creditsMusicCompText);
	creditsMusicCompText.text = PlayState.SONG.meta.customValues.composers;

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	// Fade in Animation
	back.x -= 100;
	bg_TopBanner.y -= bg_TopBanner.height;
	bg_BtmBanner.y += bg_BtmBanner.height;
	creditsBG.x += 250;
	creditsMusicBG.x += 250;
	creditsText.x += 250;
	creditsMusicNameText.x += 250;
	creditsMusicCompText.x += 250;
	for (spr in [
		back,
		bg,
		spots,
		creditsBG,
		creditsMusicBG,
		creditsText,
		creditsMusicNameText,
		creditsMusicCompText,
		bg_TopBanner,
		bg_BtmBanner,
		pauseChar
	])
		spr.alpha = 0.0;

	FlxTween.tween(bg, {alpha: 0.5}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(spots, {alpha: 0.4}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(back, {alpha: 1.0, x: back.x + 100}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(bg_TopBanner, {alpha: 1.0, y: bg_TopBanner.y + bg_TopBanner.height}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(bg_BtmBanner, {alpha: 1.0, y: bg_BtmBanner.y - bg_BtmBanner.height}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(creditsBG, {alpha: 1.0, x: creditsBG.x - 250}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(creditsMusicBG, {alpha: 1.0, x: creditsMusicBG.x - 250}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(creditsText, {alpha: 1.0, x: creditsText.x - 250}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(creditsMusicNameText, {alpha: 1.0, x: creditsMusicNameText.x - 250}, 1.0, {ease: FlxEase.expoOut});
	FlxTween.tween(creditsMusicCompText, {alpha: 1.0, x: creditsMusicCompText.x - 250}, 1.0, {ease: FlxEase.expoOut});

	for (btn in menu_Buttons)
	{
		btn.group.x -= 100;
		FlxTween.tween(btn.group, {x: btn.group.x + 100}, 1.0, {ease: FlxEase.expoOut});
	}

	new FlxTimer().start(0.30, function(tmr:FlxTimer)
	{
		FlxTween.tween(pauseChar, {alpha: 1.0}, 1.0, {ease: FlxEase.backOut});
		FlxTween.tween(pauseChar, {y: pauseChar.y - 50}, 0.3, {
			ease: FlxEase.quadOut,
			onComplete: function(tween:FlxTween)
			{
				FlxTween.tween(pauseChar, {y: pauseChar.y + 50}, 0.30, {ease: FlxEase.quadIn});
			}
		});
	});

	if (Options.gameplayShaders)
	{
		blur = new BlurFilter(0.0);
		for (cam in FlxG.cameras.list)
		{
			if (cam != pauseCam)
				blur.apply(cam);
		}

		FlxTween.num(0.0, 15, 0.50, {ease: FlxEase.expoOut}, function(num:Float)
		{
			blur.set(num);
		});
	}

	var affix:String = '-main';
	if (PlayState.SONG.meta.name == 'meguca' || PlayState.SONG.meta.name == 'reconnect' || PlayState.SONG.meta.name == 'stardom')
		affix = '-freeplay';

	pauseMusic = new FlxSound().loadEmbedded(Paths.music('pause$affix'), true);
	FlxG.sound.list.add(pauseMusic);

	pauseMusic.volume = 0.0;
	pauseMusic.fadeIn(1.0, 0.0, 1.0);

	ps_curSel = 0;

	changeSelection(0);
}

function postCreate()
{
}

function update(elapsed:Float)
{
	if (canControl)
	{
		if (controls.UP_P)
			changeSelection(-1);
		else if (controls.DOWN_P)
			changeSelection(1);

		if (controls.ACCEPT)
			confirmSelection();
	}
}

function changeSelection(change:Int)
{
	if (change != 0)
		GenUtil.playUISound('move');

	ps_curSel = FlxMath.wrap(ps_curSel + change, 0, menu_Buttons.length - 1);

	for (i in 0...menu_Buttons.length)
	{
		if (menu_Buttons[i].ID == ps_curSel)
			menu_Buttons[i].selected = true;
		else
			menu_Buttons[i].selected = false;
	}
}

function confirmSelection()
{
	GenUtil.playUISound('confirm');

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
	if (Options.gameplayShaders)
	{
		for (cam in FlxG.cameras.list)
		{
			if (cam != pauseCam)
				blur.remove(cam);
		}
	}

	pauseMusic.stop();
	FlxG.sound.list.remove(pauseMusic, true);
}
