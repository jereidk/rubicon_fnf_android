import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import funkin.game.HealthIcon;
import funkin.savedata.FunkinSave;
import util.GenUtil;
import Xml;

using StringTools;

class SongInfoUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var songinfo_Sprite:FunkinSprite;

	public var songinfo_Text:FlxText;

	public var songinfo_Icon:HealthIcon;

	public var songinfo_newText:FunkinSprite;

	var starFlame:FunkinSprite;

	var stars:Array<FunkinSprite> = [];

	public var songDataP:FreeplaySonglist;

	public var selected(default, set):Bool = false;
	public var text(default, set):String = 'Button';

	public var locked(default, set):Bool = false;

	public var unlockable(default, set):Bool = false;

	public function new(?x:Float = 0, ?y:Float = 0, ?songdata:FreeplaySonglist = null)
	{
		super(x, y);

		songDataP = songdata;

		group = new FlxSpriteGroup(x, y);

		songinfo_Rainbow = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/freeplay/borders/rainbow'));
		group.add(songinfo_Rainbow);
		songinfo_Rainbow.scale.set(1.35, 1.5);

		if (Options.gameplayShaders)
		{
			hueShader = new CustomShader("adjustColor");
			songinfo_Rainbow.shader = hueShader;
			hueShader.hue = 0.0;
			hueShader.contrast = 0.0;
			hueShader.saturation = 0.0;
		}

		songinfo_Sprite = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/freeplay/borders/base'), true, 980, 122);
		songinfo_Sprite.addAnim('normal', null, 0, false, false, [0]);
		songinfo_Sprite.addAnim('sdcb', null, 0, false, false, [1]);
		songinfo_Sprite.addAnim('fc', null, 0, false, false, [2]);
		songinfo_Sprite.addAnim('gfc', null, 0, false, false, [3]);
		songinfo_Sprite.addAnim('mfc', null, 0, false, false, [4]);
		songinfo_Sprite.addAnim('locked', null, 0, false, false, [5]);
		group.add(songinfo_Sprite);
		songinfo_Sprite.playAnim('normal');

		GenUtil.alignToCenter(songinfo_Rainbow, songinfo_Sprite);

		songinfo_Text = new FlxText(0, 0, songinfo_Sprite.width - (songinfo_Sprite.width * 0.025), songDataP.displayName);
		songinfo_Text.setFormat(Paths.font("shingo.otf"), 48, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		songinfo_Text.borderSize = 3.5;
		songinfo_Text.setPosition(((songinfo_Sprite / 2) - (songinfo_Text.width / 2)) * -0.35, ((songinfo_Sprite / 2) - (songinfo_Text.height / 2)) * -0.65);
		group.add(songinfo_Text);

		songinfo_composer_Text = new FlxText(0, 0, songinfo_Sprite.width
			- (songinfo_Sprite.width * 0.025),
			i18n.tr('Freeplay/ComposedBy')
			+ ' '
			+ songDataP.customValues.composers);
		songinfo_composer_Text.setFormat(Paths.font("shingo.otf"), 28, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		songinfo_composer_Text.borderSize = 3.5;
		songinfo_composer_Text.setPosition(((songinfo_Sprite / 2) - (songinfo_composer_Text.width / 2)) * -0.35,
			((songinfo_Sprite / 2) - (songinfo_composer_Text.height / 2)) * -4.5);
		group.add(songinfo_composer_Text);

		songinfo_score_Text = new FlxText(0, 0, songinfo_Sprite.width - (songinfo_Sprite.width * 0.025), '0');
		songinfo_score_Text.setFormat(Paths.font("shingo.otf"), 28, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		songinfo_score_Text.borderSize = 3.5;
		songinfo_score_Text.setPosition(((songinfo_Sprite / 2) - (songinfo_score_Text.width / 2)) * 0.05,
			((songinfo_Sprite / 2) - (songinfo_score_Text.height / 2)) * -4.5);
		group.add(songinfo_score_Text);

		for (i in 0...10)
		{
			var graphic:String = 'ui/freeplay/star/star_1';
			var color:FlxColor = FlxColor.fromRGB(255, 255 - (i * 15), 255);
			var addX:Float = 25;
			var addY:Float = 0;

			if (i > songDataP.customValues.diffStars - 1)
			{
				graphic = 'ui/freeplay/star/star_0';
				color = FlxColor.GRAY;
			}

			if (i == 9 && songDataP.customValues.diffStars - 1 > i - 1)
			{
				graphic = 'ui/freeplay/star/star_big';
				addX = 25;
				addY = 15;

				starFlame = new FunkinSprite(329, 67).loadSprite(Paths.image("ui/freeplay/star/star_flame"));
				starFlame.addAnim('start', 'flame', 24, false, false, [0, 1, 2, 3, 4, 5], '', 24, false);
				starFlame.addAnim('loop', 'flame', 24, true, false, [6, 7, 8, 9, 10, 11, 12, 13, 14, 15], '', 24, false);
				starFlame.scale.set(0.95, 0.95);
				starFlame.color = FlxColor.MAGENTA;
				group.add(starFlame);
				starFlame.playAnim('start');
				starFlame.animation.finishCallback = function(name:String)
				{
					starFlame.playAnim('loop');
				};
			}

			var diffStar:FlxSprite = new FlxSprite(150 + addX + (i * 25), 135 - addY).loadGraphic(Paths.image(graphic));
			diffStar.ID = i;
			diffStar.color = color;
			group.add(diffStar);
			stars.push(diffStar);
			// starsArray.push(diffStar);
		}

		icon = new HealthIcon(songDataP.icon);
		icon.scale.set(1.25, 1.25);
		icon.x -= 10;
		icon.y -= 15;
		group.add(icon);
		// icon.playAnim('neutral', true);

		// Locked Sprites
		lock = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/lock'));
		group.add(lock);
		GenUtil.alignToCenter(lock, songinfo_Sprite);

		lockGlow = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/lock_glow'));
		group.add(lockGlow);
		lockGlow.alpha = 0.0;
		// lockGlow.color = Character.getXMLFromCharName(icon.curCharacter).get('color').toWebString();
		GenUtil.alignToCenter(lockGlow, songinfo_Sprite);

		lockedText = new FlxText(0, 0, songinfo_Sprite.width - (songinfo_Sprite.width * 0.025), '${i18n.tr('Freeplay/${songDataP.customValues.unlockCond}')}');
		lockedText.setFormat(Paths.font("shingo.otf"), 42, 0xFF201A26, FlxTextAlign.LEFT);
		lockedText.setPosition(((songinfo_Sprite / 2) - (lockedText.width / 2)) * -0.10, ((songinfo_Sprite / 2) - (lockedText.height / 2)) * -0.5);
		group.add(lockedText);
		lockedText.origin.x = 0;
		lockedText.scale.x = 0.7;

		copyrightText = new FlxText(0, 0, 0, "(" + i18n.tr("Freeplay/NoCopyright") + ")");
		copyrightText.setFormat(Paths.font("shingo.otf"), 18, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0x880D090D);
		copyrightText.borderSize = 3.5;
		copyrightText.setPosition(((songinfo_Sprite / 2) - (songinfo_Text.width / 2)) * -0.35, ((songinfo_Sprite / 2) - (songinfo_Text.height / 2)) * -3.75);
		group.add(copyrightText);
		copyrightText.visible = false;

		glowSprite = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/freeplay/borders/glow'));
		group.add(glowSprite);
		glowSprite.alpha = 0.0;
		GenUtil.alignToCenter(glowSprite, songinfo_Sprite);

		updateData();

		selected = this.selected;
		text = songDataP.displayName;
		locked = !StringTools.contains(FlxG.save.data.unlockedSongs, songDataP.name.toLowerCase());
		unlockable = StringTools.contains(FlxG.save.data.unlockableSongs, songDataP.name.toLowerCase()) && locked;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			icon.color = FlxColor.WHITE;
			songinfo_Sprite.color = FlxColor.WHITE;
			songinfo_Text.color = FlxColor.WHITE;
			songinfo_composer_Text.color = FlxColor.WHITE;
			songinfo_score_Text.color = FlxColor.WHITE;
			songinfo_Rainbow.color = FlxColor.WHITE;
			copyrightText.color = FlxColor.WHITE;
			lock.color = FlxColor.WHITE;
			if (icon.animated)
			{
				icon.playAnim('from-neutral-to-winning');
				icon.animation.finishCallback = () ->
				{
					icon.playAnim('winning');
				};
			}
			else
			{
				icon.globalCurFrame = 2;
			}

			lockedText.color = unlockable ? 0xFFFFCA47 : 0xFF514260;

			for (star in stars)
				star.alpha = locked ? 0.0 : 1.0;

			if (starFlame != null)
				starFlame.playAnim('start');
			if (starFlame != null)
				starFlame.visible = locked ? false : true;
		}
		else
		{
			icon.color = FlxColor.GRAY;
			songinfo_Sprite.color = FlxColor.GRAY;
			songinfo_Text.color = FlxColor.GRAY;
			songinfo_composer_Text.color = FlxColor.GRAY;
			songinfo_score_Text.color = FlxColor.GRAY;
			songinfo_Rainbow.color = FlxColor.GRAY;
			copyrightText.color = FlxColor.GRAY;
			lock.color = FlxColor.GRAY;
			if (icon.animated)
			{
				if (icon.animation.curAnim.name == 'from-neutral-to-winning' || icon.animation.curAnim.name == 'winning')
				{
					icon.playAnim('from-winning-to-neutral', true);
					icon.animation.finishCallback = () ->
					{
						icon.playAnim('neutral');
					};
				}
			}
			else
			{
				icon.globalCurFrame = 0;
			}

			lockedText.color = unlockable ? 0xFF77482C : 0xFF201A26;

			for (star in stars)
				star.alpha = locked ? 0.0 : 0.5;

			if (starFlame != null)
				starFlame.visible = false;
		}

		return (selected = isSelected);
	}

	function set_locked(isLocked:Bool):Bool
	{
		if (isLocked)
		{
			songinfo_Sprite.playAnim('locked');
			icon.visible = false;
			songinfo_Text.visible = false;
			songinfo_composer_Text.visible = false;
			songinfo_score_Text.visible = false;

			if (songDataP.name == "stardom")
				copyrightText.visible = false;

			lock.visible = true;
			lockGlow.visible = true;
			glowSprite.visible = true;
			lockedText.visible = true;
		}
		else
		{
			songinfo_Sprite.playAnim('normal');
			icon.visible = true;
			songinfo_Text.visible = true;
			songinfo_composer_Text.visible = true;
			songinfo_score_Text.visible = true;

			if (songDataP.name == "stardom")
				copyrightText.visible = true;

			lock.visible = false;
			lockGlow.visible = false;
			glowSprite.visible = true;
			lockedText.visible = false;
		}

		return (locked = isLocked);
	}

	function set_unlockable(isUnlockable:Bool):Bool
	{
		if (isUnlockable)
		{
			lockedText.text = i18n.tr('Freeplay/PressToUnlock');
			if (Options.language == 'es_US')
				lockedText.scale.x = 0.5;
		}
		else
		{
		}

		return (unlockable = isUnlockable);
	}

	function set_text(newText:String):String
	{
		songinfo_Text.text = newText;

		return (text = newText);
	}

	function updateData(?diff:String = 'hard')
	{
		var songScore = FunkinSave.getSongHighscore(songDataP.name, diff, songDataP.variant, []);

		if (songScore.score > 0)
		{
			songinfo_score_Text.text = FlxStringUtil.formatMoney(songScore.score, false)
				+ '\n'
				+ FlxMath.roundDecimal((songScore.accuracy * 100), 2)
				+ '% [${songScore.customData.rank}] - ${songScore.customData.fcrank}';
			if (!locked)
				songinfo_Sprite.playAnim(songScore.customData.fcrank.toLowerCase());

			if (songDataP.name == 'stardom' || songDataP.name == 'resonance' || songDataP.name == 'meguca' || songDataP.name == 'partea')
				songinfo_composer_Text.size = 20;
		}
		else
		{
			songinfo_score_Text.text = 'N/A';
			if (!locked)
				songinfo_Sprite.playAnim('normal');

			if (songDataP.name == 'stardom' || songDataP.name == 'resonance')
				songinfo_composer_Text.size = 26;
		}

		if (songinfo_Sprite.getAnimName() == 'mfc')
			songinfo_Rainbow.visible = true;
		else
			songinfo_Rainbow.visible = false;

		songinfo_score_Text.y = songinfo_Sprite.y + songinfo_Sprite.height / 2 - songinfo_score_Text.height / 2.25;
	}

	public function unlockAnimation()
	{
		FlxG.sound.play(Paths.sound('ui/freeplay/lock_break'), 1.0 * Options.volumeSFX);
		FlxTween.num(0, 5, 0.6, {
			ease: FlxEase.quadIn,
			onComplete: function(twn:FlxTween)
			{
				lock.visible = false;
				lockGlow.visible = false;

				glowSprite.alpha = 1.0;
				FlxTween.tween(glowSprite, {alpha: 0.0}, 1.0, {ease: FlxEase.quadOut});
			}
		}, function(num:Float)
		{
			var randomizedXpos:Float = FlxG.random.float(-num, num);
			var randomizedYPos:Float = FlxG.random.float(-num, num);
			lock.offset.x = randomizedXpos;
			lock.offset.y = randomizedYPos;
			lockGlow.offset.x = randomizedXpos;
			lockGlow.offset.y = randomizedYPos;
		});

		FlxTween.tween(lockGlow, {alpha: 1.0}, 0.6, {ease: FlxEase.quadIn});
	}

	public override function update(elapsed)
	{
		super.update(elapsed);
	}

	public function add(obj)
	{
		group.add(obj);
	}

	public function remove(obj)
	{
		group.remove(obj);
	}

	var totalElapsed:Float = 0.0;

	override function update(elapsed)
	{
		super.update(elapsed);
		group.update();

		if (starFlame != null)
			starFlame?.update(elapsed);

		if (icon != null)
			icon?.update(elapsed);

		for (star in stars)
		{
			if (selected && (star.ID < songDataP.customValues.diffStars - 0))
			{
				if (FlxMath.roundDecimal(totalElapsed % 0.03, 2) == 0)
				{
					star.offset.x = FlxG.random.float(0 - (star.ID * 0.15), 0 + (star.ID * 0.15));
					star.offset.y = FlxG.random.float(0 - (star.ID * 0.15), 0 + (star.ID * 0.15));
				}
			}
			else
			{
				star.offset.x = 0;
				star.offset.y = 0;
				if (starFlame != null)
					starFlame.offset.x = 0;
				if (starFlame != null)
					starFlame.offset.y = 0;
			}
		}

		if (Options.gameplayShaders)
		{
			hueShader.hue += elapsed * 120;
		}

		totalElapsed += elapsed;
	}

	override function draw()
	{
		super.draw();
		group.draw();
	}

	override function destroy()
	{
		group.destroy();
		super.destroy();
	}
}
