import ui.ButtonUI;
import ui.achievement.AchievementUI;
import flixel.addons.display.FlxBackdrop;
import flixel.input.keyboard.FlxKey;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import funkin.options.PlayerSettings;
import funkin.backend.system.Controls;
import openfl.display.BlendMode;
import openfl.display.BitmapData;
import util.GenUtil;
import ui.MessageWindowUI;
import funkin.backend.utils.DiscordUtil;

public static var am_curSel:Int = 0;
var inSubMenu:Bool = false;
var targetSettingsArray:Array<Dynamic> = [];
var messageWindow:MessageWindowUI;
var achievements:Array<AchievementUI> = [];
var canControl:Bool = true;

var achievementsList:Array<String> = [
	'FCInitium',
	'FCResonance',
	'FCPartea',
	'FCEternalStar',
	'FCVexation',
	'FCOutOfTime',
	'CompleteAct1',
	'FCMeguca',
	'FCReconnect',
	'FCStardom',
	'ResOutheal',
	'VexYikes',
	'YoureOnMyTime',
	'TimeWaitsForMe',
	'Tenacious',
	'ThanksForPlaying',
	'ChamberOfLight',
	'PinpointAccuracy',
	'Devoted'
];

function create()
{
	DiscordUtil.changePresenceSince("In Achievements", null);
	bg_Spr = new FlxBackdrop(Paths.image('ui/common/background_gj'), FlxAxes.XY, 0, 0);
	add(bg_Spr);
	bg_Spr.color = FlxColor.GRAY;
	bg_Spr.velocity.set(15, 15);

	bg_Back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back_straight'));
	add(bg_Back);
	bg_Back.flipX = true;
	bg_Back.blend = BlendMode.MULTIPLY;

	// button_toLeaderBoards = new ButtonUI(15, 820, 'basic');
	// button_toLeaderBoards.text = 'Leaderboards';
	// add(button_toLeaderBoards);

	button_syncToGJ = new ButtonUI(15, 820, 'gj');
	button_syncToGJ.text = 'Sync to Game Jolt';
	add(button_syncToGJ);

	selectedAchievement = new AchievementUI(120, 250, achievementsList[am_curSel]);
	add(selectedAchievement);
	selectedAchievement.selected = true;
	selectedAchievement.group.scale.set(1.25, 1.25);

	achievementName = new FlxText(selectedAchievement.group.x
		- 100, selectedAchievement.group.y
		+ selectedAchievement.group.height
		+ 32,
		selectedAchievement.group.width
		+ 200, '');
	achievementName.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	achievementName.borderSize = 2.5;
	add(achievementName);

	achievementDescription = new FlxText(achievementName.x, achievementName.y + 64, achievementName.width, '');
	achievementDescription.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	achievementDescription.borderSize = 2.5;
	add(achievementDescription);
	achievementDescription.alpha = 0.8;

	// Generate Achievments
	var xPos:Float = 545;
	var yPos:Float = 105;
	for (i in 0...achievementsList.length)
	{
		var achievement = new AchievementUI(xPos, yPos, achievementsList[i]);
		achievement.ID = i;
		add(achievement);
		achievement.group.scale.set(0.75, 0.75);
		achievements.push(achievement);

		xPos += 215;
		if (i % 6 == 5)
		{
			xPos = 545;
			yPos += 205;
		}
	}

	selector = new FunkinSprite().loadGraphic(Paths.image('ui/accolades/selector'));
	add(selector);
	selector.scale.set(0.75, 0.75);
	FlxTween.tween(selector, {'scale.x': 0.8, 'scale.y': 0.8}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	// Tracker
	tracker_BG = new FunkinSprite(36, 711).loadGraphic(Paths.image('ui/accolades/progressback'));
	add(tracker_BG);

	tracker_Bar = new FunkinSprite(tracker_BG.x + 5, tracker_BG.y + 4).loadGraphic(Paths.image('ui/accolades/progress'));
	add(tracker_Bar);
	tracker_Bar.clipRect = new FlxRect(0, 0, Std.int(tracker_Bar.width), Std.int(tracker_Bar.height));

	tracker_text = new FlxText(tracker_BG.x, tracker_BG.y, tracker_BG.width, '');
	tracker_text.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
	tracker_text.borderSize = 2.5;
	add(tracker_text);
	GenUtil.alignToCenter(tracker_text, tracker_BG);

	changeSelection(0);

	if (FlxG.save.data.viewedMenu.contains(3))
	{
		FlxG.save.data.viewedMenu.remove(3);
		FlxG.save.flush();
	}
}

function update(elapsed:Float)
{
	if (messageWindow == null && canControl)
	{
		if (controls.UP_P)
			changeSelection(-6);
		else if (controls.DOWN_P)
			changeSelection(6);

		if (controls.LEFT_P)
		{
			changeSelection(-1);
		}
		else if (controls.RIGHT_P)
			changeSelection(1);

		if (FlxG.keys.justPressed.ENTER && FlxG.save.data.canUseGameJoltSync && signedIntoGJ && inSubMenu && !onOutdatedBuild && !lockGJprogression)
		{
			confirmSelection();
		}
		else if (FlxG.keys.justPressed.ENTER && inSubMenu)
		{
			GenUtil.playUISound('error');
		}

		if (controls.BACK)
		{
			backSelection();
		}
	}
}

function confirmSelection()
{
	if (inSubMenu)
	{
		var messageData = {
			nameKey: 'SyncGameJolt',
			mainTextKey: 'SyncGameJolt',
			leftTextKey: 'No',
			rightTextKey: 'Yes',
			icon: 'warning',
			type: 'twochoice',
			leftAction: () -> {},
			rightAction: () ->
			{
				syncGameJoltAchievements();
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
}

function syncGameJoltAchievements()
{
	var achievementsToSync:Array<String> = [];

	for (i in 0...achievementsList.length)
	{
		if (!GenUtil.isAchievementLocked(achievementsList[i]))
			achievementsToSync.push(achievementsList[i]);
	}

	GenUtil.achievementBatchUnlock(achievementsToSync);

	FlxG.save.data.canUseGameJoltSync = false;
	FlxG.save.flush();
}

function changeSelection(change:Int)
{
	if (change != 0)
		GenUtil.playUISound('move');

	if (am_curSel % 6 == 0 && change == -1)
	{
		inSubMenu = true;
	}
	else if (inSubMenu && change == 1)
	{
		inSubMenu = false;
		change = 0;
	}

	if (inSubMenu)
	{
		for (i in 0...achievements.length)
		{
			achievements[i].selected = false;
		}

		button_syncToGJ.selected = true;
		selector.color = FlxColor.GRAY;
	}
	else
	{
		am_curSel = FlxMath.wrap(am_curSel + change, 0, achievements.length - 1);

		for (i in 0...achievements.length)
		{
			if (achievements[i].ID == am_curSel)
			{
				achievements[i].selected = true;
				updateTexts(achievements[i].data);
				selectedAchievement.updateAchievementGraphic(achievementsList[am_curSel]);
				selector.setPosition(achievements[i].group.x, achievements[i].group.y);
			}
			else
				achievements[i].selected = false;
		}

		button_syncToGJ.selected = false;
		selector.color = FlxColor.WHITE;

		var showProgress:Bool = false;
		var curProgress:Int = 0;

		if (achievementsList[am_curSel] == 'PinpointAccuracy' || achievementsList[am_curSel] == 'Devoted')
		{
			showProgress = true;

			switch (achievementsList[am_curSel])
			{
				case 'PinpointAccuracy':
					curProgress = FlxG.save.data.pinpointAccuracyProgress;
				case 'Devoted':
					curProgress = FlxG.save.data.devotedProgress;
			}

			if (!GenUtil.isAchievementLocked(achievementsList[am_curSel]))
				showProgress = false;
		}

		if (showProgress)
		{
			var data = achievementData.get(achievementsList[am_curSel]);

			tracker_Bar.clipRect.width = (curProgress / data.trackerGoal) * Std.int(tracker_Bar.width);
			tracker_Bar.clipRect = tracker_Bar.clipRect;

			tracker_text.text = FlxStringUtil.formatMoney(curProgress, false) + '/' + FlxStringUtil.formatMoney(data.trackerGoal, false);
			tracker_text.size = 32;

			if (curProgress >= data.trackerGoal)
			{
				tracker_text.text = i18n.tr('Accolades/ClearToEarn');
				tracker_text.size = 28;
			}

			tracker_BG.visible = true;
			tracker_Bar.visible = true;
			tracker_text.visible = true;
		}
		else
		{
			tracker_BG.visible = false;
			tracker_Bar.visible = false;
			tracker_text.visible = false;
		}
	}
}

function backSelection()
{
	GenUtil.playUISound('back');

	FlxG.switchState(new ModState("HQMainMenu"));
}

function updateTexts(data:Dynamic)
{
	achievementName.text = i18n.tr('Accolades/Achievements/Names/${data.nameKey}');
	achievementDescription.text = i18n.tr('Accolades/Achievements/Descriptions/${data.nameKey}');
}
