import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import openfl.display.BlendMode;

class Effect extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var effectSprites:Array<FunkinSprite> = [];

	var psi = PlayState.instance;

	public function new(effectType:String)
	{
		super();

		group = new FlxSpriteGroup();
		effect = effectType;

		switch (effect)
		{
			case 'dodge':
				var creationPosition:Array<Float> = [psi.bf.x + 200, psi.bf.y + 275];

				var aura = new FunkinSprite(creationPosition[0], creationPosition[1]);
				aura.loadSprite(Paths.image("game/fx/dodge_perfect_aura"));
				add(aura);
				effectSprites.push(aura);
				aura.origin.set(aura.width / 2, aura.height - 85);
				aura.alpha = 0.25;
				aura.blend = BlendMode.ADD;

				var aura_ring = new FunkinSprite(creationPosition[0] - 30, creationPosition[1] + 310);
				aura_ring.loadSprite(Paths.image("game/fx/dodge_perfect_aura_ring"));
				add(aura_ring);
				effectSprites.push(aura_ring);
				aura_ring.alpha = 0.75;
				aura_ring.blend = BlendMode.ADD;

				FlxTween.tween(aura, {'scale.x': 1.5, 'scale.y': 1.5, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						aura?.destroy();
						remove(aura, true);
					}
				});
				FlxTween.tween(aura_ring, {'scale.x': 1.5, 'scale.y': 1.5, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						aura_ring?.destroy();
						remove(aura_ring, true);
					}
				});

				for (i in 0...7)
				{
					var aura_stars = new FunkinSprite(creationPosition[0] + FlxG.random.int(0, 355), creationPosition[1] + FlxG.random.int(0, 350));
					aura_stars.loadSprite(Paths.image("game/fx/dodge_perfect_star"));
					add(aura_stars);
					effectSprites.push(aura_stars);
					aura_stars.blend = BlendMode.ADD;

					FlxTween.tween(aura_stars, {y: aura_stars.y - FlxG.random.int(50, 350), alpha: 0.0},
						Conductor.stepCrochet * (8 + (FlxG.random.int(0, 8))) / 1000, {
							ease: FlxEase.quadOut,
							onComplete: function(twn:FlxTween)
							{
								aura_stars?.destroy();
								remove(aura_stars, true);
							}
						});
				}

			case 'dodge-perfect':
				var creationPosition:Array<Float> = [psi.bf.x + 200, psi.bf.y + 275];

				var aura = new FunkinSprite(creationPosition[0], creationPosition[1]);
				aura.loadSprite(Paths.image("game/fx/dodge_perfect_aura"));
				add(aura);
				effectSprites.push(aura);
				aura.origin.set(aura.width / 2, aura.height - 85);
				aura.alpha = 0.75;
				aura.blend = BlendMode.ADD;

				var aura_ring = new FunkinSprite(creationPosition[0] - 30, creationPosition[1] + 310);
				aura_ring.loadSprite(Paths.image("game/fx/dodge_perfect_aura_ring"));
				add(aura_ring);
				effectSprites.push(aura_ring);
				aura_ring.blend = BlendMode.ADD;

				FlxTween.tween(aura, {'scale.x': 1.5, 'scale.y': 1.5, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						aura?.destroy();
						remove(aura, true);
					}
				});
				FlxTween.tween(aura_ring, {'scale.x': 1.5, 'scale.y': 1.5, alpha: 0.0}, Conductor.stepCrochet * 8 / 1000, {
					ease: FlxEase.quadOut,
					onComplete: function(twn:FlxTween)
					{
						aura_ring?.destroy();
						remove(aura, true);
					}
				});

				for (i in 0...15)
				{
					var aura_stars = new FunkinSprite(creationPosition[0] + FlxG.random.int(0, 355), creationPosition[1] + FlxG.random.int(0, 350));
					aura_stars.loadSprite(Paths.image("game/fx/dodge_perfect_star"));
					add(aura_stars);
					effectSprites.push(aura_stars);
					aura_stars.blend = BlendMode.ADD;

					FlxTween.tween(aura_stars, {y: aura_stars.y - FlxG.random.int(150, 450), alpha: 0.0},
						Conductor.stepCrochet * (8 + (FlxG.random.int(0, 8))) / 1000, {
							ease: FlxEase.quadOut,
							onComplete: function(twn:FlxTween)
							{
								aura_stars?.destroy();
								remove(aura_stars, true);
							}
						});
				}
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

		group.velocity.x += 5;
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
