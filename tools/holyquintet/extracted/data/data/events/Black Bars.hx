import openfl.display.BlendMode;

var camBlackBars:FlxCamera;
var topBar:FlxTween;
var btmBar:FlxTween;
var topCamBarTween:FlxTween;
var btmCamBarTween:FlxTween;

function postCreate()
{
	camBlackBars = new FlxCamera();
	FlxG.cameras.insert(camBlackBars, 1, false);
	camBlackBars.bgColor = 0x00000000;

	topBar = new FlxSprite(0, -540).makeGraphic(1, 1, FlxColor.BLACK);
	topBar.scale.set(FlxG.width * 2, FlxG.height * 1);
	add(topBar);
	topBar.cameras = [camBlackBars];

	btmBar = new FlxSprite(0, FlxG.height * 1.5).makeGraphic(1, 1, FlxColor.BLACK);
	btmBar.scale.set(FlxG.width * 2, FlxG.height * 1);
	add(btmBar);
	btmBar.cameras = [camBlackBars];
}

function onEvent(e)
{
	if (e.event.name == "Black Bars")
	{
		var params:Array = e.event.params;

		if (topCamBarTween != null)
			topCamBarTween.cancel();

		if (btmCamBarTween != null)
			btmCamBarTween.cancel();

		if (!params[1])
		{
			topBar.y = -540 + (540 * (params[0] / 100));
			btmBar.y = (FlxG.height * 1.5) - (540 * (params[0] / 100));
		}
		else
		{
			topCamBarTween = FlxTween.tween(topBar, {y: -540 + (540 * (params[0] / 100))}, (Conductor.stepCrochet * params[2]) / 1000, {
				ease: CoolUtil.flxeaseFromString(params[3], params[4]),
				onComplete: function(twn:FlxTween)
				{
					topCamBarTween = null;
				}
			});

			btmCamBarTween = FlxTween.tween(btmBar, {y: (FlxG.height * 1.5) - (540 * (params[0] / 100))}, (Conductor.stepCrochet * params[2]) / 1000, {
				ease: CoolUtil.flxeaseFromString(params[3], params[4]),
				onComplete: function(twn:FlxTween)
				{
					btmCamBarTween = null;
				}
			});
		}
	}
}
