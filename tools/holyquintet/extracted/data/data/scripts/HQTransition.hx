public static var instant:Bool = false;

function postCreate(e)
{
	blackSpr.y = 0;
	blackSpr.scrollFactor.set(0, 0);
	allowSkip = false;
	transitionCamera.flipY = false;
	transitionTween.cancel();

	kyubey_spr = new FunkinSprite().loadSprite(Paths.image("ui/common/KYUBEYRUN"));
	kyubey_spr.addAnim('run', 'kyubey run instance 1', 24, true, true);
	kyubey_spr.setPosition((FlxG.width - (kyubey_spr.width / 2)) * 0.90, (FlxG.height - (kyubey_spr.height / 2)) * 0.90);
	kyubey_spr.scrollFactor.set(0.0, 0.0);
	add(kyubey_spr);
	kyubey_spr.playAnim('run');

	if (e.transOut)
	{
		blackSpr.alpha = 0.0;
		kyubey_spr.x -= 100;
		kyubey_spr.alpha = 0.0;

		FlxTween.tween(blackSpr, {alpha: 1.0}, 0.25, {ease: FlxEase.sineIn});
		FlxTween.tween(kyubey_spr, {x: kyubey_spr.x + 100, alpha: 1.0}, 0.5, {ease: FlxEase.sineOut});
	}
	else
	{
		blackSpr.alpha = 1.0;
		kyubey_spr.alpha = 1.0;

		FlxTween.tween(blackSpr, {alpha: 0.0}, 0.25, {ease: FlxEase.sineIn});
		FlxTween.tween(kyubey_spr, {x: kyubey_spr.x + 250, alpha: 0.0}, 0.5, {ease: FlxEase.sineIn});
	}

	if (instant)
		finish();

	new FlxTimer().start(0.75, function(tmr:FlxTimer)
	{
		finish();
	});
}

function onFinish(e)
{
	e.cancel();

	if (newState != null)
		FlxG.switchState(newState);
	close();
}
