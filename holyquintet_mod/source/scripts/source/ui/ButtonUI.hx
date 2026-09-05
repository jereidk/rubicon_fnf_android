import flixel.math.FlxRect;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

using StringTools;

class ButtonUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	public var button_Sprite:FunkinSprite;

	public var button_Text:FlxText;

	public var button_Selected:FunkinSprite;
	public var button_Highlight:FunkinSprite;

	public var button_HighlightTween:FlxTween;

	var style:String = 'basic';

	public var selected(default, set):Bool = false;
	public var locked(default, set):Bool = false;
	public var text(default, set):String = 'Button';
	public var subText(default, set):String = '';
	public var icon(default, set):String = 'none';

	public function new(?x:Float = 0, ?y:Float = 0, theStyle:String = 'basic')
	{
		super(x, y, theStyle);
		style = theStyle;

		group = new FlxSpriteGroup(x, y);

		switch (style)
		{
			case 'basic' | 'gj':
				button_Sprite = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/button-$style'), true, 450, 139);
				button_Sprite.addAnim('normal', null, 0, false, false, [0]);
				button_Sprite.addAnim('highlighted', null, 0, false, false, [1]);
				button_Sprite.addAnim('disabled', null, 0, false, false, [2]);
				group.add(button_Sprite);

				button_Text = new FlxText(0, 0, button_Sprite.width - (button_Sprite.width * 0.20), '');
				button_Text.setFormat(Paths.font("shingo.otf"), 52, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				button_Text.borderSize = 2.5;
				group.add(button_Text);

				button_SubText = new FlxText(0, 0, button_Sprite.width - (button_Sprite.width * 0.20), '');
				button_SubText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				button_SubText.borderSize = 2.5;
				group.add(button_SubText);

				button_Lock = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/lock'));
				group.add(button_Lock);

			case 'small':
				button_Sprite = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/button-$style'), true, 154, 139);
				button_Sprite.addAnim('normal', null, 0, false, false, [0]);
				button_Sprite.addAnim('highlighted', null, 0, false, false, [1]);
				button_Sprite.addAnim('disabled', null, 0, false, false, [2]);
				group.add(button_Sprite);

				button_Text = new FlxText(0, 0, button_Sprite.width - (button_Sprite.width * 0.20), '');
				button_Text.setFormat(Paths.font("shingo.otf"), 52, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				button_Text.borderSize = 2.5;
				group.add(button_Text);

				button_SubText = new FlxText(0, 0, button_Sprite.width - (button_Sprite.width * 0.20), '');
				button_SubText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
				button_SubText.borderSize = 2.5;
				group.add(button_SubText);

				button_Icon = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/icons/none'));
				group.add(button_Icon);

				button_Lock = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/lock'));
				group.add(button_Lock);

				text = '';
		}

		switch (style)
		{
			case 'basic':
				GenUtil.alignToCenter(button_Text, button_Sprite);
				GenUtil.alignToCenter(button_SubText, button_Sprite);
				GenUtil.alignToCenter(button_Lock, button_Sprite);
				button_Lock.x += 150;
				button_Lock.y -= 5;
			case 'small':
		}

		button_Hold = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/button_hold-$style'));
		group.insert(group.members.indexOf(button_Sprite) + 1, button_Hold);
		button_Hold.clipRect = new FlxRect(0, 0, Std.int(button_Hold.width), Std.int(button_Hold.height));
		button_Hold.clipRect.width = 0;
		button_Hold.clipRect = button_Hold.clipRect;

		button_Selected = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/button_selected-$style'));
		group.add(button_Selected);
		button_Selected.alpha = 0.0;

		button_Highlight = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/common/button_highlight-$style'));
		group.add(button_Highlight);
		button_Highlight.alpha = 1.0;

		selected = this.selected;
		locked = this.locked;
		text = this.text;
		subText = this.subText;
		icon = this.icon;
	}

	function set_selected(isSelected:Bool):Bool
	{
		if (isSelected)
		{
			if (!locked)
				button_Sprite.playAnim('highlighted');
			else
				button_Sprite.playAnim('disabled');

			if (!locked)
			{
				button_Sprite.color = FlxColor.WHITE;
				button_Highlight.color = FlxColor.WHITE;
				button_Text.color = FlxColor.WHITE;
				button_SubText.color = FlxColor.WHITE;
				button_Selected.color = FlxColor.WHITE;
				button_Text.borderSize = 3.0;
				button_SubText.borderSize = 3.0;
			}
			else
			{
				button_Sprite.color = FlxColor.WHITE;
				button_Highlight.color = FlxColor.GRAY;
				button_Lock.color = FlxColor.WHITE;
				button_Selected.color = FlxColor.WHITE;
				button_Text.color = 0xFF514260;
				button_SubText.color = 0xFF514260;
				button_Text.borderSize = 0.0;
				button_SubText.borderSize = 0.0;
			}

			if (style == 'small')
				button_Icon.color = FlxColor.WHITE;

			button_HighlightTween?.cancel();
			button_Highlight.scale.set(1.00, 1.00);
			button_Highlight.alpha = 1.0;

			button_HighlightTween = FlxTween.tween(button_Highlight, {'scale.x': 1.05, 'scale.y': 1.05, alpha: 0.0}, 1.0,
				{ease: FlxEase.quadOut, type: FlxTween.LOOPING, loopDelay: 0.5});
		}
		else
		{
			if (!locked)
				button_Sprite.playAnim('normal');
			else
				button_Sprite.playAnim('disabled');

			if (!locked)
			{
				button_Sprite.color = FlxColor.GRAY;
				button_Text.color = FlxColor.GRAY;
				button_SubText.color = FlxColor.GRAY;
				button_Text.borderSize = 3.0;
				button_SubText.borderSize = 3.0;
			}
			else
			{
				button_Sprite.color = FlxColor.GRAY;
				button_Lock.color = FlxColor.GRAY;
				button_Text.color = 0xFF201A26;
				button_SubText.color = 0xFF201A26;
				button_Text.borderSize = 0.0;
				button_SubText.borderSize = 0.0;
			}

			if (style == 'small')
				button_Icon.color = FlxColor.GRAY;

			button_HighlightTween?.cancel();
			button_Highlight.scale.set(1.00, 1.00);
			button_Highlight.alpha = 0.0;
		}

		return (selected = isSelected);
	}

	function set_locked(isLocked:Bool):Bool
	{
		if (isLocked)
		{
			button_Sprite.playAnim('disabled');

			button_Sprite.color = FlxColor.WHITE;
			button_Text.color = FlxColor.WHITE;
			button_SubText.color = FlxColor.WHITE;
			if (style != 'small')
				button_Lock.visible = true;
		}
		else
		{
			button_Sprite.playAnim('normal');

			button_Sprite.color = FlxColor.GRAY;
			button_Text.color = FlxColor.GRAY;
			button_SubText.color = FlxColor.GRAY;
			button_Lock.visible = false;

			button_HighlightTween?.cancel();
			button_Highlight.scale.set(1.0, 1.0);
			button_Highlight.alpha = 0.0;
		}

		return (locked = isLocked);
	}

	function set_text(newText:String):String
	{
		button_Text.text = newText;

		GenUtil.alignToCenter(button_Text, button_Sprite);

		if (button_SubText.text != '')
			button_Text.y -= 12;

		if (locked)
		{
			button_Text.scale.x = 0.9;
			button_Text.x -= 30;
			button_SubText.scale.x = 0.9;
			button_SubText.x -= 30;
		}
		else
		{
			button_Text.scale.x = 1.0;
			button_SubText.scale.x = 1.0;
		}

		return (text = newText);
	}

	function set_subText(newsubText:String):String
	{
		button_SubText.text = newsubText;

		GenUtil.alignToCenter(button_SubText, button_Sprite);
		button_SubText.y += 32;

		text = text;

		return (subText = newsubText);
	}

	function set_icon(newIcon:String):String
	{
		if (style == 'small')
		{
			button_Icon.loadGraphic(Paths.image('ui/common/icons/$newIcon'));
			icon = icon;
		}

		return (icon = newIcon);
	}

	public function selection()
	{
		if (!locked)
		{
			button_Selected.alpha = 1.0;
			button_Selected.scale.set(1.0, 1.0);
			FlxTween.tween(button_Selected, {'scale.x': 1.15, 'scale.y': 1.15, alpha: 0.0}, 1.0, {ease: FlxEase.quadOut});

			button_HighlightTween?.cancel();
			button_Highlight.scale.set(1.00, 1.00);
			button_Highlight.alpha = 0.0;
		}
		else
		{
		}
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
