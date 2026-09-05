import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.addons.display.FlxBackdrop;
import flixel.util.FlxStringUtil;
import openfl.display.BlendMode;
import util.GenUtil;

class GauntletModSelectorUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var defaultColor:FlxColor = FlxColor.WHITE;
	var darkenColor:FlxColor = FlxColor.GRAY;

	public var selected(default, set):Bool = false;
	public var enabled(default, set):Bool = false;
	public var bonusAvaliable(default, set):Bool = false;
	public var locked(default, set):Bool = false;

	public var conflictedMod(default, set):String = '';
	public var additionalConflicts:Int = 0;

	public var data:Dynamic;

	public function new(mod:String)
	{
		super();

		data = gauntletModsData.get(mod);

		group = new FlxSpriteGroup();

		modbg = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/modselector'));
		group.add(modbg);

		modbgtab = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/modselectorcolortab'));
		group.add(modbgtab);

		switch (data.tier)
		{
			case 0:
				defaultColor = 0xFF55C5EF;
				darkenColor = 0xFF2E588C;
			case 1:
				defaultColor = 0xFFF9D922;
				darkenColor = 0xFF886113;
			case 2:
				defaultColor = 0xFFFF0F7B;
				darkenColor = 0xFF8B0647;
			case 3:
				defaultColor = 0xFF46078E;
				darkenColor = 0xFF260353;
		}

		modNameText = new FlxText(0, 0, modbg.width - 125, i18n.tr('Gauntlet/Mods/' + data.nameKey));
		modNameText.setFormat(Paths.font("shingo.otf"), 24, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		modNameText.borderSize = 2.0;
		group.add(modNameText);
		GenUtil.alignToCenter(modNameText, modbg);

		modMutliText = new FlxText(0, 0, modbg.width - 40, GenUtil.padMultiplier(data.multiplier));
		modMutliText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		modMutliText.borderSize = 2.0;
		group.add(modMutliText);
		GenUtil.alignToCenter(modMutliText, modbg);

		if (!data.affectTotalMulti)
		{
			modMutliText.x += 10;
			modMutliText.text = '+' + modMutliText.text;
		}

		checkmark = new FunkinSprite(-6, -6).loadGraphic(Paths.image("ui/gauntlet/modtick"), true, 69, 69);
		checkmark.addAnim('off', null, 0, false, false, [0]);
		checkmark.addAnim('on', null, 0, false, false, [1]);
		add(checkmark);
		checkmark.playAnim('off');

		pairbonusback = new FunkinSprite(-260, 5).loadGraphic(Paths.image('ui/gauntlet/pairbonus'));
		group.add(pairbonusback);
		pairbonusback.blend = BlendMode.ADD;
		FlxTween.color(pairbonusback, 0.5, FlxColor.CYAN, FlxColor.YELLOW, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
		FlxTween.tween(pairbonusback, {x: 1155}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

		pairbonustext = new FlxText(-260, 8, pairbonusback.width, i18n.tr('Gauntlet/EnableForBonus') + '\n+1.00x ${i18n.tr('Gauntlet/Multiplier')}');
		pairbonustext.setFormat(Paths.font("shingo.otf"), 20, FlxColor.BLACK, FlxTextAlign.LEFT);
		group.add(pairbonustext);
		pairbonustext.scale.x = 0.9;
		FlxTween.tween(pairbonustext, {x: 1155}, 0.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

		modDisabledSpr = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/moddisabled'));
		group.add(modDisabledSpr);
		modDisabledSpr.alpha = 1.0;
		modDisabledSpr.blend = BlendMode.MULTIPLY;

		modDisabledTxt = new FlxText(0, 5, modbg.width,
			i18n.tr('Gauntlet/ConflictionWith') + '\n${StringTools.replace(i18n.tr('Gauntlet/Mods/' + data.conflictions[0]), '\n', ' ')}');
		modDisabledTxt.setFormat(Paths.font("shingo.otf"), 24, FlxColor.RED, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		modDisabledTxt.borderSize = 2.0;
		group.add(modDisabledTxt);

		selected = this.selected;
		enabled = this.enabled;
		bonusAvaliable = this.bonusAvaliable;
		locked = this.locked;
		conflictedMod = this.conflictedMod;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			modbg.color = FlxColor.WHITE;
			modbgtab.color = defaultColor;
			modNameText.color = FlxColor.WHITE;
			modMutliText.color = FlxColor.WHITE;
			checkmark.color = FlxColor.WHITE;
		}
		else
		{
			modbg.color = FlxColor.GRAY;
			modbgtab.color = darkenColor;
			modNameText.color = FlxColor.GRAY;
			modMutliText.color = FlxColor.GRAY;
			checkmark.color = FlxColor.GRAY;
		}

		return (selected = isSelected);
	}

	function set_bonusAvaliable(isBonusAvaliable:Bool):Bool
	{
		if (isBonusAvaliable)
		{
			pairbonusback.visible = true;
			pairbonustext.visible = true;
		}
		else
		{
			pairbonusback.visible = false;
			pairbonustext.visible = false;
		}

		return (bonusAvaliable = isBonusAvaliable);
	}

	function set_locked(isLocked:Bool):Bool
	{
		if (isLocked)
		{
			modDisabledSpr.visible = true;
			modDisabledTxt.visible = true;
		}
		else
		{
			modDisabledSpr.visible = false;
			modDisabledTxt.visible = false;
		}

		return (locked = isLocked);
	}

	function set_conflictedMod(newConflictedMod:String):String
	{
		modDisabledTxt.text = i18n.tr('Gauntlet/ConflictionWith') + '\n${StringTools.replace(i18n.tr('Gauntlet/Mods/' + newConflictedMod), '\n', ' ')} ';

		if (additionalConflicts >= 1)
			modDisabledTxt.text += i18n.tr('Gauntlet/AndMore', ["conflictions" => additionalConflicts]);

		return (conflictedMod = newConflictedMod);
	}

	public var doEffect:Bool = false;

	function set_enabled(isEnabled:Bool):Bool
	{
		if (doEffect && enabled != isEnabled)
		{
			var checkmarkChange:FunkinSprite = new FunkinSprite(0, 0).loadGraphic(Paths.image("ui/gauntlet/modtickchange"));
			add(checkmarkChange);
			checkmarkChange.scale.set(0.75, 0.75);
			checkmarkChange.blend = BlendMode.ADD;
			GenUtil.alignToCenter(checkmarkChange, checkmark);
			FlxTween.tween(checkmarkChange, {
				'scale.x': 2.0,
				'scale.y': 2.0,
				alpha: 0.0
			}, 1.5, {
				ease: FlxEase.expoOut,
				onComplete: function(twn:FlxTween)
				{
					checkmarkChange.destroy();
					remove(checkmarkChange, true);
				}
			});

			FlxTween.cancelTweensOf(checkmark);
			checkmark.scale.set(1.5, 1.5);
			FlxTween.tween(checkmark, {'scale.x': 1.0, 'scale.y': 1.0}, 0.75, {ease: FlxEase.expoOut});
		}

		if (isEnabled)
		{
			checkmark.playAnim('on');
		}
		else
		{
			checkmark.playAnim('off');
		}

		doEffect = true;

		return (enabled = isEnabled);
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

	override function update(elapsed)
	{
		super.update(elapsed);
		group.update();

		pairbonusback.alpha = FlxMath.bound(group.alpha, 0, modbg.alpha);
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
