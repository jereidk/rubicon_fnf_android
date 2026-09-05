import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.util.FlxAxes;
import openfl.display.BlendMode;
import BlurFilter;
import util.GenUtil;
import funkin.backend.utils.DiscordUtil;
import ui.achievement.AchievementUnlockNoticeUI;

var bg:FunkinSprite;
var frame:FunkinSprite;
var madoka:FunkinSprite;
var sayaka:FunkinSprite;
var back:FunkinSprite;
var namebg:FunkinSprite;
var artText:FlxText;
var prev:FunkinSprite;
var next:FunkinSprite;
var dimmingSprites:Array = [];
var dimmingTweens:Array = [];
var prevTween:FlxTween;
var nextTween:FlxTween;

// Artworks
var artGraphics:Array = [];
var curSelected:Int = 0;
var currentArtwork:FunkinSprite;

// Zooming
var isZoomedIn:Bool = false;
var zoomTween:FlxTween;

// Controls
var zoomLimit:Float = 0.0;

// Help UI
var camUI:FlxCamera;
var camUITween:FlxTween;
var helpText:FlxText;
var artTween:FlxTween;
var zoomdifference:Float = 0.0;

// Cata UI
var isSelectingCata:Bool = true;
var blur:BlurFilter;
var cataGroup:FlxSpriteGroup;
var cataTextGroup:FlxSpriteGroup;
var curCataSel:Int = 0;

var catas:Array<String> = [
	'Girlfriend',
	'Sayaka',
	'Mami',
	'Madoka',
	'Kyoko',
	'Homura',
	'Kyubey',
	'meguca',
	'Promo',
	'Fanart',
	'UI',
	'Scrapped'
];

var waitNextFrame:Bool = false;

// Workaround since HScript doesn't support typedefs!
var artworks = [];

function create()
{
	DiscordUtil.changePresenceSince("In Gallery", null);
	CoolUtil.playMusic(Paths.music("gallery"));

	camUI = new FlxCamera();
	FlxG.cameras.add(camUI, false);
	camUI.bgColor = 0x00000000;
	camUI.alpha = 0.0;

	camCataGroup = new FlxCamera();
	FlxG.cameras.add(camCataGroup, false);
	camCataGroup.bgColor = 0x00000000;

	camWhaterverlolGroup = new FlxCamera();
	FlxG.cameras.add(camWhaterverlolGroup, false);
	camWhaterverlolGroup.bgColor = 0x00000000;

	bg = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gallery/bg'));
	add(bg);

	frame = new FunkinSprite(282, 0).loadGraphic(Paths.image('ui/gallery/frame'));
	add(frame);

	madoka = new FunkinSprite(0, 240).loadGraphic(Paths.image('ui/gallery/madoka'));
	add(madoka);

	sayaka = new FunkinSprite(1413, 0).loadGraphic(Paths.image('ui/gallery/sayaka'));
	add(sayaka);

	back = new FunkinSprite(5, 11).loadGraphic(Paths.image('ui/gallery/back'));
	add(back);

	namebg = new FunkinSprite(619, 888).loadGraphic(Paths.image('ui/gallery/namebg'));
	add(namebg);

	artText = new FlxText(0, 0, namebg.width, 'Name\nby: Name');
	artText.setFormat(Paths.font("kaisho-S.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	artText.borderSize = 2.5;
	add(artText);
	GenUtil.alignToCenter(artText, namebg);

	prev = new FunkinSprite(386, 881).loadGraphic(Paths.image('ui/gallery/prev'));
	add(prev);

	next = new FunkinSprite(1236, 881).loadGraphic(Paths.image('ui/gallery/next'));
	add(next);

	for (spr in [bg, frame, madoka, sayaka, back, namebg, artText, prev, next])
	{
		spr.color = FlxColor.WHITE;
		dimmingSprites.push(spr);
	}

	// Help UI
	topBar = new FunkinSprite(0, FlxG.height * 1.40).makeGraphic(1, 1, FlxColor.BLACK);
	topBar.scale.set(FlxG.width * 2, FlxG.height * 1);
	add(topBar);
	topBar.alpha = 0.5;

	helpText = new FlxText(0, 0, FlxG.width, i18n.tr('Gallery/Help'));
	helpText.setFormat(Paths.font("kaisho-S.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
	helpText.borderSize = 2.5;
	add(helpText);
	helpText.y = FlxG.height - helpText.height - 48;

	for (spr in [topBar, helpText])
		spr.cameras = [camUI];

	// Catas
	blur = new BlurFilter(15.0);
	for (cam in FlxG.cameras.list)
	{
		if (cam != camCataGroup && cam != camWhaterverlolGroup)
			blur.apply(cam);
	}

	blur.remove(globalCam);

	cataBGOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
	cataBGOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
	add(cataBGOverlay).cameras = [camCataGroup];
	cataBGOverlay.alpha = 0.85;

	cataGroup = new FlxSpriteGroup();
	add(cataGroup);

	cataTextGroup = new FlxSpriteGroup();
	add(cataTextGroup);

	for (i in 0...catas.length)
	{
		catabg = new FunkinSprite(619, 450 + (200 * i)).loadGraphic(Paths.image('ui/gallery/namebg'));
		catabg.ID = i;
		cataGroup.add(catabg).cameras = [camCataGroup];

		cataText = new FlxText(0, 0, catabg.width, catas[i]);
		cataText.ID = i;
		cataText.setFormat(Paths.font("kaisho-S.otf"), 56, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
		cataText.borderSize = 2.5;
		cataTextGroup.add(cataText).cameras = [camCataGroup];
		GenUtil.alignToCenter(cataText, catabg);
	}

	infoHelp = new FlxText(25, FlxG.height, 0, i18n.tr('Gallery/HelpFull'));
	infoHelp.setFormat(Paths.font("kaisho-S.otf"), 42, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x88000000);
	infoHelp.borderSize = 2.5;
	add(infoHelp).cameras = [camCataGroup];
	infoHelp.y -= infoHelp.height + 25;

	// UNLOCK: ACHIEVEMENT - Chamber of Light
	if (GenUtil.isAchievementLocked('ChamberOfLight'))
	{
		GenUtil.achievementUnlock('ChamberOfLight');
		var popup:AchievementUnlockNoticeUI = new AchievementUnlockNoticeUI('ChamberOfLight');
		add(popup).group.cameras = [camWhaterverlolGroup];
	}

	switchCata(false);

	if (FlxG.save.data.viewedMenu.contains(4))
	{
		FlxG.save.data.viewedMenu.remove(4);
		FlxG.save.flush();
	}
}

function postCreate()
{
	// switchArt(0);
}

function update(elapsed:Float)
{
	if (controls.BACK && isSelectingCata)
	{
		FlxG.switchState(new MainMenuState());
	}
	else if (controls.BACK)
	{
		GenUtil.playUISound('back');
		isSelectingCata = true;
		camCataGroup.visible = true;

		isZoomedIn = true;
		focusToggle();

		for (cam in FlxG.cameras.list)
		{
			if (cam != camCataGroup)
				blur.set(15.0);
		}
	}

	if (!isSelectingCata)
	{
		if (!isZoomedIn)
		{
			if (controls.LEFT_P)
				switchArt(-1);
			else if (controls.RIGHT_P)
				switchArt(1);
		}
		else
		{
			if (controls.LEFT)
				currentArtwork.x += 500 * elapsed;
			else if (controls.RIGHT)
				currentArtwork.x -= 500 * elapsed;

			if (controls.UP)
				currentArtwork.y += 500 * elapsed;
			else if (controls.DOWN)
				currentArtwork.y -= 500 * elapsed;

			zoomLimit = 0.5;

			if (FlxG.keys.pressed.Q && zoomdifference >= 0.0)
			{
				currentArtwork.scale.x -= 1.5 * elapsed;
				currentArtwork.scale.y -= 1.5 * elapsed;
				zoomdifference -= 0.5 * elapsed;
			}
			else if (FlxG.keys.pressed.E && zoomdifference <= 0.25)
			{
				currentArtwork.scale.x += 1.5 * elapsed;
				currentArtwork.scale.y += 1.5 * elapsed;
				zoomdifference += 0.5 * elapsed;
			}
		}
	}
	else
	{
		if (controls.DOWN_P)
		{
			curCataSel = FlxMath.wrap(curCataSel + 1, 0, catas.length - 1);
			switchCata(true);
		}
		else if (controls.UP_P)
		{
			curCataSel = FlxMath.wrap(curCataSel - 1, 0, catas.length - 1);
			switchCata(true);
		}

		if (controls.ACCEPT)
		{
			waitNextFrame = true;
			loadCata();
		}
	}

	if (!isSelectingCata && !waitNextFrame)
	{
		if (controls.ACCEPT)
			focusToggle();
	}

	cataGroup.y = CoolUtil.fpsLerp(cataGroup.y, 0 - curCataSel * 200, 0.25);
	cataTextGroup.y = cataGroup.y;

	waitNextFrame = false;
}

function focusToggle()
{
	isZoomedIn = !isZoomedIn;
	zoomdifference = 0.0;

	if (zoomTween != null)
		zoomTween.cancel();

	if (camUITween != null)
		camUITween.cancel();

	if (isZoomedIn)
	{
		zoomTween = FlxTween.tween(FlxG.camera, {zoom: 1.55}, 0.75, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				zoomTween = null;
			}
		});

		camUITween = FlxTween.tween(camUI, {alpha: 1.0}, 0.75, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				camUITween = null;
			}
		});

		for (twn in dimmingTweens)
			twn.cancel();

		for (spr in dimmingSprites)
			dimmingTweens.push(FlxTween.color(spr, 1.5, spr.color, 0xFF383838, {ease: FlxEase.expoOut}));
	}
	else
	{
		zoomTween = FlxTween.tween(FlxG.camera, {zoom: 1.0}, 0.75, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				zoomTween = null;
			}
		});

		camUITween = FlxTween.tween(camUI, {alpha: 0.0}, 0.75, {
			ease: FlxEase.expoOut,
			onComplete: function(twn:FlxTween)
			{
				camUITween = null;
			}
		});

		for (art in artGraphics)
		{
			if (art.ID == curSelected)
			{
				artTween = FlxTween.tween(art, {
					x: (FlxG.width - art.width) / 2,
					y: (FlxG.height - art.height) / 2,
					'scale.x': artworks[curSelected].defaultZoom,
					'scale.y': artworks[curSelected].defaultZoom
				}, 0.5, {
					ease: FlxEase.expoOut
				});
			}
		}

		for (twn in dimmingTweens)
			twn.cancel();

		for (spr in dimmingSprites)
			dimmingTweens.push(FlxTween.color(spr, 1.5, spr.color, 0xFFFFFFFF, {ease: FlxEase.expoOut}));
	}
}

function switchCata(playSound:Bool)
{
	if (playSound)
		GenUtil.playUISound('move');

	for (spr in cataGroup)
	{
		spr.color = FlxColor.GRAY;
		if (spr.ID == curCataSel)
			spr.color = FlxColor.WHITE;
	}

	for (spr in cataTextGroup)
	{
		spr.color = FlxColor.GRAY;
		if (spr.ID == curCataSel)
			spr.color = FlxColor.WHITE;
	}
}

function loadCata()
{
	curSelected = 0;
	loadCataImages(curCataSel);

	GenUtil.playUISound('confirm');

	for (cam in FlxG.cameras.list)
	{
		if (cam != camCataGroup)
			blur.set(0.0);
	}

	camCataGroup.visible = false;
	isSelectingCata = false;
}

function switchArt(?amount:Int = 0)
{
	curSelected = FlxMath.wrap(curSelected + amount, 0, artworks.length - 1);
	switchCata(true);

	zoomdifference = 0.0;
	for (art in artGraphics)
	{
		art.visible = false;

		if (art.ID == curSelected)
		{
			art.scale.set(artworks[curSelected].defaultZoom, artworks[curSelected].defaultZoom);
			art.screenCenter();
			art.visible = true;
			currentArtwork = art;
		}
	}

	if (amount == -1)
	{
		if (prevTween != null)
			prevTween.cancel();

		prev.x = 386 - 25;
		prevTween = FlxTween.tween(prev, {x: prev.x + 25}, 0.5, {ease: FlxEase.expoOut});
	}
	else if (amount == 1)
	{
		if (nextTween != null)
			nextTween.cancel();

		next.x = 1236 + 25;
		nextTween = FlxTween.tween(next, {x: next.x - 25}, 0.5, {ease: FlxEase.expoOut});
	}

	artText.text = artworks[curSelected].artshort + '\nBy: ' + artworks[curSelected].artist;
	helpText.text = artworks[curSelected].art + ' / By: ' + artworks[curSelected].artist + '\n${i18n.tr('Gallery/Help')}';
}

function loadCataImages(cata:Int)
{
	for (spr in artGraphics)
	{
		spr.destroy();
		remove(spr, true);
	}
	artGraphics = [];

	switch (cata)
	{
		case 0:
			artworks = [
				{
					imgName: 'GF/first concept of girlfriend outfit March 2022',
					art: "Outfit Concept (March 2022)",
					artshort: "Outfit Concept (MAR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/first finalised girlfriend outfit March 2022',
					art: "Finalised Concept (March 2022)",
					artshort: "Finalised Concept (MAR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/first concept of girlfriend poses May 2022',
					art: "Poses Concept (May 2022)",
					artshort: "Poses Concept (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/first concept of girlfriend other animations May 2022',
					art: "Death Concept (May 2022)",
					artshort: "Death Concept (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/old gf icons May 2022',
					art: "Old Icons (May 2022)",
					artshort: "Old Icons (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/back in my day July 2022',
					art: "Sprite Showcase (July 2022)",
					artshort: "Sprite Showcase (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/oldest casual gf sketches november 2022',
					art: "Casual Girlfriend (November 2022)",
					artshort: "Casual Girlfriend (NOV. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/height reference april 2025',
					art: "Height Reference (April 2025)",
					artshort: "Height Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/refsheet april 2025',
					art: "Girlfriend Reference (April 2025)",
					artshort: "Girlfriend Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/refsheet faces april 2025',
					art: "Girlfriend Face Reference (April 2025)",
					artshort: "Girlfriend Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/Newest GF poses July 2025 1',
					art: "Girlfriend Poses (July 2025)",
					artshort: "Girlfriend Poses (JUL. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'GF/Newest GF poses July 2025 2',
					art: "Girlfriend Poses (July 2025)",
					artshort: "Girlfriend Poses (JUL. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 1:
			artworks = [
				{
					imgName: 'Sayaka/first completed sayaka sprites March 2022',
					art: "Sayaka Sprite (March 2022)",
					artshort: "Sayaka Sprite (MAR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/sayaka concept april 2022',
					art: "Sayaka Concept (April 2022)",
					artshort: "Sayaka Concept (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/oldest sayaka poses march 2022',
					art: "Sayaka Poses (March 2022)",
					artshort: "Sayaka Poses (MAR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/old sayaka icons May 2022',
					art: "Sayaka Icon (March 2022)",
					artshort: "Sayaka Icon (MAR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/oldest resonance bg characters July 2022',
					art: "Resonance BG Characters (July 2022)",
					artshort: "Resonance BG Characters (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 0.95
				},
				{
					imgName: 'Sayaka/oldest resonance concept sketch July 2022',
					art: "BG Concept (July 2022)",
					artshort: "BG Concept (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/oldest resonance bg October 2022',
					art: "Resonance BG (October 2022)",
					artshort: "Resonance BG (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/char october 2022',
					art: "Resonance BG Characters (October 2022)",
					artshort: "Resonance BG Characters (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/old resonance album art january 2023',
					art: "Album Art (January 2023)",
					artshort: "Album Art (JAN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/canned anime-styled redesign sayaka idle febuary 2023',
					art: "Scrapped Redesign (February 2023)",
					artshort: "Scrapped Redesign (FEB. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/second oldest resonance bg June 2023',
					art: "Resonance BG (June 2023)",
					artshort: "Resonance BG (JUN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.25
				},
				{
					imgName: 'Sayaka/Newest Sayaka poses sketches Novemeber 2023',
					art: "Sayaka Poses (November 2023)",
					artshort: "Sayaka Poses (NOV. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/Newest Sayaka poses Novemeber 2023',
					art: "Sayaka Poses (November 2023)",
					artshort: "Sayaka Poses (NOV. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/Newest Sayaka heal poses Novemeber 2023',
					art: "Sayaka Heal Poses (November 2023)",
					artshort: "Sayaka Heal Poses (NOV. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/old sayaka ref april 2025',
					art: "Sayaka Reference (April 2025)",
					artshort: "Sayaka Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Sayaka/sayaka face ref april 2025',
					art: "Sayaka Face Reference (April 2025)",
					artshort: "Sayaka Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 2:
			artworks = [
				{
					imgName: 'Mami/first concept of mami April 2022',
					art: "Mami Concept (April 2022)",
					artshort: "Mami Concept (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/old mami icons May 2022',
					art: "Mami Icons (May 2022)",
					artshort: "Mami Icons (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/oldest mami sprites june 2022',
					art: "Mami Sprite (June 2022)",
					artshort: "Mami Sprite (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/oldest partea concept sketch July 2022',
					art: "Partea BG Concept (July 2022)",
					artshort: "Partea BG Concept (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/oldest partea bg characters September 2022',
					art: "Partea BG (September 2022)",
					artshort: "Partea BG (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/char october 2022',
					art: "Partea BG Characters (October 2022)",
					artshort: "Partea BG Characters (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/old partea album art febuary 2023',
					art: "Album Art (February 2023)",
					artshort: "Album Art (FEB. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/old partea bg characters concept April 2023',
					art: "Partea BG Characters (April 2023)",
					artshort: "Partea BG Characters (APR. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/more updated partea bg characters Febuary 2025',
					art: "Partea BG (February 2025)",
					artshort: "Partea BG (FEB. 2025)",
					artist: 'Kixel & RetroDetro',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/old mami ref april 2025',
					art: "Mami Reference (April 2025)",
					artshort: "Mami Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/mami face ref april 2025',
					art: "Mami Face Reference (April 2025)",
					artshort: "Mami Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Mami/new partea mid-song concept september 2025',
					art: "Partea Song Event Concept (September 2025)",
					artshort: "Partea Song Event Concept (SEP. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 3:
			artworks = [
				{
					imgName: 'Madoka/madoka concept april 2022',
					art: "Madoka Concept (April 2022)",
					artshort: "Madoka Concept (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/old madoka icons May 2022',
					art: "Madoka Icons (May 2022)",
					artshort: "Madoka Icons (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/oldest eternal star concept sketch July 2022',
					art: "Eternal Star BG Concept (July 2022)",
					artshort: "Eternal Star BG Concept (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/oldest eternal star bg characters August 2022',
					art: "Eternal Star BG (August 2022)",
					artshort: "Eternal Star BG (AUG. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/oldest madoka poses october 2022',
					art: "Madoka Poses (October 2022)",
					artshort: "Madoka Poses (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/char october 2022',
					art: "Eternal Star BG Characters (October 2022)",
					artshort: "Eternal Star BG Characters (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/old eternal star album art january 2023',
					art: "Album Art (January 2023)",
					artshort: "Album Art (JAN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/Newest madoka poses Novemeber 2023',
					art: "Madoka Poses (November 2023)",
					artshort: "Madoka Poses (NOV. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/old madoka ref april 2025',
					art: "Madoka Reference (April 2025)",
					artshort: "Madoka Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Madoka/madoka face ref april 2025',
					art: "Madoka Face Reference (April 2025)",
					artshort: "Madoka Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 4:
			artworks = [
				{
					imgName: 'Kyoko/kyoko concept april 2022',
					art: "Kyoko Concept (April 2022)",
					artshort: "Kyoko Concept (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/oldest kyoko poses april 2022',
					art: "Kyoko Sprites (April 2022)",
					artshort: "Kyoko Sprites (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old kyoko icons May 2022',
					art: "Kyoko Icons (April 2022)",
					artshort: "Kyoko Icons (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old vexation sketch June 2022',
					art: "Vexation BG (June 2022)",
					artshort: "Vexation BG (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old vexation bg characters concept October 2022',
					art: "Vexation BG Characters (October 2022)",
					artshort: "Vexation BG Characters (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old vexation album art febuary 2023',
					art: "Album Art (February 2022)",
					artshort: "Album Art (FEB. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/Updated Kyoko poses May 2023',
					art: "Kyoko Poses (May 2023)",
					artshort: "Kyoko Poses (MAY. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old kyoko poses october 2023',
					art: "Kyoko Poses (October 2023)",
					artshort: "Kyoko Poses (OCT. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/old kyoko ref april 2025',
					art: "Kyoko Reference (April 2025)",
					artshort: "Kyoko Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyoko/kyoko face ref april 2025',
					art: "Kyoko Face Reference (April 2025)",
					artshort: "Kyoko Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
			];
		case 5:
			artworks = [
				{
					imgName: 'Homura/homura concept april 2022',
					art: "Homura Concept (April 2022)",
					artshort: "Homura Concept (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/oldest homura poses may 2022',
					art: "Homura Poses (May 2022)",
					artshort: "Homura Poses (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/old homura icons May 2022',
					art: "Homura Icons (May 2022)",
					artshort: "Homura Icons (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/old out of time bg sketch June 2022',
					art: "Out-of-Time BG Concept (June 2022)",
					artshort: "Out-of-Time BG Concept (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/Updated Homura poses October 2022',
					art: "Homura Poses (October 2022)",
					artshort: "Homura Poses (OCT. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/oldest out of time bg characters October 2022',
					art: "Out-of-Time BG Character (October 2022)",
					artshort: "Out-of-Time BG Character (OCT. 2022)",
					artist: 'Kixel & cuffeekawaii',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/old out of time album art january 2023',
					art: "Album Art (January 2023)",
					artshort: "Album Art (JAN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/old homura ref april 2025',
					art: "Homura Reference (April 2025)",
					artshort: "Homura Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Homura/homuras face ref april 2025',
					art: "Homura Face Reference (April 2025)",
					artshort: "Homura Face Reference (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 6:
			artworks = [
				{
					imgName: 'Kyubey/inital kyubey sprites sketch May 2022',
					art: "Kyubey Concept (May 2022)",
					artshort: "Kyubey Concept (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyubey/old kyubey sprites May 2022',
					art: "Kyubey Sprites (May 2022)",
					artshort: "Kyubey Sprites (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyubey/old kyubey icons May 2022',
					art: "Kyubey Icons (May 2022)",
					artshort: "Kyubey Icons (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyubey/Updated kyubey concept January 2024',
					art: "Kyubey Concept (January 2024)",
					artshort: "Kyubey Concept (JAN. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Kyubey/old kyubey ref april 2025',
					art: "Kyubey Concept (April 2025)",
					artshort: "Kyubey Concept (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 7:
			artworks = [
				{
					imgName: 'Meguca/inital meguca concept June 2022',
					art: "Meguca Concept (June 2022)",
					artshort: "Meguca Concept (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Meguca/old meguca album art january 2023',
					art: "Album Art (January 2023)",
					artshort: "Album Art (JAN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Meguca/inital meguca countdown concept June 2023',
					art: "Yotsuba Countdown Concept (June 2023)",
					artshort: "Yotsuba Countdown Concept (JUN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Meguca/inital meguca countdown July 2023',
					art: "Yotsuba Countdown (July 2023)",
					artshort: "Yotsuba Countdown Concept (JUL. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 8:
			artworks = [
				{
					imgName: 'Promo/now in production image april 2022',
					art: "Now in Production (April 2022)",
					artshort: "Now in Production (APR. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/retconned July 2022',
					art: "Retconned (July 2022)",
					artshort: "Retconned (JUL. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/January 2024 dev log art',
					art: "Dev Log (January 2023)",
					artshort: "Dev Log (JAN. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/old promo art may 2023',
					art: "Promo Art (May 2023)",
					artshort: "Promo Art (MAY. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/September 2023 dev log art',
					art: "Dev Log (September 2023)",
					artshort: "Dev Log (SEP. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/donuts september 2023',
					art: "Donuts (September 2023)",
					artshort: "Donuts (SEP. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/April 2024 dev log art',
					art: "Dev Log (April 2024)",
					artshort: "Dev Log (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/funkkast promo wip April 2024',
					art: "FunkKast Promo WIP (April 2024)",
					artshort: "FunkKast Promo WIP (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/finalised funkkast promo art June 2024',
					art: "FunkKast Promo (June 2024)",
					artshort: "FunkKast Promo (JUN. 2024)",
					artist: 'Kixel & Teri',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/random gf sketches July 2024',
					art: "Girlfriend Skectches (June 2024)",
					artshort: "Girlfriend Skectches (JUN. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/post-demo release drawing July 2024',
					art: "Post-Demo Release (July 2024)",
					artshort: "Post-Demo Release (JUL. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/Hotfix art July 2024',
					art: "Hotfix Update (July 2024)",
					artshort: "Hotfix Update (JUL. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/more random gf sketches August 2024',
					art: "Girlfriend Skectches (August 2024)",
					artshort: "Girlfriend Skectches (AUG. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/December 2024 dev log art',
					art: "Dev Log (December 2024)",
					artshort: "Dev Log (DEC. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/Febuary 2025 dev log art',
					art: "Dev Log (February 2025)",
					artshort: "Dev Log (FEB. 2025)",
					artist: 'Kixel & Sector',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/never happening april 2025',
					art: "April Fools (April 2025)",
					artshort: "April Fools (APR. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Promo/september 2025 dev log',
					art: "Dev Log (September 2025)",
					artshort: "Dev Log (SEP. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 9:
			artworks = [
				{
					imgName: 'Fan Art/ame',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'ame',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/ash (muff1no0)',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'ash (muff1no0)',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/Caroline Sparkle',
					art: "Girlfriend & Nene Fanart",
					artshort: "Girlfriend & Nene Fanart",
					artist: 'Caroline Sparkle',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/DiegoT',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'DiegoT',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/DusterBuster',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'DusterBuster',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/far0',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'far0',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/foikun9',
					art: "Kyubey Fanart",
					artshort: "Kyubey Fanart",
					artist: 'foikun9',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/Inkzilla',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'Inkzilla',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/LZDigiArts',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'LZDigiArts',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/Mari',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'Mari',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/novaAG',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'novaAG',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/okuto',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'okuto',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/RetroDetro',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'RetroDetro',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/RevDev',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'RevDev',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/sp0re',
					art: "Moemura Fanart",
					artshort: "Moemura Fanart",
					artist: 'Sp0re',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/Teri',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'Teri',
					defaultZoom: 1.0
				},
				{
					imgName: 'Fan Art/Torr',
					art: "Girlfriend Fanart",
					artshort: "Girlfriend Fanart",
					artist: 'Torr',
					defaultZoom: 1.0
				}
			];
		case 10:
			artworks = [
				{
					imgName: 'UI/old menu concepts May 2022',
					art: "Main Menu Concept (May 2022)",
					artshort: "Main Menu Concept (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/inital logo sketche may 2022',
					art: "Logo Concept (May 2022)",
					artshort: "Logo Concept (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/oldest freeplay art sketches May 2022',
					art: "Freeplay Portraits (May 2022)",
					artshort: "Freeplay Portraits (MAY. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/slightly newer menu concepts June 2022',
					art: "Menu Concept (June 2022)",
					artshort: "Menu Concept (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/oldest main menu August 2022',
					art: "Main Menu Concept (August 2022)",
					artshort: "Main Menu Concept (AUG. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old updated icons sketches september 2022',
					art: "Icons (September 2022)",
					artshort: "Icons (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/oldest window icon March 2023',
					art: "App Icon (March 2023)",
					artshort: "App Icon (MAR. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old pause menu concepts August 2023',
					art: "Pause Menu (August 2023)",
					artshort: "Pause Menu (AUG. 2023)",
					artist: 'Kixel & Sector',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/options screen concept August 2023',
					art: "Options Menu (August 2023)",
					artshort: "Options Menu (AUG. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/mechanic explanation screen concept August 2023',
					art: "Mechanic Screen Concept (August 2023)",
					artshort: "Mechanic Screen Concept (AUG. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/pause menu animation sketches  january 2024',
					art: "Pause Concepts (January 2024)",
					artshort: "Pause Concepts (JAN. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/initial difficulty select sketch January 2024',
					art: "Difficulty Selection Concept (January 2024)",
					artshort: "Difficulty Selection Concept (JAN. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/initial disclaimer screen sketch January 2024',
					art: "Disclaimer Concept (January 2024)",
					artshort: "Disclaimer Concept (JAN. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old achievement select art concept April 2024',
					art: "Achievements Concept (April 2024)",
					artshort: "Achievements Concept (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old achievement select art April 2024',
					art: "Achievements (April 2024)",
					artshort: "Achievements (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old credits select art concept April 2024',
					art: "Credits Concept (April 2024)",
					artshort: "Credits Concept (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old credits select art April 2024',
					art: "Credits (April 2024)",
					artshort: "Credits (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old freeplay select art concept April 2024',
					art: "Freeplay Concept (April 2024)",
					artshort: "Freeplay Concept (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old freeplay select art April 2024',
					art: "Freeplay (April 2024)",
					artshort: "Freeplay (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old options select art concept April 2024',
					art: "Options Concept (April 2024)",
					artshort: "Options Concept (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old options select art April 2024',
					art: "Options (April 2024)",
					artshort: "Options (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old story mode select art concept April 2024',
					art: "Story Mode Concept (April 2024)",
					artshort: "Story Mode Concept (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/old story mode select art April 2024',
					art: "Story Mode (April 2024)",
					artshort: "Story Mode (APR. 2024)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/new freeplay concept July 2025',
					art: "Freeplay Concept (July 2025)",
					artshort: "Freeplay Concept (JUL. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'UI/new ui concept July 2025',
					art: "Game UI Concept (July 2025)",
					artshort: "Game UI Concept (JUL. 2025)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
		case 11:
			artworks = [
				{
					imgName: 'Scrapped/inital rolling girl sketch July 2022',
					art: "Rolling Girl Concept (June 2022)",
					artshort: "Rolling Girl Concept (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned boogieman cover inital oncept july 2022',
					art: "Boogieman Concept (June 2022)",
					artshort: "Boogieman Concept (JUN. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned phase 1 rolling sprites september 2022',
					art: "Rolling Girl Sprites (September 2022)",
					artshort: "Rolling Girl Sprites (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned phase 2 rolling sprites september 2022',
					art: "Rolling Girl Sprites (September 2022)",
					artshort: "Rolling Girl Sprites (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/old rolling girl hug september 2022',
					art: "Rolling Girl Hug (September 2022)",
					artshort: "Rolling Girl Hug (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned twlight serenade cover concept september 2022',
					art: "Twilight Serenade Concept (September 2022)",
					artshort: "Twilight Serenade Concept (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned twlight serenade outfit reference september 2022',
					art: "Twilight Serenade Reference (September 2022)",
					artshort: "Twilight Serenade Reference (SEP. 2022)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned anime-styled redesign febuary 2023',
					art: "Scrapped Redesigns (February 2023)",
					artshort: "Scrapped Redesigns (FEB. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				},
				{
					imgName: 'Scrapped/canned updated twlight serenade cover concept september 2023',
					art: "Twilight Serenade Concept (September 2023)",
					artshort: "Twilight Serenade Concept (SEP. 2023)",
					artist: 'Kixel',
					defaultZoom: 1.0
				}
			];
	}

	for (i in 0...artworks.length)
	{
		var art = new FunkinSprite(0, 240).loadGraphic(Paths.image('ui/gallery/art/' + artworks[i].imgName));
		art.ID = i;
		insert(members.indexOf(bg), art);
		art.screenCenter();
		art.scale.set(artworks[i].defaultZoom, artworks[i].defaultZoom);
		artGraphics.push(art);
	}

	switchArt(0);
}
