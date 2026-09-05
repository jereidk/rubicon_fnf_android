import ui.ButtonUI;
import ui.CurrencyPopupUI;
import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import openfl.display.BlendMode;
import gamejolt.GameJolt;
import gamejolt.GJRequest;
import gamejolt.types.RequestType;
import flixel.math.FlxRect;
import funkin.savedata.FunkinSave;
import ui.StoryDiffUI;
import ui.MessageWindowUI;
import ui.GameJoltSignInUI;
import util.PopUpUtil;
import funkin.backend.utils.DiscordUtil;

public static var mm_curSel:Int = 0;
var canControl:Bool = true;
var menuOptions:Array<String> = ['Story', 'Freeplay', 'Gauntlet', 'Accolades', 'Gallery', 'Credits', 'Settings'];
var menu_Buttons:Array<ButtonUI> = [];
var scroll_Tweens:Array<FlxTween> = [];
var menu_Buttons_OriginalX:Array<Float> = [];
var menu_Buttons_OriginalY:Array<Float> = [];
var graphics_Array:Array<FunkinSprite> = [];
var selectingGJ:Bool = false;
var selectingShop:Bool = false;
var newBadges:Array<FunkinSprite> = [];
var newBadgesApplicable:Array<Int> = FlxG.save.data.viewedMenu;
var tickerTween:FlxTween;
var medalInfo:Array<FlxText> = [];

FlxG.sound.load(Paths.sound('ui/ui_storystart'));
function create()
{
	DiscordUtil.changePresenceSince("In Main Menu", null);
	CoolUtil.playMenuSong(false);

	bg_Spr = new FunkinSprite().loadGraphic(Paths.image('ui/common/background'));
	add(bg_Spr);

	bg_Spots = new FlxBackdrop(Paths.image('ui/common/spots'), FlxAxes.XY, 0, 0);
	bg_Spots.alpha = 1.0;
	add(bg_Spots);
	bg_Spots.velocity.set(15, 25);

	bg_Back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back'));
	add(bg_Back);
	bg_Back.blend = BlendMode.MULTIPLY;

	bg_Logo = new FunkinSprite(1300, 125).loadGraphic(Paths.image('ui/main/logo'));
	add(bg_Logo);
	bg_Logo.scale.set(1.0, 1.0);

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	for (i in 0...menuOptions.length)
	{
		var graphic:MainMenuSprite = new MainMenuSprite(menuOptions[i].toLowerCase());
		insert(members.indexOf(bg_BtmBanner), graphic);
		graphics_Array.push(graphic);

		var menu_Button = new ButtonUI(((bg_Logo.x + 90) - (40 * i)), (bg_Logo.y + 150) + (150 * i), 'basic');
		menu_Button.ID = i;
		if (i == 1 && !FlxG.save.data.freeplayUnlocked)
			menu_Button.locked = true;
		if (i == 2 && !FlxG.save.data.gauntletUnlocked)
			menu_Button.locked = true;
		if (i == 3 && !FlxG.save.data.accoladesUnlocked)
			menu_Button.locked = true;
		if (i == 4 && !FlxG.save.data.galleryUnlocked)
			menu_Button.locked = true;

		// if (i == 4)
		//	menu_Button.locked = true;
		menu_Button.text = i18n.tr('Main/${menuOptions[i]}');
		insert(members.indexOf(bg_Logo), menu_Button);
		menu_Buttons.push(menu_Button);

		menu_Buttons_OriginalX.push(menu_Button.group.x);
		menu_Buttons_OriginalY.push(menu_Button.group.y);

		newBadge = new FunkinSprite(menu_Buttons_OriginalX[i] + 385, menu_Buttons_OriginalY[i] + -15).loadGraphic(Paths.image('ui/common/newbadge'));
		insert(members.indexOf(bg_Logo), newBadge);
		newBadge.visible = false;
		newBadges.push(newBadge);
		if (newBadgesApplicable.contains(i) && !menu_Button.locked)
			newBadge.visible = true;

		FlxTween.tween(newBadge, {'scale.x': 1.05, 'scale.y': 1.05}, 0.5, {ease: FlxEase.quadInOut, type: FlxTween.PINGPONG});
	}

	shopgraphic = new MainMenuSprite('shop');
	insert(members.indexOf(bg_BtmBanner), shopgraphic);
	graphics_Array.push(shopgraphic);

	for (i in 0...3)
	{
		newMedal = new FunkinSprite(185 + (150 * i), 835).loadGraphic(Paths.image('ui/common/medal$i'));
		insert(members.indexOf(bg_BtmBanner), newMedal);
		newMedal.color = FlxColor.BLACK;
		newMedal.alpha = 0.5;

		medalText = new FlxText(newMedal.x, newMedal.y, newMedal.width, '');
		medalText.setFormat(Paths.font("shingo.otf"), 14, FlxColor.GRAY, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		medalText.borderSize = 2.5;
		add(medalText);

		switch (i)
		{
			case 0:
				medalText.text = i18n.tr('Main/Medals/AllSongsCleared');
			case 1:
				medalText.text = i18n.tr('Main/Medals/GauntletCleared');
			case 2:
				medalText.text = i18n.tr('Main/Medals/AllAccolades');
		}

		if (i == 0
			&& (FunkinSave.getSongHighscore('stardom', 'easy', null, []).score > 0
				|| FunkinSave.getSongHighscore('stardom', 'hard', null, []).score > 0))
		{
			newMedal.color = FlxColor.WHITE;
			newMedal.alpha = 1.0;
			medalText.color = FlxColor.WHITE;
		}

		if (i == 1 && FlxG.save.data.bestGauntletScoreStandard > 0)
		{
			newMedal.color = FlxColor.WHITE;
			newMedal.alpha = 1.0;
			medalText.color = FlxColor.WHITE;
		}

		if (i == 2 && GenUtil.ownsAllAchievements())
		{
			newMedal.color = FlxColor.WHITE;
			newMedal.alpha = 1.0;
			medalText.color = FlxColor.WHITE;
		}
	}

	gj_Button = new ButtonUI(1750, 825, 'small');
	if (signedIntoGJ)
		gj_Button.icon = 'gamejolt';
	else
		gj_Button.icon = 'gamejoltoff';
	add(gj_Button);

	shop_Button = new ButtonUI(25, 825, 'small');
	shop_Button.icon = 'shop';
	shop_Button.locked = true;
	add(shop_Button);

	fadeoutSprite = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
	fadeoutSprite.scale.set(FlxG.width * 2, FlxG.height * 2);
	add(fadeoutSprite);
	fadeoutSprite.alpha = 0.0;

	changeSelection(0, false);

	tickerBarBG = new FlxSprite(14, 124).loadGraphic(Paths.image('ui/main/ticker'));
	add(tickerBarBG);
	tickerBarBG.alpha = 0.5;

	tickerBarTxt = new FlxText(50, 125, 0, newsText);
	tickerBarTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
	tickerBarTxt.borderSize = 2.5;
	add(tickerBarTxt);
	tickerBarTxt.clipRect = new FlxRect(0, 0, 1275, Std.int(tickerBarTxt.height));
	tickerBarTxt.clipRect = tickerBarTxt.clipRect;

	if (tickerBarTxt.width > 1275)
	{
		tickerTween = FlxTween.num(0, tickerBarTxt.width - 1275, 2.5 + (tickerBarTxt.width / 500), {
			ease: FlxEase.linear,
			type: FlxTween.PERSIST,
			startDelay: 1.5,
			onComplete: function(twn:FlxTween)
			{
				FlxTween.tween(tickerBarTxt, {alpha: 0.0}, 0.5, {
					ease: FlxEase.quadIn,
					startDelay: 2.0,
					onComplete: function(twn:FlxTween)
					{
						tickerBarTxt.x = 50;
						tickerBarTxt.clipRect.x = 0;
						tickerBarTxt.clipRect = tickerBarTxt.clipRect;

						FlxTween.tween(tickerBarTxt, {alpha: 1.0}, 0.5, {
							ease: FlxEase.quadOut,
							onComplete: function(twn:FlxTween)
							{
								tickerTween.start();
							}
						});
					}
				});
			}
		}, function(num:Float)
		{
			tickerBarTxt.x = 50 - num;
			tickerBarTxt.clipRect.x = num;
			tickerBarTxt.clipRect = tickerBarTxt.clipRect;
		});
	}

	outdatedTxt = new FlxText(250, 250, 0, i18n.tr('Main/Outdated'));
	outdatedTxt.setFormat(Paths.font("shingo.otf"), 32, FlxColor.RED, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	outdatedTxt.borderSize = 2.5;
	add(outdatedTxt);
	outdatedTxt.screenCenter(FlxAxes.X);
	outdatedTxt.visible = false;

	if (onOutdatedBuild)
		outdatedTxt.visible = true;
}

function update(elapsed:Float)
{
	if (canControl)
	{
		if (!selectingShop)
		{
			if (controls.UP_P)
			{
				if (selectingGJ)
				{
					selectingGJ = false;
					gj_Button.selected = false;
					changeSelection(0, true);
					GenUtil.playUISound('move');
					return;
				}
				changeSelection(-1, false);
			}
			else if (controls.DOWN_P)
			{
				if (selectingGJ)
				{
					selectingGJ = false;
					gj_Button.selected = false;
					changeSelection(0, true);
					GenUtil.playUISound('move');
					return;
				}
				changeSelection(1, false);
			}

			if (controls.LEFT_P && !selectingGJ)
			{
				selectingShop = true;
				GenUtil.playUISound('move');

				for (i in 0...menu_Buttons.length)
					menu_Buttons[i].selected = false;

				shop_Button.selected = true;

				for (graphic in graphics_Array)
				{
					graphic.hideArt();
				}
				graphics_Array[7].showArt();

				return;
			}

			if (controls.LEFT_P || controls.RIGHT_P)
			{
				selectingGJ = !selectingGJ;
				GenUtil.playUISound('move');
				if (selectingGJ)
				{
					for (i in 0...menu_Buttons.length)
						menu_Buttons[i].selected = false;

					gj_Button.selected = true;
				}
				else
				{
					changeSelection(0, true);
					gj_Button.selected = false;
				}
			}
		}
		else
		{
			if (controls.UP_P || controls.DOWN_P)
			{
				selectingShop = false;
				gj_Button.selected = false;
				changeSelection(0, true);
				GenUtil.playUISound('move');

				shop_Button.selected = false;

				for (graphic in graphics_Array)
				{
					graphic.hideArt();
				}
				graphics_Array[mm_curSel].showArt();
			}
			else if (controls.LEFT_P || controls.RIGHT_P)
			{
				selectingShop = false;
				GenUtil.playUISound('move');

				changeSelection(0, true);
				shop_Button.selected = false;

				for (graphic in graphics_Array)
				{
					graphic.hideArt();
				}
				graphics_Array[mm_curSel].showArt();
			}
		}

		if (controls.ACCEPT)
			confirmSelection();

		if (controls.BACK)
			FlxG.switchState(new ModState("HQTitle"));
	}

	if (controls.DEV_ACCESS)
	{
		persistentUpdate = false;
		persistentDraw = true;
		openSubState(new funkin.editors.EditorPicker());
	}

	if (FlxG.keys.justPressed.NINE && Options.devMode)
	{
		FlxG.switchState(new ModState("HQSHOP"));
	}
}

function confirmSelection()
{
	canControl = false;

	if (!selectingGJ && !selectingShop)
	{
		for (i in 0...menu_Buttons.length)
		{
			if (menu_Buttons[i].ID == mm_curSel)
				menu_Buttons[i].selection();
		}

		if (!menu_Buttons[mm_curSel].locked)
		{
			canControl = false;
			if (mm_curSel != 0)
				GenUtil.playUISound('confirm');

			if (mm_curSel == 2 || mm_curSel == 4 || mm_curSel == 6)
				FlxG.sound.music.stop();

			if (mm_curSel == 0)
			{
				if (FlxG.save.data.curStoryProgress == 0)
				{
					var messageData = {
						leftAction: () ->
						{
							FlxG.save.data.curStoryProgress = 0;
							FlxG.save.data.curStoryDiff = 'easy';
							beginStoryMode('easy');
						},
						rightAction: () ->
						{
							FlxG.save.data.curStoryProgress = 0;
							FlxG.save.data.curStoryDiff = 'hard';
							beginStoryMode('hard');
						},
						completedAction: () ->
						{
							GenUtil.playUISound('confirm');
							storyDiffScreen.destroy();
							remove(storyDiffScreen, true);
							storyDiffScreen = null;
							canControl = false;
						},
						backAction: () ->
						{
							GenUtil.playUISound('back');
							storyDiffScreen.destroy();
							remove(storyDiffScreen, true);
							storyDiffScreen = null;
							canControl = true;
						}
					}
					storyDiffScreen = new StoryDiffUI(messageData);
					add(storyDiffScreen);
				}
				else
				{
					var messageData = {
						nameKey: 'ResumeStory',
						mainTextKey: 'ResumeStory',
						leftTextKey: 'No',
						rightTextKey: 'Yes',
						icon: 'info',
						type: 'twochoice',
						leftAction: () ->
						{
							var messageInfo2 = {
								nameKey: 'RestartStory',
								mainTextKey: 'RestartStory',
								leftTextKey: 'No',
								rightTextKey: 'Yes',
								icon: 'warning',
								type: 'twochoice',
								leftAction: () ->
								{
									canControl = true;
								},
								rightAction: () ->
								{
									FlxG.save.data.curStoryProgress = 0;
									FlxG.save.flush();
									confirmSelection();
								},
								completedAction: () ->
								{
									GenUtil.playUISound('confirm');
									messageWindow2.destroy();
									remove(messageWindow2, true);
									messageWindow2 = null;
								},
								backAction: () ->
								{
									GenUtil.playUISound('back');
									messageWindow2.destroy();
									remove(messageWindow2, true);
									messageWindow2 = null;
									canControl = true;
								}
							}
							messageWindow2 = new MessageWindowUI(messageInfo2);
							add(messageWindow2);
						},
						rightAction: () ->
						{
							beginStoryMode(FlxG.save.data.curStoryDiff);
						},
						completedAction: () ->
						{
							GenUtil.playUISound('confirm');
							messageWindow.destroy();
							remove(messageWindow, true);
							messageWindow = null;
						},
						backAction: () ->
						{
							GenUtil.playUISound('back');
							messageWindow.destroy();
							remove(messageWindow, true);
							messageWindow = null;
							canControl = true;
						}
					}
					messageWindow = new MessageWindowUI(messageData);
					add(messageWindow);
				}
			}

			if (mm_curSel != 0)
			{
				switch (mm_curSel)
				{
					case 1:
						FlxG.switchState(new ModState("HQFreeplay"));
					case 2:
						FlxG.switchState(new ModState("HQGauntlet"));
					case 3:
						FlxG.switchState(new ModState("HQAchievements"));
					case 4:
						FlxG.switchState(new ModState("HQGallery"));
					case 5:
						FlxG.switchState(new ModState("HQCredits"));
					case 6:
						FlxG.switchState(new ModState("HQSettings", {fromSong: false}));
				}
			}
		}
		else
		{
			canControl = true;
			GenUtil.playUISound('error');
		}
	}
	else if (!selectingShop)
	{
		GenUtil.playUISound('confirm');
		canControl = false;
		gj_Button.selection();

		if (signedIntoGJ)
		{
			var messageData = {
				nameKey: 'SignOut',
				mainTextKey: 'SignOut',
				leftTextKey: 'No',
				rightTextKey: 'Yes',
				icon: 'warning',
				type: 'twochoice',
				leftAction: () -> {},
				rightAction: () ->
				{
					GameJolt.userName = '';
					GameJolt.userToken = '';
					FlxG.save.data.curUserName = '';
					FlxG.save.data.userToken = '';
					signedIntoGJ = false;
					gj_Button.icon = 'gamejoltoff';
					FlxG.save.flush();
					PopUpUtil.gjPopup(i18n.tr('GameJolt/SignedOut'));
				},
				completedAction: () ->
				{
					GenUtil.playUISound('confirm');
					messageWindow.destroy();
					messageWindow = null;
					canControl = true;
				},
				backAction: () ->
				{
					GenUtil.playUISound('back');
					messageWindow.destroy();
					messageWindow = null;
					canControl = true;
				}
			}
			messageWindow = new MessageWindowUI(messageData);
			add(messageWindow);
		}
		else
		{
			var loginData = {
				acceptAction: () ->
				{
					GenUtil.playUISound('confirm');
					gjLogin.destroy();
					remove(gjLogin, true);
					gjLogin = null;
					canControl = true;
					gj_Button.icon = 'gamejolt';
					signedIntoGJ = true;
					FlxG.save.flush();
					PopUpUtil.gjPopup(i18n.tr('GameJolt/SignedIn') + ' ${GameJolt.userName}');
				},
				backAction: () ->
				{
					GenUtil.playUISound('back');
					gjLogin.destroy();
					remove(gjLogin, true);
					gjLogin = null;
					canControl = true;
				}
			}
			gjLogin = new GameJoltSignInUI(loginData);
			add(gjLogin);
		}
	}
	else
	{
		canControl = true;
		GenUtil.playUISound('error');
	}
}

function changeSelection(change:Int, skipGraphic:Bool)
{
	if (change != 0)
		GenUtil.playUISound('move');

	mm_curSel = FlxMath.wrap(mm_curSel + change, 0, menu_Buttons.length - 1);

	if (!skipGraphic)
	{
		for (graphic in graphics_Array)
		{
			graphic.hideArt();
		}
		graphics_Array[mm_curSel].showArt();
	}

	if (mm_curSel >= 3)
	{
		scroll_OffsetX = 40 * (mm_curSel - 2);
		scroll_OffsetY = 200 * (mm_curSel - 2);

		if (mm_curSel == 5)
		{
			scroll_OffsetX = 40 * (mm_curSel - 3);
			scroll_OffsetY = 200 * (mm_curSel - 3);
		}
		if (mm_curSel == 6)
		{
			scroll_OffsetX = 40 * (mm_curSel - 4);
			scroll_OffsetY = 200 * (mm_curSel - 4);
		}
	}
	else
	{
		scroll_OffsetX = 0;
		scroll_OffsetY = 0;
	}

	for (tween in scroll_Tweens)
		tween?.cancel();

	for (i in 0...menu_Buttons.length)
	{
		if (menu_Buttons[i].ID == mm_curSel)
			menu_Buttons[i].selected = true;
		else
			menu_Buttons[i].selected = false;

		if (change != 0)
		{
			scroll_Tweens.push(FlxTween.tween(menu_Buttons[i].group,
				{x: menu_Buttons_OriginalX[i] + scroll_OffsetX, y: menu_Buttons_OriginalY[i] - scroll_OffsetY}, 0.5, {ease: FlxEase.expoOut}));

			scroll_Tweens.push(FlxTween.tween(newBadges[i],
				{x: menu_Buttons_OriginalX[i] + scroll_OffsetX + 385, y: menu_Buttons_OriginalY[i] - scroll_OffsetY + -15}, 0.5, {ease: FlxEase.expoOut}));
		}
		else
		{
			menu_Buttons[i].group.setPosition(menu_Buttons_OriginalX[i] + scroll_OffsetX, menu_Buttons_OriginalY[i] - scroll_OffsetY);

			newBadges[i].setPosition(menu_Buttons_OriginalX[i] + scroll_OffsetX + 385, menu_Buttons_OriginalY[i] - scroll_OffsetY + -15);
		}
	}
}

function beginStoryMode(diff:String)
{
	FlxG.sound.play(Paths.sound('ui/ui_storystart'), 1.0 * Options.volumeSFX);
	FlxG.sound.music?.fadeOut(1.5, 0.0);

	FlxG.camera.filters ??= [];
	if (Options.gameplayShaders)
	{
		bloomShader = new CustomShader("Bloom");
		FlxG.camera.addShader(bloomShader);
		FlxTween.num(-0.25, 0.0, 1.5, {
			ease: FlxEase.quadOut
		}, function(num:Float)
		{
			bloomShader.amt = num;
		});

		transverse = new CustomShader("Transverse");
		transverse.falloff = 10;
		transverse.blur = 5.0;
		FlxG.camera.addShader(transverse);
		FlxTween.num(10, 0.5, 2.5, {
			ease: FlxEase.quadOut
		}, function(num:Float)
		{
			transverse.falloff = num;
		});

		adjustColor = new CustomShader("adjustColor");
		adjustColor.saturation = 0.0;
		FlxG.camera.addShader(adjustColor);
		FlxTween.num(0, 200, 2.0, {
			ease: FlxEase.expoIn
		}, function(num:Float)
		{
			adjustColor.saturation = num;
			adjustColor.contrast = num * 2;
		});
	}

	FlxTween.num(0, 25, 2.0, {
		ease: FlxEase.expoIn
	}, function(num:Float)
	{
		FlxG.camera.angle = num;
	});

	FlxTween.num(FlxG.camera.zoom + 0.05, 1.0, 0.5, {
		ease: FlxEase.expoOut,
		onComplete: function(twn:FlxTween)
		{
			FlxTween.num(FlxG.camera.zoom, 5.0, 1.5, {
				ease: FlxEase.expoIn,
				onComplete: function(twn:FlxTween)
				{
					var songsList:Array<Dynamic> = [
						{name: "initium", hide: false},
						{name: "resonance", hide: false},
						{name: "partea", hide: false},
						{name: "eternalstar", hide: false},
						{name: "vexation", hide: false},
						{name: "out-of-time", hide: false}
					];

					for (i in 0...FlxG.save.data.curStoryProgress)
					{
						songsList.shift();
					}

					new FlxTimer().start(0.5, function(tmr:FlxTimer)
					{
						var weekData = {
							songs: songsList,
							name: "Act 1",
							id: "act1",
							difficulties: ["easy", "hard"]
						};

						PlayState.loadWeek(weekData, diff);
						PlayState.isStoryMode = true;
						PlayState.isGauntletMode = false;
						FlxG.switchState(new PlayState());
					});
				}
			}, function(num:Float)
			{
				FlxG.camera.zoom = num;
			});
		}
	}, function(num:Float)
	{
		FlxG.camera.zoom = num;
	});

	FlxTween.tween(fadeoutSprite, {alpha: 1.0}, 1.0, {ease: FlxEase.cubeIn, startDelay: 0.75});
}

class MainMenuSprite extends FunkinSprite
{
	var length:Int = 59;

	public function new(?sprite:String = '')
	{
		super();

		switch (sprite)
		{
			case 'story':
				setPosition(1300, 1000);
				loadSprite(Paths.image("ui/main/anim_story"));
				addAnim('start', 'Story_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Story_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.15, 1.15);

			case 'freeplay':
				setPosition(-2325, -250);
				loadSprite(Paths.image("ui/main/anim_freeplay"));
				addAnim('start', 'Freeplay_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Freeplay_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.15, 1.15);

			case 'gauntlet':
				setPosition(-1250, -1100);
				loadSprite(Paths.image("ui/main/anim_gauntlet"));
				addAnim('start', 'Gauntlet_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Gauntlet_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.1, 1.1);

			case 'credits':
				setPosition(675, 675);
				loadSprite(Paths.image("ui/main/anim_credits"));
				addAnim('start', 'Credits_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Credits_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.15, 1.15);

			case 'accolades':
				setPosition(-1300, 370);
				loadSprite(Paths.image("ui/main/anim_accolades"));
				addAnim('start', 'Accolades_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Accolades_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.2, 1.2);

			case 'gallery':
				setPosition(850, 750);
				loadSprite(Paths.image("ui/main/anim_gallery"));
				addAnim('start', 'Gallery_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
					71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90
				]);
				addAnim('loop', 'Gallery_Animation', 60, true, true, [
					91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
					120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146,
					147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
					174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200,
					201, 202, 203, 204, 205, 206, 207, 208, 209, 210
				]);
				scale.set(1.35, 1.35);

				length = 90;

			case 'settings':
				setPosition(850, 700);
				loadSprite(Paths.image("ui/main/anim_settings"));
				addAnim('start', 'Settings_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Settings_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.2, 1.2);

			case 'shop':
				setPosition(800, 500);
				loadSprite(Paths.image("ui/main/anim_shop"));
				addAnim('start', 'Shop_Animation', 80, false, false, [
					0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
					37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
				]);
				addAnim('loop', 'Shop_Animation', 60, true, true, [
					60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93,
					94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
					123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149,
					150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176,
					177, 178, 179
				]);
				scale.set(1.0, 1.0);
		}
	}

	function showArt()
	{
		playAnim('start', true);
		visible = true;
	}

	function hideArt()
	{
		visible = false;
	}

	override function update(elapsed)
	{
		super.update(elapsed);

		// stupid fix, the end anim checks were not working
		if (globalCurFrame >= length)
		{
			playAnim('loop', false);
		}
	}
}
