import funkin.editors.ui.UIState;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextBorderStyle;
import funkin.backend.system.Control;
import BlurFilter;
import ui.ButtonUI;
import ui.EntryFieldUI;
import gamejolt.GameJolt;
import gamejolt.GJRequest;
import gamejolt.types.RequestType;
import sys.io.File;
import sys.net.Http;
import ui.GameJoltNoticeUI;
import openfl.display.Sprite;
import flixel.text.FlxText.FlxTextFormat;
import flixel.text.FlxText.FlxTextFormatMarkerPair;

class GameJoltSignInUI extends FlxBasic
{
	public var group:FlxSpriteGroup;

	var blur:BlurFilter;

	var canControl:Bool = true;

	var scrollTween:FlxTween;

	var mouse:Mouse;

	var sprites:Array<FunkinSprite> = [];

	public function new(theData:Dynamic)
	{
		super();

		data = theData;

		signInCam = new FlxCamera();
		signInCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(signInCam, false);
		signInCam.scroll.y -= 15;
		scrollTween = FlxTween.num(-15, 0, 0.5, {ease: FlxEase.expoOut}, function(num:Float)
		{
			signInCam.scroll.y = num;
		});

		group = new FlxSpriteGroup();

		if (Options.gameplayShaders)
		{
			blur = new BlurFilter(0.0);
			blur.apply(FlxG.camera);
			FlxTween.num(0.0, 15, 0.50, {ease: FlxEase.expoOut}, function(num:Float)
			{
				blur.set(num);
			});
		}

		bg = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width * 2, FlxG.height * 2);
		group.add(bg);
		bg.alpha = 0.0;
		FlxTween.tween(bg, {alpha: 0.75}, 0.50, {ease: FlxEase.expoOut});

		blackBanner = new FlxSprite(1220, 500).makeGraphic(640, 1, FlxColor.BLACK);
		blackBanner.scale.set(1.0, FlxG.height * 1.1);
		group.add(blackBanner).cameras = [signInCam];
		blackBanner.alpha = 0.0;
		FlxTween.tween(blackBanner, {alpha: 0.75}, 0.50, {ease: FlxEase.expoOut});

		signInText = new FlxText(blackBanner.x, 200, blackBanner.width, i18n.tr('GameJolt/SignIn/Header'));
		signInText.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		signInText.borderSize = 2.5;
		group.add(signInText).cameras = [signInCam];
		signInText.alpha = 0.0;
		FlxTween.tween(signInText, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});

		usernameText = new FlxText(blackBanner.x, 280, blackBanner.width, i18n.tr('GameJolt/SignIn/Username'));
		usernameText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		usernameText.borderSize = 2.5;
		group.add(usernameText).cameras = [signInCam];
		usernameText.alpha = 0.0;
		FlxTween.tween(usernameText, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});

		entryFieldUsername = new EntryFieldUI(blackBanner.x + 44, usernameText.y + 40);
		group.add(entryFieldUsername.group).cameras = [signInCam];
		entryFieldUsername.group.alpha = 0.0;
		FlxTween.tween(entryFieldUsername.group, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});

		tokenText = new FlxText(blackBanner.x, 480, blackBanner.width, i18n.tr('GameJolt/SignIn/Token'));
		tokenText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		tokenText.borderSize = 2.5;
		group.add(tokenText).cameras = [signInCam];
		tokenText.alpha = 0.0;
		FlxTween.tween(tokenText, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});

		entryFieldToken = new EntryFieldUI(blackBanner.x + 44, tokenText.y + 40);
		group.add(entryFieldToken.group).cameras = [signInCam];
		entryFieldToken.group.alpha = 0.0;
		FlxTween.tween(entryFieldToken.group, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});
		entryFieldToken.stringVisible = false;

		passwordWarningText = new FlxText(blackBanner.x, 640, blackBanner.width, i18n.tr('GameJolt/SignIn/PasswordNotice'));
		passwordWarningText.setFormat(Paths.font("shingo.otf"), 32, FlxColor.RED, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		passwordWarningText.borderSize = 2.5;
		group.add(passwordWarningText).cameras = [signInCam];
		passwordWarningText.alpha = 0.0;
		FlxTween.tween(passwordWarningText, {alpha: 1.0}, 0.50, {ease: FlxEase.expoOut});

		gamejoltAnimation = new FunkinSprite(25, 100).loadSprite(Paths.image("ui/gamejolt"));
		gamejoltAnimation.addAnim('start', 'GamejoltAnimation', 60, false, false, [
			0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
			39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
		]);
		gamejoltAnimation.scale.set(1.0, 1.0);
		group.add(gamejoltAnimation).cameras = [signInCam];
		gamejoltAnimation.playAnim('start');

		gjAnimText1 = new FlxText(115, 800, 0, i18n.tr('GameJolt/SignIn/Info1'));
		gjAnimText1.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		gjAnimText1.borderSize = 2.5;
		group.add(gjAnimText1).cameras = [signInCam];

		gjAnimText1.x -= 25;
		gjAnimText1.alpha = 0.0;
		FlxTween.tween(gjAnimText1, {x: gjAnimText1.x + 25, alpha: 1.0}, 0.50, {ease: FlxEase.backOut});

		gjAnimText2 = new FlxText(550, 800, 0, i18n.tr('GameJolt/SignIn/Info2'));
		gjAnimText2.setFormat(Paths.font("shingo.otf"), 42, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, 0xFF0D090D);
		gjAnimText2.borderSize = 2.5;
		group.add(gjAnimText2).cameras = [signInCam];

		gjAnimText2.x -= 25;
		gjAnimText2.alpha = 0.0;
		FlxTween.tween(gjAnimText2, {x: gjAnimText2.x + 25, alpha: 1.0}, 0.50, {ease: FlxEase.backOut, startDelay: 0.5});

		logInButton = new ButtonUI(blackBanner.x + 95, blackBanner.y + 250, 'gj');
		logInButton.text = i18n.tr('GameJolt/SignIn/Login');
		group.add(logInButton.group).cameras = [signInCam];

		gjAnimText1.applyMarkup(gjAnimText1.text, [
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFCBFF00), "*"),
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFF72AEDA), "#")
		]);

		gjAnimText2.applyMarkup(gjAnimText2.text, [
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFFFFF00), "*"),
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFF00FFFF), "#")
		]);

		GenUtil.playUISound('open');

		mouseSpr = new FunkinSprite(FlxG.mouse.x, FlxG.mouse.y).loadGraphic(Paths.image('ui/common/cursor/normal'));
		group.add(mouseSpr).cameras = [signInCam];

		FlxG.sound.play(Paths.sound("ui/ui_gj"));

		FlxG.mouse.visible = false;
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
		mouseSpr.setPosition(FlxG.mouse.x, FlxG.mouse.y);

		if (CoolUtil.mouseOverlaps(entryFieldUsername.group, signInCam) && entryFieldUsername != null)
			mouseSpr.loadGraphic(Paths.image('ui/common/cursor/hover'));

		if (CoolUtil.mouseOverlaps(entryFieldToken.group, signInCam))
			mouseSpr.loadGraphic(Paths.image('ui/common/cursor/hover'));

		if (!CoolUtil.mouseOverlaps(entryFieldUsername.group, signInCam)
			&& !CoolUtil.mouseOverlaps(entryFieldToken.group, signInCam)
			&& !CoolUtil.mouseOverlaps(logInButton.group, signInCam))
		{
			mouseSpr.loadGraphic(Paths.image('ui/common/cursor/normal'));
		}

		super.update(elapsed);
		group.update();

		entryFieldUsername.update(elapsed);
		entryFieldToken.update(elapsed);
		gamejoltAnimation.update(elapsed);

		if (canControl)
		{
			if (FlxG.mouse.justPressed && CoolUtil.mouseOverlaps(entryFieldUsername.group, signInCam))
			{
				entryFieldUsername.selected = true;
			}
			else if (FlxG.mouse.justPressed && !CoolUtil.mouseOverlaps(entryFieldUsername.group, signInCam))
				entryFieldUsername.selected = false;

			if (FlxG.mouse.justPressed && CoolUtil.mouseOverlaps(entryFieldToken.group, signInCam))
			{
				entryFieldToken.selected = true;
			}
			else if (FlxG.mouse.justPressed && !CoolUtil.mouseOverlaps(entryFieldToken.group, signInCam))
				entryFieldToken.selected = false;

			if (CoolUtil.mouseOverlaps(logInButton.group, signInCam) && !logInButton.selected)
			{
				logInButton.selected = true;
				GenUtil.playUISound('move');

				mouseSpr.loadGraphic(Paths.image('ui/common/cursor/hover'));
			}
			else if (!CoolUtil.mouseOverlaps(logInButton.group, signInCam))
			{
				logInButton.selected = false;
			}

			if (FlxG.mouse.justPressed && logInButton.selected)
			{
				canControl = false;
				entryFieldUsername.selected = false;
				entryFieldToken.selected = false;
				requestSignIn();
				GenUtil.toggleVolControl(false);
			}

			if (FlxG.keys.justPressed.ESCAPE)
			{
				data.backAction();
			}
		}

		if (entryFieldUsername.selected || entryFieldToken.selected)
			GenUtil.toggleVolControl(false);
		else
			GenUtil.toggleVolControl(true);

		if (FlxG.mouse.justPressed)
		{
			var clickFx:FunkinSprite = new FunkinSprite(FlxG.mouse.screenX, FlxG.mouse.screenY).loadGraphic(Paths.image('ui/common/cursor/click'));
			clickFx.blend = BlendMode.ADD;
			clickFx.scale.set(0.5, 0.5);
			clickFx.alpha = 1.0;
			clickFx.updateHitbox();
			clickFx.scrollFactor.set(0.0, 0.0);
			clickFx.setPosition(FlxG.mouse.getPositionInCameraView(signInCam).x - clickFx.width / 2,
				FlxG.mouse.getPositionInCameraView(signInCam).y - clickFx.height / 2);
			group.insert(group.members.indexOf(mouseSpr), clickFx).cameras = [signInCam];

			sprites.push(clickFx);

			var scale:Float = FlxG.random.float(0.75, 1.5);

			FlxTween.tween(clickFx, {
				alpha: 0.0,
				angle: FlxG.random.int(-365, 365),
				'scale.x': scale,
				'scale.y': scale
			}, FlxG.random.float(1.0, 1.5), {
				ease: FlxEase.expoOut,
				onComplete: function(twn:FlxTween) clickFx.destroy()
			});
		}
	}

	function requestSignIn()
	{
		GameJolt.userName = entryFieldUsername.entryString.text;
		GameJolt.userToken = entryFieldToken.entryString.text;
		FlxG.save.data.curUserName = GameJolt.userName;
		FlxG.save.data.curUserToken = GameJolt.userToken;

		var signInRequest:GJRequest = new GJRequest(RequestType.USER_AUTH);
		signInRequest.onComplete.add(function(res)
		{
			if (res.success == 'true')
			{
				data.acceptAction();
				canControl = true;
			}
		});
		signInRequest.onError.add(e ->
		{
			GenUtil.playUISound('error');
			canControl = true;
		});
		signInRequest.send(false);
	}

	override function draw()
	{
		super.draw();
		group.draw();
	}

	override function destroy()
	{
		group.destroy();

		scrollTween.cancel();

		for (spr in sprites)
		{
			FlxTween.cancelTweensOf(spr);
		}

		FlxTween.cancelTweensOf(signInCam);
		if (Options.gameplayShaders)
			blur.remove(FlxG.camera);
		FlxG.cameras.remove(signInCam);

		FlxG.mouse.visible = true;

		super.destroy();
	}
}
