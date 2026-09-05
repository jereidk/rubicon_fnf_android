import flixel.addons.display.FlxBackdrop;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import openfl.display.BlendMode;
import util.GenUtil;

class GauntletBackgrounds extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var background:String = '';
	var movingOnSelection = [];

	public var ambienceSnd:FlxSound;

	public function new(background:String)
	{
		FlxG.sound.load(Paths.sound('ui/gauntlet/${background}_bg'));

		super();

		group = new FlxSpriteGroup();

		switch (background)
		{
			case 'peaceful':
				bg_base = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/bg'));
				group.add(bg_base);

				bg_stars = new FlxBackdrop(Paths.image('ui/gauntlet/bgs/peaceful/stars'), FlxAxes.XY, 0, 0);
				group.add(bg_stars);
				bg_stars.blend = BlendMode.ADD;

				bg_backFog = new FlxBackdrop(Paths.image('ui/gauntlet/bgs/peaceful/fogback'), FlxAxes.X, 0, 0);
				group.add(bg_backFog);
				bg_backFog.y = 400;
				bg_backFog.blend = BlendMode.ADD;

				bg_fieldBack = new FunkinSprite(0, 650).loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/fieldback'));
				group.add(bg_fieldBack);

				bg_field = new FunkinSprite(0, 750).loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/field'));
				group.add(bg_field);

				bg_madoka = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/madoka'));
				group.add(bg_madoka);
				bg_madoka.setPosition((FlxG.width - (bg_madoka.width)) * 0.185, (FlxG.height - (bg_madoka.height)) * 0.15);
				bg_madoka.origin.set(bg_madoka.width, bg_madoka.height);
				bg_madoka.angle = -0.5;

				bg_sayaka = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/sayaka'));
				group.add(bg_sayaka);
				bg_sayaka.setPosition((FlxG.width - (bg_sayaka.width)) * 0.825, (FlxG.height - (bg_sayaka.height)) * -0.05);
				bg_sayaka.origin.set(0, bg_sayaka.height);
				bg_sayaka.angle = 0.5;

				bg_gf = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/peaceful/gf'));
				group.add(bg_gf);
				bg_gf.setPosition((FlxG.width - (bg_gf.width)) * 0.5, (FlxG.height - (bg_gf.height)) * 1.0);

				for (spr in [bg_madoka, bg_sayaka, bg_gf])
					movingOnSelection.push(spr);

				for (spr in movingOnSelection)
					spr.x -= 200;

				FlxTween.tween(bg_gf, {y: bg_gf.y + 5}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
				FlxTween.tween(bg_madoka, {y: bg_madoka.y - 5, angle: 0.5}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});
				FlxTween.tween(bg_sayaka, {y: bg_sayaka.y - 5, angle: -0.5}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

			case 'stressed':
				bg_base = new FunkinSprite(0, 0).loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/bg'));
				group.add(bg_base);

				bg_clouds = new FlxBackdrop(Paths.image('ui/gauntlet/bgs/stressed/clouds'), FlxAxes.X, 0, 0);
				add(bg_clouds);
				bg_clouds.y = 0;

				bg_fogback = new FlxBackdrop(Paths.image('ui/gauntlet/bgs/stressed/fogback'), FlxAxes.X, 0, 0);
				add(bg_fogback);
				bg_fogback.y = 425;
				bg_fogback.velocity.set(25, 0);

				bg_fieldback = new FunkinSprite(0, 650).loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/fieldback'));
				add(bg_fieldback);

				bg_kyubey = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/kyubey'));
				add(bg_kyubey);
				bg_kyubey.setPosition((FlxG.width - (bg_kyubey.width)) * 0.10, (FlxG.height - (bg_kyubey.height)) * 0.25);

				bg_field = new FunkinSprite(0, 750).loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/field'));
				add(bg_field);

				bg_homura = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/homura'));
				add(bg_homura);
				bg_homura.setPosition((FlxG.width - (bg_homura.width)) * 0.95, (FlxG.height - (bg_homura.height)) * 0.05);
				bg_homura.origin.set(0, bg_homura.height);
				bg_homura.angle = 0.5;

				FlxTween.tween(bg_homura, {y: bg_homura.y - 5, angle: -0.5}, 2.5, {ease: FlxEase.sineInOut, type: FlxTween.PINGPONG});

				bg_gf = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/stressed/gf'));
				add(bg_gf);
				bg_gf.setPosition((FlxG.width - (bg_gf.width)) * 0.5, (FlxG.height - (bg_gf.height)) * 1.0);

				for (spr in [bg_kyubey, bg_homura, bg_gf])
					movingOnSelection.push(spr);

				for (spr in movingOnSelection)
					spr.x -= 200;

			case 'hopeless':
				bg_bg = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/hopeless/bg'));
				add(bg_bg);

				kyubeyShader = new CustomShader('wave');
				kyubeyShader.strength = 1.0;
				kyubeyShader.speed = 15;

				bg_kyubey = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/hopeless/kyubey'));
				add(bg_kyubey);
				bg_kyubey.setPosition((FlxG.width - (bg_kyubey.width)) * 0.5, (FlxG.height - (bg_kyubey.height)) * 0.5);
				bg_kyubey.shader = kyubeyShader;

				bg_kyubeyglow = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/hopeless/kyubeyglow'));
				add(bg_kyubeyglow);
				bg_kyubeyglow.setPosition((FlxG.width - (bg_kyubeyglow.width)) * 0.5, (FlxG.height - (bg_kyubeyglow.height)) * 0.5);
				bg_kyubeyglow.blend = BlendMode.ADD;

				bg_gf = new FunkinSprite().loadGraphic(Paths.image('ui/gauntlet/bgs/hopeless/gf'));
				add(bg_gf);
				bg_gf.setPosition((FlxG.width - (bg_gf.width)) * 0.5, (FlxG.height - (bg_gf.height)) * 1.0);

				for (spr in [bg_kyubey, bg_kyubeyglow, bg_gf])
					movingOnSelection.push(spr);

				for (spr in movingOnSelection)
					spr.x -= 200;
		}

		ambienceSnd = new FlxSound().loadEmbedded(Paths.sound('ui/gauntlet/${background}_bg'), true, false);
		FlxG.sound.list.add(ambienceSnd);
		if (background == 'peaceful')
			ambienceSnd.volume = 0.75;

		this.background = background;
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

	var totalElapsed:Float = 0;

	override function update(elapsed)
	{
		super.update(elapsed);
		group.update();

		totalElapsed += elapsed;

		switch (background)
		{
			case 'peaceful':
				bg_stars.setPosition(bg_stars.x + 5 * elapsed, bg_stars.y + 2 * elapsed);
				bg_backFog.x = bg_backFog.x + 25 * elapsed;
			case 'stressed':
				bg_clouds.x = bg_clouds.x + 15 * elapsed;
				bg_fogback.x = bg_fogback.x + 25 * elapsed;
				if (FlxMath.roundDecimal(totalElapsed % 0.05, 2) == 0)
				{
					bg_gf.offset.set(FlxG.random.float(-0.5, 0.5), FlxG.random.float(-0.5, 0.5));
				}
			case 'hopeless':
				if (Options.gameplayShaders)
				{
					if (FlxMath.roundDecimal(totalElapsed % 0.1, 2) == 0)
						kyubeyShader.time = FlxG.random.int(0, 2500);
				}
				if (FlxMath.roundDecimal(totalElapsed % 0.03, 2) == 0)
				{
					bg_gf.offset.set(FlxG.random.float(-1, 1), FlxG.random.float(-1, 1));
				}
		}
	}

	public function fadeOut(?fadeOutTime:Float = 0.5)
	{
		switch (background)
		{
			case 'peaceful':
				for (spr in group)
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 0.0}, fadeOutTime, {ease: FlxEase.cubeOut});
				}

			case 'stressed':
				for (spr in group)
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 0.0}, fadeOutTime, {ease: FlxEase.cubeOut});
				}

			case 'hopeless':
				for (spr in group)
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 0.0}, fadeOutTime, {ease: FlxEase.cubeOut});
				}
		}

		ambienceSnd.stop();
	}

	public function fadeIn(?intro:Bool = false)
	{
		switch (background)
		{
			case 'peaceful':
				for (spr in group)
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 1.0}, 0.5, {ease: FlxEase.cubeOut});
				}

			case 'stressed':
				for (spr in group)
				{
					FlxTween.cancelTweensOf(spr, ['alpha']);
					FlxTween.tween(spr, {alpha: 1.0}, 0.5, {ease: FlxEase.cubeOut});
				}

			case 'hopeless':
				new FlxTimer().start(0.45, function(tmr:FlxTimer)
				{
					for (spr in group)
					{
						FlxTween.cancelTweensOf(spr, ['alpha']);
						FlxTween.tween(spr, {alpha: 1.0}, 0.15, {ease: FlxEase.cubeOut});
					}
				});
		}
		if (intro)
			ambienceSnd.fadeIn(1.0, 0.0, 1.0);
		else
			ambienceSnd.play();
	}

	public function slideIn()
	{
		for (spr in movingOnSelection)
			FlxTween.tween(spr, {x: spr.x + 200}, 1.0, {ease: FlxEase.cubeOut});
	}

	override function draw()
	{
		super.draw();
		group.draw();
	}

	override function destroy()
	{
		group.destroy();

		ambienceSnd?.destroy();
		FlxG.sound.list.remove(ambienceSnd);

		super.destroy();
	}
}
