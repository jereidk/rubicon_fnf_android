import flx3d.Flx3DView;
import openfl.geom.Vector3D;
import flixel.addons.display.FlxBackdrop;

var shopScene:Flx3DView;
var shopModel;

function create()
{
	scene3D = new Flx3DView(0, 0, FlxG.width, FlxG.height);
	scene3D.screenCenter();

	var shopModel;
	scene3D.addModel(Paths.obj("shop"), function(model)
	{
		if (Std.string(model.asset.assetType) == "mesh")
		{
			model.asset.scale(50);
			// model.asset.x = 0;
			model.asset.y = -100;
			model.asset.rotationY = 90;
			model.asset.z = -1000;
			shopModel = model.asset;
		}
	}, Paths.image("ui/shop/shoptex"), true);

	// scene3D.view.camera.x -= 50;
	// scene3D.view.camera.z += 975;
	// scene3D.view.camera.lookAt(new Vector3D(0, 0, 20));

	add(scene3D);

	kyubey = new FunkinSprite(-1500, 375).loadGraphic(Paths.image('ui/shop/nkyubey'));
	add(kyubey);
	kyubey.origin.y = kyubey.height;

	var transitionSpeed:Float = 1.75;

	FlxTween.num(75, 90, transitionSpeed, {ease: FlxEase.quadOut}, function(num:Float)
	{
		shopModel.rotationY = num;
	});

	FlxTween.num(300, -50, transitionSpeed, {ease: FlxEase.quadOut}, function(num:Float)
	{
		scene3D.view.camera.x = num;
	});

	FlxTween.tween(kyubey, {x: 0}, transitionSpeed, {ease: FlxEase.quadOut});

	FlxTween.tween(kyubey, {y: kyubey.y + 5, 'scale.x': 1.01, 'scale.y': 0.99}, 1.6, {ease: FlxEase.quadInOut, type: FlxTween.PINGPONG});

	bg_TopBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_TopBanner);
	bg_TopBanner.velocity.set(5, 0);

	bg_BtmBanner = new FlxBackdrop(Paths.image('ui/common/border'), FlxAxes.X, 0, 0);
	add(bg_BtmBanner);
	bg_BtmBanner.flipY = true;
	bg_BtmBanner.velocity.set(-5, 0);
	bg_BtmBanner.y = FlxG.height - bg_BtmBanner.height;
}

function update(elapsed:Float)
{
	if (controls.BACK)
		FlxG.switchState(new ModState("HQMainMenu"));
}

override function destory()
{
	scene3D.destroy();
	trace('oh sht!');
}
