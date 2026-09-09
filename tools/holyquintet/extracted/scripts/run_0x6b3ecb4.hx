import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import util.GenUtil;

class JudgementDisplayUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var gradientBG:FunkinSprite;

	var comboNumbers:Array<FunkinSprite> = [];
	var judgement_fades:Array<Dynamic> = [];

	var displayTimer:Float = 0.0;
	var shaking:Float = 0.0;
	var shaking_Tween:FlxTween;
	var judgement_Tween:FlxTween;
	var judgement_flashTween:FlxTween;
	var comboNumbers_Tweens:Array<FlxTween> = [];
	var milsecs_tween:FlxTween;
	var defaultColor:FlxColor = 0xFFFFFFFF;

	var lastCombo:Int = 0;

	var psi = PlayState.instance;

	var style:String = PlayState.SONG.meta.customValues.uiStyle;

	public function new()
	{
		super();

		group = new FlxSpriteGroup();
		switch (style)
		{
			case 'MegucaUI':
				FlxG.sound.load(Paths.sound("game/break_meguca"));
				// Judgement
				judgement = new FunkinSprite(150, 650).loadGraphic(Paths.image('game/judgement/ratings-meguca'), true, 400, 113);
				judgement.addAnim('sick', null, 0, false, false, [0]);
				judgement.addAnim('good', null, 0, false, false, [1]);
				judgement.addAnim('bad', null, 0, false, false, [2]);
				judgement.addAnim('shit', null, 0, false, false, [3]);
				judgement.addAnim('break', null, 0, false, false, [4]);
				add(judgement);

				// Combo
				combo = new FlxText(judgement.x, judgement.y + 85, judgement.width, '');
				combo.setFormat(Paths.font("arial.ttf"), 72, 0xFF131838, FlxTextAlign.CENTER);
				add(combo);

				// Miliseconds
				milsecs = new FlxText(judgement.x, judgement.y + 160, judgement.width, '');
				milsecs.setFormat(Paths.font("arial.ttf"), 32, 0xFF636A96, FlxTextAlign.CENTER);
				add(milsecs);

				for (spr in [judgement, combo, milsecs])
					judgement_fades.push(spr);
				for (spr in judgement_fades)
					spr.alpha = 0.0;
			default:
				FlxG.sound.load(Paths.sound("game/break_stage1"));
				FlxG.sound.load(Paths.sound("game/break_stage2"));
				FlxG.sound.load(Paths.sound("game/break_stage3"));
				FlxG.sound.load(Paths.sound("game/break_stage4"));
				FlxG.sound.load(Paths.sound("game/break_stage5"));
				// Judgement BG
				gradientBG = new FunkinSprite(0, 0).loadGraphic(Paths.image("game/judgement/bg"));
				add(gradientBG);
				gradientBG.screenCenter(FlxAxes.Y);

				// Judgement
				judgement = new FunkinSprite(gradientBG.x,
					gradientBG.y - 25).loadGraphic(Paths.image('game/judgement/ratings-${Options.language}'), true, 400, 120);
				judgement.addAnim('sick', null, 0, false, false, [0]);
				judgement.addAnim('good', null, 0, false, false, [1]);
				judgement.addAnim('bad', null, 0, false, false, [2]);
				judgement.addAnim('shit', null, 0, false, false, [3]);
				judgement.addAnim('break', null, 0, false, false, [4]);
				add(judgement);

				// Combo
				for (i in 0...4)
				{
					var number:FunkinSprite = new FunkinSprite(70 + (60 * i), 0).loadGraphic(Paths.image('game/judgement/numbers'), true, 95, 119);
					number.setGraphicSize(Std.int(number.width * 0.75));
					number.updateHitbox();
					for (i in 0...10)
					{
						number.addAnim(Std.string(i), null, 0, false, false, [i]);
					}
					add(number);
					number.screenCenter(FlxAxes.Y);
					number.y += 42;
					number.playAnim('0');
					comboNumbers.push(number);
					judgement_fades.push(number);
				}

				divider = new FunkinSprite(0, 0).loadGraphic(Paths.image("game/judgement/divider"));
				add(divider);
				divider.screenCenter(FlxAxes.Y);

				// Miliseconds
				milsecs = new FlxText(gradientBG.x, gradientBG.y + 170, gradientBG.width, '');
				milsecs.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0x88000000);
				milsecs.borderSize = 2.5;
				add(milsecs);

				for (spr in [gradientBG, judgement, divider, milsecs])
					judgement_fades.push(spr);
				for (spr in judgement_fades)
					spr.alpha = 0.0;

				gradientBG.color = psi.dad.iconColor;
				defaultColor = gradientBG.color;

				judgement_flash = new CustomShader("WhiteOverlay");
				judgement_flash.strength = 0.0;
				judgement.shader = judgement_flash;
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

		if (displayTimer > 0.0)
		{
			displayTimer -= 1.0 * elapsed;
			for (spr in judgement_fades)
				spr.alpha = 1.0;
		}
		else
		{
			switch (style)
			{
				case 'MegucaUI':
					for (spr in judgement_fades)
						spr.alpha = 0.0;
				default:
					for (spr in judgement_fades)
						spr.alpha -= 2.5 * elapsed;
			}
		}

		judgement.offset.x = FlxG.random.float(-shaking, shaking);
		judgement.offset.y = FlxG.random.float(-shaking, shaking);
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

	public function updateJudgement(judgementstring:String, ?e:Dynamic)
	{
		displayTimer = 1.5;
		switch (style)
		{
			case 'MegucaUI':
				if (judgementstring != 'break')
				{
					lastCombo = psi.combo;

					// Judgement
					judgement.playAnim(judgementstring);

					// Combo
					combo.text = psi.combo;

					// Miliseconds
					if (milsecs_tween != null)
						milsecs_tween.cancel();

					milsecs.text = '(' + FlxMath.roundDecimal(Math.abs(Conductor.songPosition - e.note.strumTime), 2) + 'ms)';
				}
				else
				{
					FlxG.sound.play(Paths.sound('game/break_meguca'), 0.8 * Options.volumeSFX);

					// Judgement
					judgement.playAnim(judgementstring);

					// Combo
					combo.text = '0';

					// Miliseconds
					milsecs.text = '';
				}

			default:
				if (judgementstring != 'break')
				{
					lastCombo = psi.combo;

					if (shaking_Tween != null)
						shaking_Tween.cancel();

					shaking = 0;
					// Judgement BG
					gradientBG.color = defaultColor;

					// Judgement
					if (judgement_Tween != null)
						judgement_Tween.cancel();

					if (judgement_flashTween != null)
						judgement_flashTween.cancel();

					judgement.angle = FlxG.random.int(-2, 2);
					judgement.scale.set(1.15, 1.15);
					judgement.playAnim(judgementstring);

					judgement_Tween = FlxTween.tween(judgement, {'scale.x': 1.0, 'scale.y': 1.0}, Conductor.crochet / 1000, {
						ease: FlxEase.expoOut
					});

					if (judgementstring == 'sick')
					{
						judgement_flash.strength = 1.0;
						judgement_flashTween = FlxTween.num(1.0, 0.0, Conductor.crochet / 1000, {ease: FlxEase.expoOut}, function(num:Float)
						{
							judgement_flash.strength = num;
						});
					}
					else
					{
						judgement_flash.strength = 0.0;
					}

					// Combo
					var seperatedScore:Array<Int> = [];
					seperatedScore.push(Math.floor(psi.combo / 1000) % 10);
					seperatedScore.push(Math.floor(psi.combo / 100) % 10);
					seperatedScore.push(Math.floor(psi.combo / 10) % 10);
					seperatedScore.push(psi.combo % 10);

					for (twn in comboNumbers_Tweens)
					{
						if (twn != null)
							twn.cancel();
					}

					for (i in 0...4)
					{
						comboNumbers[i].animation.play(Std.string(seperatedScore[i]));
						comboNumbers[i].color = FlxColor.GRAY;
						FlxTween.cancelTweensOf(comboNumbers[i]);
						comboNumbers[i].scale.set(0.75, 0.75);
						comboNumbers[i].alpha = 1.0;
					}

					var judgementNumsToAnimate:Array<Int> = [3];

					if (psi.combo > 9)
						judgementNumsToAnimate.push(2);
					if (psi.combo > 99)
						judgementNumsToAnimate.push(1);
					if (psi.combo > 999)
						judgementNumsToAnimate.push(0);

					for (i in 0...4)
					{
						if (judgementNumsToAnimate.contains(i))
						{
							comboNumbers[i].color = FlxColor.WHITE;
							comboNumbers[i].scale.set(0.9, 0.9);
							FlxTween.tween(comboNumbers[i], {'scale.x': 0.75, 'scale.y': 0.75}, Conductor.crochet / 1000, {ease: FlxEase.expoOut});
						}
					}

					// Miliseconds
					if (milsecs_tween != null)
						milsecs_tween.cancel();

					milsecs.text = FlxMath.roundDecimal(Math.abs(Conductor.songPosition - e.note.strumTime), 2) + 'ms';
					milsecs.scale.set(1.15, 1.15);
					milsecs_tween = FlxTween.tween(milsecs, {'scale.x': 1.0, 'scale.y': 1.0}, Conductor.crochet / 1000, {
						ease: FlxEase.expoOut
					});
				}
				else
				{
					var breakTier:Int = 1;
					if (lastCombo > 500)
						breakTier = 5;
					else if (lastCombo > 300)
						breakTier = 4;
					else if (lastCombo > 150)
						breakTier = 3;
					else if (lastCombo > 50)
						breakTier = 2;

					FlxG.sound.play(Paths.sound('game/break_stage$breakTier'), 1.0 * Options.volumeSFX).pitch = FlxG.random.float(0.95, 1.05);

					if (shaking_Tween != null)
						shaking_Tween.cancel();

					shaking_Tween = FlxTween.num(50, 0.0, Conductor.crochet / 250, {ease: FlxEase.expoOut}, function(num:Float)
					{
						shaking = num;
					});

					// Judgement BG
					gradientBG.color = 0xFF393854;

					// Judgement
					if (judgement_Tween != null)
						judgement_Tween.cancel();

					if (judgement_flashTween != null)
						judgement_flashTween.cancel();

					judgement_flash.strength = 0.0;
					judgement.angle = 0;
					judgement.scale.set(1.0, 1.0);
					judgement.playAnim(judgementstring);

					// Combo
					for (i in 0...4)
					{
						comboNumbers[i].animation.play(Std.string('0'));
						comboNumbers[i].color = FlxColor.GRAY;
						FlxTween.cancelTweensOf(comboNumbers[i]);
						comboNumbers[i].scale.set(0.75, 0.75);
						comboNumbers[i].alpha = 1.0;
					}

					// Miliseconds
					if (milsecs_tween != null)
						milsecs_tween.cancel();

					milsecs.text = '';
					milsecs.scale.set(1.0, 1.0);
				}
		}
	}
}
