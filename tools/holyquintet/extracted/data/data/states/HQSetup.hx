import util.GenUtil;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import ui.MessageWindowUI;

var canControl:Bool = false;
var step:Int = 0;
var currentKey:Int = 0;
var keyNames:Array<Dynamic> = ['LeftNote', 'DownNote', 'UpNote', 'RightNote'];
var keyValues:Array<Dynamic> = ['P1_NOTE_LEFT', 'P1_NOTE_DOWN', 'P1_NOTE_UP', 'P1_NOTE_RIGHT'];
var changingKeyBind:Bool = false;

function create()
{
	// i thought i preloaded the videos and its like only a few days before release so this is a really bad fix for now i think grahhhh
	preloadedVid1 = GenUtil.createVideo("intro_start", 0.1, true, 0, 0);
	add(preloadedVid1);
	preloadedVid1.play();
	preloadedVid1.pause();
	preloadedVid1.visible = false;

	preloadedVid2 = GenUtil.createVideo("intro_yes", 0.1, true, 0, 0);
	add(preloadedVid2);
	preloadedVid2.play();
	preloadedVid2.pause();
	preloadedVid2.visible = false;

	preloadedVid3 = GenUtil.createVideo("intro_no", 0.1, true, 0, 0);
	add(preloadedVid3);
	preloadedVid3.play();
	preloadedVid3.pause();
	preloadedVid3.visible = false;

	if (!FlxG.save.data.firstTimeSetupDone)
	{
		progressSetup();

		/*
			var messageData = {
				nameKey: 'Language',
				mainTextKey: 'Language',
				leftTextKey: 'No',
				rightTextKey: 'Yes',
				icon: 'info',
				type: 'languagechoose',
				leftAction: () -> {},
				rightAction: () -> {},
				completedAction: () ->
				{
					GenUtil.playUISound('confirm');
					messageWindow.destroy();
					messageWindow = null;
					progressSetup();
				},
				backAction: () -> {}
			}
			messageWindow = new MessageWindowUI(messageData);
			add(messageWindow);
		 */
	}
	else if (FlxG.save.data.firstTimeSetupDone && FlxG.save.data.seeIntro)
	{
		FlxG.switchState(new ModState("HQIntro"));
	}
}

function postCreate()
{
	new FlxTimer().start(0.5, function(tmr:FlxTimer)
	{
		if (FlxG.save.data.firstTimeSetupDone)
		{
			if (FlxG.save.data.seeIntro)
				FlxG.switchState(new ModState("HQIntro"));
			else
				FlxG.switchState(new ModState("HQDisclaimer"));
		}
	}, 0);
}

function update(elapsed:Float)
{
	if (changingKeyBind && FlxG.keys.justPressed.ANY)
	{
		finishKeyChange(FlxG.keys.firstJustPressed());
	}
}

function progressSetup()
{
	step += 1;

	new FlxTimer().start(0.5, function(tmr:FlxTimer)
	{
		switch (step)
		{
			case 1:
				var messageData = {
					nameKey: 'FirstTimeSetup',
					mainTextKey: 'FirstTimeSetup',
					leftTextKey: 'No',
					rightTextKey: 'Yes',
					icon: 'warning',
					type: 'twochoice',
					leftAction: () ->
					{
						step = 4;
						progressSetup();
					},
					rightAction: () ->
					{
						progressSetup();
					},
					completedAction: () ->
					{
						GenUtil.playUISound('confirm');
						messageWindow2.destroy();
						messageWindow2 = null;
					},
					backAction: () -> {}
				}
				messageWindow2 = new MessageWindowUI(messageData);
				add(messageWindow2);

			case 2:
				var messageData = {
					nameKey: 'KeepFlashingLights',
					mainTextKey: 'KeepFlashingLights',
					leftTextKey: 'No',
					rightTextKey: 'Yes',
					icon: 'danger',
					type: 'twochoice',
					leftAction: () ->
					{
						Options.flashingLights = false;
						progressSetup();
					},
					rightAction: () ->
					{
						Options.flashingLights = true;
						progressSetup();
					},
					completedAction: () ->
					{
						GenUtil.playUISound('confirm');
						messageWindow.destroy();
						messageWindow = null;
					},
					backAction: () -> {}
				}
				messageWindow = new MessageWindowUI(messageData);
				add(messageWindow);

			case 3:
				var messageData = {
					nameKey: 'SetControlScheme',
					mainTextKey: 'SetControlScheme',
					leftTextKey: 'No',
					rightTextKey: 'Yes',
					icon: 'warning',
					type: 'twochoice',
					leftAction: () ->
					{
						Options.flashingLights = true;
						progressSetup();
					},
					rightAction: () ->
					{
						promptKeyChange(0);
					},
					completedAction: () ->
					{
						GenUtil.playUISound('confirm');
						messageWindow.destroy();
						messageWindow = null;
					},
					backAction: () -> {}
				}
				messageWindow = new MessageWindowUI(messageData);
				add(messageWindow);

			case 4:
				var messageData = {
					nameKey: 'DownscrollPreference',
					mainTextKey: 'DownscrollPreference',
					leftTextKey: 'Upscroll',
					rightTextKey: 'Downscroll',
					icon: 'warning',
					type: 'twochoice',
					leftAction: () ->
					{
						Options.downscroll = false;
						progressSetup();
					},
					rightAction: () ->
					{
						Options.downscroll = true;
						progressSetup();
					},
					completedAction: () ->
					{
						GenUtil.playUISound('confirm');
						messageWindow.destroy();
						messageWindow = null;
					},
					backAction: () -> {}
				}
				messageWindow = new MessageWindowUI(messageData);
				add(messageWindow);
			case 5:
				FlxG.save.data.firstTimeSetupDone = true;
				FlxG.save.flush();
				FlxG.switchState(new ModState("HQIntro"));
		}
	});
}

function confirmSelection()
{
}

var overlay:FlxSprite;
var overlayRebindText:FlxText;

function promptKeyChange(keyint:Int)
{
	changingKeyBind = true;
	overlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	overlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(overlay);
	overlay.alpha = 0.5;

	overlayRebindText = new FlxText(0, 0, FlxG.width, i18n.tr('Settings/RebindPrompt') + ' ' + i18n.tr('Settings/${keyNames[keyint]}'));
	overlayRebindText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	overlayRebindText.borderSize = 2.0;
	add(overlayRebindText);
	overlayRebindText.screenCenter();
}

function finishKeyChange(newKey:FlxKey)
{
	overlay?.destroy();
	overlayRebindText?.destroy();
	remove(overlay, true);
	remove(overlayRebindText, true);
	Reflect.setField(Options, keyValues[currentKey], [newKey]);
	Options.applyKeybinds();
	changingKeyBind = false;

	currentKey += 1;
	if (currentKey <= 3)
		promptKeyChange(currentKey);
	else
	{
		progressSetup();
	}
}

function promptKey()
{
}
