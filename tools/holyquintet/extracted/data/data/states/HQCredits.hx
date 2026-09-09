import ui.CreditInfoUI;
import flixel.addons.display.FlxBackdrop;
import funkin.menus.FreeplayState.FreeplaySonglist;
import funkin.savedata.FunkinSave;
import funkin.backend.utils.DiscordUtil;

public static var cm_curSel:Int = 0;
var canControl:Bool = true;
var portrait:FunkinSprite;
var songInfos:Array<CreditInfoUI> = [];
var scroll_OffsetX:Float = 0;
var scroll_OffsetY:Float = 0;
var songInfos_OriginalX:Array<Float> = [];
var songInfos_OriginalY:Array<Float> = [];
var scroll_Tweens:Array<FlxTween> = [];
var confirmingSong:Bool = false;

var credits = [
	{
		imgName: 'kixel',
		name: 'Kixel',
		role: 'Lead Director, Lead Art & Animation Director,\nConcept Artist, Story Writer',
		tworow: true
	},
	{
		imgName: 'sector',
		name: 'Sector',
		role: 'Director, Lead Program Director, Artist, Cleanup Artist,\nAnimator',
		tworow: true
	},
	{
		imgName: 'spore',
		name: 'Sp0re',
		role: 'Co-Director, Lead Music Director,\nLead Story Writer, Chromatic Maker',
		tworow: true
	},
	{
		imgName: 'chumbot',
		name: 'chum-bot',
		role: 'Co-Director, Musician, Story Writer',
		tworow: false
	},
	{
		imgName: 'pablito',
		name: 'GamerPablito',
		role: 'Programmer, Translator (ES)',
		tworow: false
	},
	{
		imgName: 'revdev',
		name: 'RevDev',
		role: 'Lead Witch Aesthetic Artist, BG Artist',
		tworow: false
	},
	{
		imgName: 'torr',
		name: 'Torresmmo',
		role: 'Artist and Animator',
		tworow: false
	},
	{
		imgName: 'teri',
		name: 'Teri',
		role: 'Artist and BG Artist',
		tworow: false
	},
	{
		imgName: 'moth',
		name: 'endtimeillusionist',
		role: 'Artist',
		tworow: false
	},
	{
		imgName: 'faro',
		name: 'Far0',
		role: 'Artist',
		tworow: false
	},
	{
		imgName: 'retrodetro',
		name: 'RetroDetro',
		role: 'BG Artist, Animatic Animator, Animator',
		tworow: false
	},
	{
		imgName: 'cuffee',
		name: 'cuffeekawaii',
		role: 'Artist',
		tworow: false
	},
	{
		imgName: 'akoy',
		name: 'akoy!',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'mag',
		name: 'Mag',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'sinn',
		name: 'Sinn',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'oreo',
		name: 'Sleepy_Oreo',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'jordo',
		name: 'JordoPrice',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'clover',
		name: 'cloverderus',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'penkaru',
		name: 'Penkaru',
		role: 'Musician',
		tworow: false
	},
	{
		imgName: 'fade',
		name: 'Fade_R',
		role: 'Charter',
		tworow: false
	},
	{
		imgName: 'flootena',
		name: 'Flootena',
		role: 'Charter',
		tworow: false
	},
	{
		imgName: 'maskly',
		name: 'BlackMaskly',
		role: 'Charter',
		tworow: false
	},
	{
		imgName: 'tau',
		name: 'TAU',
		role: 'Editor',
		tworow: false
	},
	{
		imgName: 'blitz',
		name: 'Blitz',
		role: 'Voice Actress',
		tworow: false
	},
	{
		imgName: 'cyancat',
		name: 'Cyancat',
		role: 'Translator (JP)',
		tworow: false
	}
];

function create()
{
	DiscordUtil.changePresenceSince("In Credits", null);
	// PRELOAD
	for (i in 0...credits.length)
	{
		graphicCache.cache(Paths.image('ui/credits/portraits/' + credits[i].imgName));
	}

	bg_Spr = new FunkinSprite().loadGraphic(Paths.image('ui/common/background'));
	add(bg_Spr);
	bg_Spr.color = FlxColor.GRAY;

	bg_Spots = new FlxBackdrop(Paths.image('ui/common/spots'), FlxAxes.XY, 0, 0);
	bg_Spots.alpha = 1.0;
	add(bg_Spots);
	bg_Spots.color = FlxColor.GRAY;
	bg_Spots.velocity.set(15, 25);

	bg_Back = new FunkinSprite().loadGraphic(Paths.image('ui/common/back'));
	add(bg_Back);
	bg_Back.flipX = true;
	bg_Back.blend = BlendMode.MULTIPLY;

	for (i in 0...credits.length)
	{
		var songinfo = new CreditInfoUI((100 + (25 * i)), (465 + (180 * i)), credits[i]);
		songinfo.ID = i;
		add(songinfo);
		songInfos.push(songinfo);

		songInfos_OriginalX.push(songinfo.group.x);
		songInfos_OriginalY.push(songinfo.group.y);
	}

	additonalText = new FlxText(675, 4750, 1000, '');
	additonalText.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
	additonalText.borderSize = 3.5;
	add(additonalText);

	additonalText.text = "SPECIAL THANKS\n\nBlantados, Ame, TaeYai, 2DSleeping, Codename Engine, EggOverlord, TheRoyalTony, ChampionKnightEX, Zarky, Inkujira, AGgames, Matt_Does, siron_FNF, shinogami_hajime, Superskullz115, Syrup, Moro-Maniac, Nex_isDumb, heihua., deepseek, OrLavi\n\n\nCOPYRIGHT\n\nThis is a fan-made project and is NOT officially affiliated with Funkin' Crew, Magica Quartet, Aniplex & SHAFT.\nAll rights reserved.\nA Magical Friday Night: Vs Holy Quintet by Team HQ";

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;

	portrait = new FunkinSprite().loadGraphic(Paths.image('ui/credits/portraits/kixel'));
	portrait.scale.set(1.30, 1.30);
	portrait.updateHitbox();
	portrait.setPosition((FlxG.width - (portrait.width / 2)) * 0.7, bg_BtmBanner.y - portrait.height);
	portrait.y -= bg_BtmBanner.height;
	insert(members.indexOf(bg_BtmBanner), portrait);
	portrait.alpha = 0.0;

	changeSelection(0);

	// UNLOCK: ACHIEVEMENT - Thanks for Playing!
	if (GenUtil.isAchievementLocked('ThanksForPlaying'))
	{
		GenUtil.achievementUnlock('ThanksForPlaying');
	}
}

function changeSelection(change:Int)
{
	if (change != 0)
		GenUtil.playUISound('move');

	cm_curSel = FlxMath.wrap(cm_curSel + change, 0, songInfos.length - 1);

	updatePortrait();

	curCredit = credits[cm_curSel];

	scroll_OffsetX = -25 * cm_curSel;
	scroll_OffsetY = 180 * cm_curSel;

	for (tween in scroll_Tweens)
	{
		tween?.cancel();
	}

	for (i in 0...songInfos.length)
	{
		if (songInfos[i].ID == cm_curSel)
			songInfos[i].selected = true;
		else
			songInfos[i].selected = false;

		scroll_Tweens.push(FlxTween.tween(songInfos[i].group, {x: songInfos_OriginalX[i] + scroll_OffsetX, y: songInfos_OriginalY[i] - scroll_OffsetY}, 0.5,
			{ease: FlxEase.expoOut}));
	}

	scroll_Tweens.push(FlxTween.tween(additonalText, {x: 725 + scroll_OffsetX, y: 4925 - scroll_OffsetY}, 0.5, {ease: FlxEase.expoOut}));
}

function updatePortrait()
{
	FlxTween.cancelTweensOf(portrait);
	portrait.alpha = 0.0;

	portrait.loadGraphic(Paths.image('ui/credits/portraits/' + credits[cm_curSel].imgName));
	portrait.scale.set(0.65, 0.65);
	portrait.updateHitbox();
	portrait.setPosition((FlxG.width - (portrait.width / 2)) * 0.7, bg_BtmBanner.y - portrait.height);

	portrait.x += 50;
	FlxTween.tween(portrait, {x: portrait.x - 50, alpha: 1.0}, 0.75, {ease: FlxEase.backOut});
}

function backSelection()
{
	GenUtil.playUISound('back');

	FlxG.switchState(new ModState("HQMainMenu"));
}

function update(elapsed:Float)
{
	if (canControl)
	{
		if (controls.UP_P)
			changeSelection(-1);
		else if (controls.DOWN_P)
			changeSelection(1);
	}

	if (controls.BACK)
	{
		backSelection();
	}
}
