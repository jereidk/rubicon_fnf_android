import funkin.graphics.FunkinSprite;
import flixel.addons.display.FlxBackdrop;
import funkin.audio.FunkinSound;
import funkin.play.stage.ScriptedStage;
import funkin.graphics.shaders.OverlayBlend;
import funkin.Conductor;
import flixel.addons.effects.FlxTrail;
import flixel.group.FlxTypedGroup;
import funkin.play.character.CharacterType;
import funkin.modding.base.ScriptedFlxRuntimeShader;
import openfl.filters.ShaderFilter;
import flixel.util.helpers.FlxPointRangeBounds;
import funkin.graphics.shaders.DropShadowShader;
import funkin.graphics.shaders.DrowShadowAnimateShader;

class PhoneCallStreet extends ScriptedStage
{
	var bloomShader = new BloomShader();
	var bloomFilter;

	var leafs = [];

	function new()
	{
		super('phoneCallStreet');
	}

	override function resetStage()
	{
		super.resetStage();
	}

	override function onUpdate(e)
	{
		super.onUpdate(e);
		if (Preferences.lowQuality)
			return;
	
		for (leaf in leafs)
		{
			if (leaf.y > 1550)
				createLeaf(false, leaf);
		}
	}

	public override function addCharacter(character:BaseCharacter, charType:CharacterType):Void
	{
		super.addCharacter(character, charType);
		if (charType == CharacterType.DAD)
			character?.scrollFactor.set(0.9, 0.95);
	}

	var bgSky:FlxBackdrop = null;

	function buildStage()
	{
		super.buildStage();
		if (Preferences.shaders)
			FlxG.camera.setFilters([bloomFilter = new ShaderFilter(bloomShader)]);

		bgSky = new FlxBackdrop(Paths.image('stages/phoneCallStreet/sky'), 0x01, -1885.85, -831.5);
		bgSky.scrollFactor.set(0.1, 0.1);
		bgSky.velocity.x = 20;
		bgSky.scale.set(1.2, 1.2);
		bgSky.zIndex = -13;
		add(bgSky);

		var lightShade = getNamedProp("lightShade");
		if (lightShade != null)
		{
			var width = 1882.6 * 3;
			lightShade.scrollFactor.set(0., 1.);
			lightShade.blend = 0;
			lightShade.alpha = 0.1;
			lightShade.scale.x = width;
			lightShade.scale.y *= 2;
			lightShade.updateHitbox();
		}

		var overl = getNamedProp("overlay-all");
		overl.shouldDraw = true;

		for (prop in namedProps)
			if (prop.name.indexOf("stand-") != -1)
				prop.visible = false;

		for (leaf in leafs)
			if (leaf != null)
				leaf.kill();

		leafs = [];

		if (Preferences.lowQuality)
			return;

		for (i in 0...3)
			createLeaf(true);
	}

	var leafsBounds = [-1500, 1500, -150, 50];

	function createLeaf(forceNew:Bool = false, ?oldLeaf:FunkinSprite)
	{
		if (Preferences.lowQuality)
			return;

		var leaf;
		if (oldLeaf != null)
		{
			leaf = oldLeaf;
		}
		else if (forceNew)
		{
			leaf = new FunkinSprite();
			leaf.zIndex = 999;
			leaf.shouldDraw = true;
			leaf.frames = Paths.getSparrowAtlas("stages/phoneCallStreet/leafs");
			for (i in 1...5)
				leaf.animation.addByPrefix("y", "leaf", 24, true);
		}

		leaf.angularVelocity = FlxG.random.float(-25, 65);
		leaf.velocity.x = FlxG.random.float(-225, 275);
		leaf.velocity.y = FlxG.random.float(225, 450);
		leaf.animation.play("y", true);
		leaf.zIndex = 900;
		leaf.animation.curAnim.curFrame = FlxG.random.int(1,9);
		leaf.animation.curAnim.frameRate = FlxG.random.int(4, 24);

		leaf.x = FlxG.random.float(leafsBounds[0], leafsBounds[1]);
		leaf.y = FlxG.random.float(leafsBounds[2], leafsBounds[3]);
		leaf.zoomFactor = FlxG.random.float(.7, .9);
		leaf.scale.x = leaf.scale.y = FlxG.random.float(1.1, 1.35);
		leaf.scrollFactor.x = FlxG.random.float(.9, 1.1);
		if (oldLeaf == null)
		{
			add(leaf);
			leafs.push(leaf);
		}
		refresh();
	}

	public override function onBeatHit(event:CountdownScriptEvent):Void
	{
		super.onBeatHit(event);

		if (PlayState.instance.isPlayerDying)
			return;

		if (Preferences.lowQuality)
			return;

		if (FlxG.random.bool(10) && leafs.length <= 9)
			createLeaf(leafs.length <= 9);
	}
}
