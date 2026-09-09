import flixel.input.keyboard.FlxKey;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxStringUtil;
import util.GenUtil;
import util.ColorUtil;

class ResultJudgementUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var psi = PlayState.instance;

	var originalColor:FlxColor = FlxColor.WHITE;

	public var judgementID:Int = 0;
	public var scoreBonus:Int = 0;

	var countTo:Int = 0;

	public function new(?x:Float = 0, ?y:Float = 0, ?judgement:String = '')
	{
		super(x, y);

		switch (judgement)
		{
			case 'sick':
				judgementID = 0;
				scoreBonus = 50;
			case 'good':
				judgementID = 1;
				scoreBonus = 25;
			case 'bad':
				judgementID = 2;
				scoreBonus = -5;
			case 'shit':
				judgementID = 3;
				scoreBonus = -100;
			case 'break':
				judgementID = 4;
				scoreBonus = -500;
		}

		group = new FlxSpriteGroup(x, y);

		bgFade = new FunkinSprite(0, 0).loadSprite(Paths.image('game/results/bgjudgement'));
		group.add(bgFade);

		bgFadeShine = new FunkinSprite(0, 0).loadSprite(Paths.image('game/results/bgjudgementshine'));
		group.add(bgFadeShine);
		bgFadeShine.blend = BlendMode.ADD;
		bgFadeShine.visible = false;

		switch (judgementID)
		{
			case 0:
				bgFade.color = 0xFFFF76A3;
				countTo = psi.hits[0];
			case 1:
				bgFade.color = 0xFFFFA6C4;
				countTo = psi.hits[1];
			case 2:
				bgFade.color = 0xFF523363;
				countTo = psi.hits[2];
			case 3:
				bgFade.color = 0xFF1E0F35;
				countTo = psi.hits[3];
			case 4:
				bgFade.color = 0xFF190F26;
				countTo = psi.misses;
		}

		originalColor = bgFade.color;
		bgFadeShine.color = originalColor;

		judgementSprite = new FunkinSprite(-175, 0).loadGraphic(Paths.image('game/judgement/ratings-${Options.language}'), true, 400, 120);
		judgementSprite.addAnim('idle', null, 0, false, false, [judgementID]);
		group.add(judgementSprite);
		judgementSprite.playAnim('idle');

		judgementCount = new FlxText(0, 0, bgFade.width - (bgFade.width * 0.05), '0');
		judgementCount.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		judgementCount.borderSize = 2.5;
		group.add(judgementCount);
		judgementCount.setPosition(bgFade.x, bgFade.y + bgFade.height / 2 - judgementCount.height / 2);
		judgementCount.origin.set(judgementCount.width, judgementCount.height);

		judgementBonus = new FlxText(bgFade.x, bgFade.y, bgFade.width - (bgFade.width * 0.05), '+0');
		judgementBonus.setFormat(Paths.font("rowdy.otf"), 38, 0xFFFFD16E, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFFB47125);
		if (judgement == 'bad' || judgement == 'shit' || judgement == 'break')
			judgementBonus.setFormat(Paths.font("rowdy.otf"), 38, 0xFF9B90FF, FlxTextAlign.RIGHT, FlxTextBorderStyle.OUTLINE, 0xFF4B2494);
		judgementBonus.borderSize = 2.5;
		add(judgementBonus);
		judgementBonus.setPosition(bgFade.x + 50, bgFade.y + bgFade.height - 32);
		judgementBonus.visible = false;

		judgementSprite.color = FlxColor.GRAY;
		judgementCount.color = FlxColor.GRAY;
		bgFade.color = ColorUtil.getDarkened(bgFade.color, 0.5);

		tickerSnd = new FlxSound().loadEmbedded(Paths.sound('game/results/results_increase'), true);
		tickerSnd.volume = 1 * Options.volumeSFX;
		FlxG.sound.list.add(tickerSnd);
	}

	public function countJudgement()
	{
		var targetNumber:Int = 0;

		switch (judgementID)
		{
			case 0:
				targetNumber = psi.hits.get('sick');
			case 1:
				targetNumber = psi.hits.get('good');
			case 2:
				targetNumber = psi.hits.get('bad');
			case 3:
				targetNumber = psi.hits.get('shit');
			case 4:
				targetNumber = psi.misses;
		}

		var additonalScore = scoreBonus * targetNumber;
		judgementBonus.text = FlxStringUtil.formatMoney(FlxMath.roundDecimal(additonalScore, 0), false);
		if (additonalScore > 0)
			judgementBonus.text = '+${judgementBonus.text}';

		psi.songScore = FlxMath.bound(psi.songScore + additonalScore, 0, 9999999);

		if (targetNumber == 0)
			return;

		tickerSnd.play();

		bgFade.color = originalColor;
		judgementSprite.color = FlxColor.WHITE;
		judgementCount.color = FlxColor.WHITE;

		judgementBonus.scale.y = 0.0;
		judgementBonus.alpha = 0.0;
		judgementBonus.visible = true;

		FlxTween.tween(judgementCount, {'scale.x': 1.4, 'scale.y': 1.6}, 0.5, {ease: FlxEase.expoOut});

		FlxTween.num(0, targetNumber, 0.5, {
			ease: FlxEase.quadOut,
			onComplete: function()
			{
				bgFadeShine.visible = true;
				FlxTween.tween(bgFadeShine, {x: bgFadeShine.x - 300, alpha: 0.0}, 1.0, {ease: FlxEase.expoOut});

				FlxTween.tween(judgementCount, {'scale.x': 1.0, 'scale.y': 1.0}, 0.5, {ease: FlxEase.expoIn});

				FlxTween.tween(judgementBonus, {x: judgementBonus.x - 50, 'scale.y': 1.0, alpha: 1.0}, 0.75, {ease: FlxEase.expoOut});
				FlxTween.tween(judgementBonus, {x: judgementBonus.x - 150, 'scale.y': 1.0, alpha: 0.0}, 0.75, {ease: FlxEase.expoIn, startDelay: 1.0});

				FlxG.sound.play(Paths.sound('game/results/results_judgementdone'), 0.75 * Options.volumeSFX).pitch = 1.5 - (0.15 * judgementID);

				tickerSnd?.stop();
			}
		}, function(num:Float)
		{
			judgementCount.text = FlxMath.roundDecimal(num, 0);
		});

		FlxTween.num(1, 1.5, 0.5, {
			ease: FlxEase.quadIn
		}, function(num:Float)
		{
			tickerSnd.pitch = num;
		});
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
