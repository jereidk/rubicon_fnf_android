import ui.ButtonUI;
import ui.SettingOptionUI;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import funkin.options.PlayerSettings;
import funkin.backend.system.Controls;
import funkin.savedata.FunkinSave;
import openfl.display.BlendMode;
import openfl.display.BitmapData;
import util.GenUtil;
import ui.MessageWindowUI;
import util.PopUpUtil;
import Sys;
import funkin.backend.utils.DiscordUtil;

public static var sm_curSel:Int = 0;
var inSubMenu:Bool = false;
var sm_curCat:Int = 0;
var sm_subSel:Int = 0;
var scrollOffset:Int = 0;
var metronomeSnd:FlxSound;
var offsettingOption:Bool = false;
var changingKeyBind:Bool = false;
var targetControlOption:SettingOptionUI;
var mainOptions:Array<String> = ['Controls', 'Gameplay', 'Visuals', 'Language', 'Other'];
var mainOptionButtons:Array<ButtonUI> = [];
var targetSettingsArray:Array<Dynamic> = [];
var messageWindow:MessageWindowUI;
var controlSettings:Array<SettingOptionUI> = [];
var canControl:Bool = true;

var controlSettingsList = [
	{
		nameKey: 'LeftNote',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.A],
		parentValue: 'P1_NOTE_LEFT'
	},
	{
		nameKey: 'DownNote',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.S],
		parentValue: 'P1_NOTE_DOWN'
	},
	{
		nameKey: 'UpNote',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.W],
		parentValue: 'P1_NOTE_UP'
	},
	{
		nameKey: 'RightNote',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.D],
		parentValue: 'P1_NOTE_RIGHT'
	},
	{
		type: 'separator'
	},
	{
		nameKey: 'LeftUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.LEFT],
		parentValue: 'P1_LEFT'
	},
	{
		nameKey: 'DownUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.DOWN],
		parentValue: 'P1_DOWN'
	},
	{
		nameKey: 'UpUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.UP],
		parentValue: 'P1_UP'
	},
	{
		nameKey: 'RightUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.RIGHT],
		parentValue: 'P1_RIGHT'
	},
	{
		type: 'separator'
	},
	{
		nameKey: 'Dodge',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.SPACE],
		parentValue: 'P1_DODGE'
	},
	{
		type: 'separator'
	},
	{
		nameKey: 'AcceptUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.ENTER],
		parentValue: 'P1_ACCEPT'
	},
	{
		nameKey: 'BackUI',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.BACKSPACE],
		parentValue: 'P1_BACK'
	},
	{
		nameKey: 'Pause',
		descriptionKey: 'Placeholder Text',
		type: 'control',
		defaultValue: [FlxKey.ENTER],
		parentValue: 'P1_PAUSE'
	}
];

var gameplaySettings:Array<SettingOptionUI> = [];

var gameplaySettingsList = [
	{
		nameKey: 'Downscroll',
		descriptionKey: 'Notes come from the top instead of the bottom',
		type: 'bool',
		defaultValue: false,
		parentValue: 'downscroll'
	},
	{
		nameKey: 'Middlescroll',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'middleScroll'
	},
	{
		nameKey: 'StrumUnderlayAlpha',
		descriptionKey: 'Placeholder Text',
		type: 'int',
		defaultValue: false,
		parentValue: 'strumUnderlayAlpha',
		lowerLimit: 0,
		upperLimit: 100
	},
	{
		nameKey: 'PlayerStrumScale',
		descriptionKey: 'Placeholder Text',
		type: 'float',
		defaultValue: false,
		parentValue: 'playerStrumScale',
		lowerLimit: 1.0,
		upperLimit: 1.3
	},
	{
		nameKey: 'ScrollSpeed',
		descriptionKey: 'Placeholder Text',
		type: 'float',
		defaultValue: false,
		parentValue: 'playerStrumSpeed',
		lowerLimit: 1.0,
		upperLimit: 1.5
	},
	{
		nameKey: 'CamZoomOnBeat',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'camZoomOnBeat'
	},
	/*
		{
			nameKey: 'AutoPause',
			descriptionKey: 'Placeholder Text',
			type: 'bool',
			defaultValue: false,
			parentValue: 'autoPause'
		},
	 */
	{
		nameKey: 'SongOffset',
		descriptionKey: 'Placeholder Text',
		type: 'int',
		defaultValue: 0,
		parentValue: 'songOffset',
		lowerLimit: -999,
		upperLimit: 999
	},
	{
		nameKey: 'ResetButton',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'resetButtonEnabled'
	},
	{
		type: 'separator'
	},
	{
		nameKey: 'StreamedMusic',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'streamedMusic'
	},
	{
		nameKey: 'StreamedVocals',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'streamedVocals'
	}
];

var visualSettings:Array<SettingOptionUI> = [];

var visualSettingsList = [
	{
		nameKey: 'FlashingLights',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'flashingLights'
	},
	{
		nameKey: 'Shaders',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'gameplayShaders'
	},
	{
		nameKey: 'GPUCache',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'gpuOnlyBitmaps'
	},
	{
		nameKey: 'Anti-aliasing',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'antialiasing'
	},
	{
		nameKey: 'LowMemoryMode',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'lowMemoryMode'
	},
	{
		nameKey: 'SplashNotes',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: false,
		parentValue: 'splashesEnabled'
	},
	{
		nameKey: 'Framerate',
		descriptionKey: 'Placeholder Text',
		type: 'int',
		defaultValue: 120,
		parentValue: 'framerate',
		lowerLimit: 60,
		upperLimit: 240
	}
];

var languageSettings:Array<SettingOptionUI> = [];

var languageSettingsList = [
	{
		nameKey: 'English',
		descriptionKey: 'Placeholder Text',
		type: 'language',
		defaultValue: 'en_US',
		parentValue: 'language',
	},
	{
		nameKey: 'Spanish',
		descriptionKey: 'Placeholder Text',
		type: 'language',
		defaultValue: 'es_US',
		parentValue: 'language'
	} // ,
	// {
	//	nameKey: 'Japanese',
	//	descriptionKey: 'Placeholder Text',
	//	type: 'language',
	//	defaultValue: 'ja',
	//	parentValue: 'language'
	// }
];

var otherSettings:Array<SettingOptionUI> = [];

var otherSettingsList = [
	{
		nameKey: 'Mechanics',
		descriptionKey: 'Placeholder Text',
		type: 'bool',
		defaultValue: true,
		parentValue: 'mechanics'
	},
	{
		nameKey: 'DestroySaveData',
		descriptionKey: 'Placeholder Text',
		type: 'deleteData',
		defaultValue: '',
		parentValue: ''
	},
];

function create()
{
	DiscordUtil.changePresenceSince("In Settings", null);
	CoolUtil.playMusic(Paths.music("settings"));

	metronomeSnd = new FlxSound().loadEmbedded(Paths.sound('editors/charter/metronome'));

	bg_Spr = new FunkinSprite().loadGraphic(Paths.image('ui/common/background'));
	add(bg_Spr);

	bg_Spots = new FlxBackdrop(Paths.image('ui/common/spots'), FlxAxes.XY, 0, 0);
	bg_Spots.alpha = 1.0;
	add(bg_Spots);
	bg_Spots.velocity.set(15, 25);

	bg_Back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back'));
	add(bg_Back);
	bg_Back.flipX = true;
	bg_Back.blend = BlendMode.MULTIPLY;

	for (i in 0...mainOptions.length)
	{
		var menu_Button = new ButtonUI((50 + (40 * i)), 175 + (150 * i), 'basic');
		menu_Button.ID = i;
		menu_Button.text = i18n.tr('Settings/Catas/${mainOptions[i]}');

		add(menu_Button);
		mainOptionButtons.push(menu_Button);
	}

	// Generate Options
	for (i in 0...controlSettingsList.length)
	{
		var option = new SettingOptionUI(580 + (i * 35), 180 + (i * 100), controlSettingsList[i]);
		option.ID = i;
		add(option);
		controlSettings.push(option);
	}

	for (i in 0...gameplaySettingsList.length)
	{
		var option = new SettingOptionUI(580 + (i * 35), 180 + (i * 100), gameplaySettingsList[i]);
		option.ID = i;
		add(option);
		gameplaySettings.push(option);
	}

	for (i in 0...visualSettingsList.length)
	{
		var option = new SettingOptionUI(580 + (i * 35), 180 + (i * 100), visualSettingsList[i]);
		option.ID = i;
		add(option);
		visualSettings.push(option);
	}

	for (i in 0...languageSettingsList.length)
	{
		var option = new SettingOptionUI(580 + (i * 35), 180 + (i * 100), languageSettingsList[i]);
		option.ID = i;
		add(option);
		languageSettings.push(option);
	}

	for (i in 0...otherSettingsList.length)
	{
		var option = new SettingOptionUI(580 + (i * 35), 180 + (i * 100), otherSettingsList[i]);
		option.ID = i;
		add(option);
		otherSettings.push(option);
	}

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	changeSelection(0);
}

var holdTime:Float = 0.0;
var lastBeatOffSet:Int = 0;
var lastSongBeatOffset:Int = 0;

function update(elapsed:Float)
{
	if (!changingKeyBind && messageWindow == null && canControl)
	{
		if (!inSubMenu)
		{
			if (controls.UP_P)
				changeSelection(-1);
			else if (controls.DOWN_P)
				changeSelection(1);

			if (FlxG.keys.justPressed.ENTER)
				confirmSelection();
		}
		else
		{
			if (controls.UP_P)
				changeSelection(-1);
			else if (controls.DOWN_P)
				changeSelection(1);
			else if (controls.LEFT_P || controls.RIGHT_P)
			{
				for (option in targetSettingsArray)
				{
					if (option.selected && option.data.type == 'int')
						option.selection((controls.LEFT ? -1 : 1));
					if (option.selected && option.data.type == 'float')
						option.selection((controls.LEFT ? -0.1 : 0.1));
					if (option.selected && option.data.type == 'bool')
						option.selection(0);
				}
			}

			if (controls.LEFT || controls.RIGHT)
			{
				holdTime += elapsed;

				if (holdTime >= 0.5)
				{
					for (option in targetSettingsArray)
					{
						if (option.selected && option.data.type == 'int')
							option.selection((controls.LEFT ? -1 : 1));
						if (option.selected && option.data.type == 'float')
							option.selection((controls.LEFT ? -0.1 : 0.1));
					}
				}
			}
			else
			{
				holdTime = 0;
			}

			if (FlxG.keys.justPressed.ENTER)
				confirmSelection();
		}

		if (controls.BACK)
		{
			backSelection();
		}
	}

	if (changingKeyBind && FlxG.keys.justPressed.ANY)
	{
		finishKeyChange(FlxG.keys.firstJustPressed());
	}

	if (offsettingOption)
	{
		FlxG.sound.music.volume = 0.5;
		if (lastBeatOffSet != Conductor.curBeat)
		{
			FlxG.camera.zoom += 0.03;
			lastBeatOffSet = Conductor.curBeat;
		}

		var beat = Math.floor(Conductor.getTimeInBeats(FlxG.sound.music.time));
		if (lastSongBeatOffset != beat)
		{
			metronomeSnd.play();
			lastSongBeatOffset = beat;
		}
	}
	else
	{
		FlxG.sound.music.volume = 1.0;
	}
	FlxG.camera.zoom = CoolUtil.fpsLerp(FlxG.camera.zoom, 1, 0.25);

	scrollOffset = sm_subSel - 3;

	for (spr in controlSettings)
	{
		spr.group.offset.x = CoolUtil.fpsLerp(spr.group.offset.x, 35 * FlxMath.bound(scrollOffset, 0, controlSettings.length - 7), 0.25);
		spr.group.offset.y = CoolUtil.fpsLerp(spr.group.offset.y, 100 * FlxMath.bound(scrollOffset, 0, controlSettings.length - 7), 0.25);
	}
	for (spr in gameplaySettings)
	{
		spr.group.offset.x = CoolUtil.fpsLerp(spr.group.offset.x, 35 * FlxMath.bound(scrollOffset, 0, gameplaySettings.length - 7), 0.25);
		spr.group.offset.y = CoolUtil.fpsLerp(spr.group.offset.y, 100 * FlxMath.bound(scrollOffset, 0, gameplaySettings.length - 7), 0.25);
	}
	for (spr in visualSettings)
	{
		// spr.group.offset.x = CoolUtil.fpsLerp(spr.group.offset.x, 35 * FlxMath.bound(scrollOffset, 0, visualSettings.length), 0.25);
		// spr.group.offset.y = CoolUtil.fpsLerp(spr.group.offset.y, 100 * FlxMath.bound(scrollOffset, 0, visualSettings.length), 0.25);
	}
}

function confirmSelection()
{
	if (!inSubMenu)
	{
		for (i in 0...mainOptionButtons.length)
		{
			if (mainOptionButtons[i].ID == sm_curSel)
				mainOptionButtons[i].selection(0);
		}

		if (!mainOptionButtons[sm_curSel].locked)
		{
			GenUtil.playUISound('confirm');

			sm_curCat = sm_curSel;

			inSubMenu = true;
			updateSubMenu();
		}
		else
		{
			GenUtil.playUISound('error');
		}
	}
	else
	{
		for (option in targetSettingsArray)
		{
			if (option.data.type == 'language' && !option.selected)
				option.option_Setting.text = '';
			if (option.selected && (option.data.type == 'bool' || option.data.type == 'language'))
			{
				option.selection(0);
				if (option.data.type == 'language')
				{
					i18n.loadFromString(Assets.getText('data/langs/${Options.language}/translations.json'));
					FlxG.resetState();
				}
			}
			if (option.selected && option.data.type == 'control')
			{
				new FlxTimer().start(0.0001, function(tmr:FlxTimer)
				{
					changingKeyBind = true;
					targetControlOption = option;
					promptKeyChange();
				});
			}
			if (option.selected && (option.data.type == 'deleteData'))
			{
				if (!data.fromSong)
				{
					var messageData = {
						nameKey: 'DeleteData',
						mainTextKey: 'DeleteData',
						leftTextKey: 'No',
						rightTextKey: 'Yes',
						icon: 'danger',
						type: 'twochoice',
						leftAction: () -> {},
						rightAction: () ->
						{
							FlxG.save.data.tutorialCompleted = false;
							FlxG.save.data.kyubeyCoins = 0;
							FlxG.save.data.unlockedSongs = [];
							FlxG.save.data.unlockableSongs = [];

							FlxG.save.data.curStoryProgress = 0;
							FlxG.save.data.curStoryDiff = 'hard';

							FlxG.save.data.unlockedAchievements = [];
							FlxG.save.data.canUseGameJoltSync = true;

							FlxG.save.data.bestGauntletScoreStandard = 0;
							// FlxG.save.data.bestGauntletScoreEndless = 0;

							// GJ Stuff
							FlxG.save.data.curUserName = '';
							FlxG.save.data.curUserToken = '';

							// Achievement progress data
							FlxG.save.data.pinpointAccuracyProgress = 0;
							FlxG.save.data.devotedProgress = 0;

							// Startup
							FlxG.save.data.firstTimeSetupDone = false;
							FlxG.save.data.seeIntro = true;

							// Post Story mode content
							FlxG.save.data.freeplayUnlocked = false;
							FlxG.save.data.gauntletUnlocked = false;
							FlxG.save.data.accoladesUnlocked = false;
							FlxG.save.data.galleryUnlocked = false;
							FlxG.save.data.viewedMenu = [1, 2, 3, 4];

							if (signedIntoGJ)
							{
								PopUpUtil.gjPopup(i18n.tr('GameJolt/SignedOutForced'));
								signedIntoGJ = false;
							}

							Options.__save.erase();
							Options.__save.flush();
							FlxG.save.flush();

							FunkinSave.save.erase();
							FunkinSave.highscores.clear();
							FunkinSave.flush();
							FlxG.save.flush();

							Sys.exit();
						},
						completedAction: () ->
						{
							GenUtil.playUISound('confirm');
							messageWindow.destroy();
							messageWindow = null;
						},
						backAction: () ->
						{
							GenUtil.playUISound('back');
							messageWindow.destroy();
							messageWindow = null;
						}
					}
					messageWindow = new MessageWindowUI(messageData);
					add(messageWindow);
				}
				else
				{
					GenUtil.playUISound('error');
				}
			}
		}
	}
}

function updateSubMenu()
{
	switch (sm_curCat)
	{
		case 0:
			targetSettingsArray = controlSettings;
		case 1:
			targetSettingsArray = gameplaySettings;
		case 2:
			targetSettingsArray = visualSettings;
		case 3:
			targetSettingsArray = languageSettings;
		case 4:
			targetSettingsArray = otherSettings;
	}

	for (option in targetSettingsArray)
	{
		option.active = true;
	}
	for (button in mainOptionButtons)
	{
		button.group.color = FlxColor.GRAY;
	}

	changeSelection(0);
}

function changeSelection(change:Int)
{
	if (!inSubMenu)
	{
		if (change != 0)
			GenUtil.playUISound('move');

		sm_curSel = FlxMath.wrap(sm_curSel + change, 0, mainOptionButtons.length - 1);

		for (i in 0...mainOptionButtons.length)
		{
			if (mainOptionButtons[i].ID == sm_curSel)
				mainOptionButtons[i].selected = true;
			else
				mainOptionButtons[i].selected = false;
		}

		for (grp in controlSettings)
			grp.group.visible = (sm_curSel == 0 ? true : false);
		for (grp in gameplaySettings)
			grp.group.visible = (sm_curSel == 1 ? true : false);
		for (grp in visualSettings)
			grp.group.visible = (sm_curSel == 2 ? true : false);
		for (grp in languageSettings)
			grp.group.visible = (sm_curSel == 3 ? true : false);
		for (grp in otherSettings)
			grp.group.visible = (sm_curSel == 4 ? true : false);
	}
	else
	{
		if (change != 0)
			GenUtil.playUISound('move');

		sm_subSel = FlxMath.wrap(sm_subSel + change, 0, targetSettingsArray.length - 1);

		for (i in 0...targetSettingsArray.length)
		{
			if (targetSettingsArray[i].ID == sm_subSel && targetSettingsArray[i].data.type == 'separator')
				sm_subSel = FlxMath.wrap(sm_subSel + change, 0, targetSettingsArray.length - 1);
		}

		offsettingOption = false;
		for (i in 0...targetSettingsArray.length)
		{
			if (targetSettingsArray[i].ID == sm_subSel)
				targetSettingsArray[i].selected = true;
			else
				targetSettingsArray[i].selected = false;

			if (targetSettingsArray[i].ID == sm_subSel && targetSettingsArray[i].data.nameKey == 'SongOffset')
				offsettingOption = true;
		}
	}
}

function backSelection()
{
	GenUtil.playUISound('back');

	if (!inSubMenu)
	{
		canControl = false;
		FlxG.sound.music.stop();
		!data.fromSong ? FlxG.switchState(new ModState("HQMainMenu")) : FlxG.switchState(new PlayState());
	}
	else
	{
		inSubMenu = false;
		updateSubMenu();
		sm_subSel = 0;

		for (option in targetSettingsArray)
		{
			option.selected = false;
			option.active = false;
		}
	}

	offsettingOption = false;
}

var overlay:FlxSprite;
var overlayRebindText:FlxText;

function promptKeyChange()
{
	overlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	overlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(overlay);
	overlay.alpha = 0.5;

	overlayRebindText = new FlxText(0, 0, FlxG.width, i18n.tr('Settings/RebindPrompt') + ' ' + i18n.tr('Settings/${targetControlOption.data.nameKey}'));
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
	Reflect.setField(Options, targetControlOption.data.parentValue, [newKey]);
	Options.applyKeybinds();
	targetControlOption.option_Setting.text = targetControlOption.formatCurOption();
	changingKeyBind = false;
}
