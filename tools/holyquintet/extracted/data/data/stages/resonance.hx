import hxvlc.flixel.FlxVideoSprite;
import openfl.display.BlendMode;

public var kyubey:Character;
public var kyubeySpeaker:Character;

function create()
{
	startUIvisablityArgs = [true, true, true, true, true, 0, false, 4, "linear", "In"];

	// BG Sprites
	if (!Options.lowMemoryMode)
	{
		resBG_Video = new FlxVideoSprite(0, 0);
		resBG_Video.antialiasing = true;
		resBG_Video.bitmap.onFormatSetup.add(function():Void
		{
			if (resBG_Video.bitmap != null && resBG_Video.bitmap.bitmapData != null)
			{
				final scale:Float = Math.min((FlxG.width / resBG_Video.bitmap.bitmapData.width) * 1.75,
					(FlxG.height / resBG_Video.bitmap.bitmapData.height) * 1.75);

				resBG_Video.setGraphicSize(resBG_Video.bitmap.bitmapData.width * scale, resBG_Video.bitmap.bitmapData.height * scale);
				resBG_Video.updateHitbox();
				resBG_Video.screenCenter();
				resBG_Video.x -= 350;
				resBG_Video.y -= 1100;
			}
		});
		resBG_Video.bitmap.onEndReached.add(resBG_Video.destroy);
		insert(members.indexOf(bf), resBG_Video);
		if (resBG_Video.load(Paths.video("resbg"), ['input-repeat=99999']))
			new FlxTimer().start(0.001, (_) -> resBG_Video.play());
	}
	else
	{
		resBG_simpleBG = new FunkinSprite(-500, -1200);
		resBG_simpleBG.loadSprite(Paths.image("stages/resonance/simpleBG"));
		resBG_simpleBG.scale.set(1.5, 1.5);
		resBG_simpleBG.scrollFactor.set(1.0, 1.0);
		insert(members.indexOf(bf), resBG_simpleBG);
	}

	resBG_Ground = new FunkinSprite(0, -480);
	resBG_Ground.loadSprite(Paths.image("stages/resonance/background_bg"));
	resBG_Ground.scale.set(2.25, 2.25);
	resBG_Ground.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), resBG_Ground);

	resBG_Madoka = new FunkinSprite(790, -470);
	resBG_Madoka.loadSprite(Paths.image("stages/resonance/madokabg"));
	resBG_Madoka.addAnim('bop', 'madoka resvibe', 24, false, false);
	resBG_Madoka.scale.set(0.9, 0.9);
	resBG_Madoka.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), resBG_Madoka);
	resBG_Madoka.playAnim('bop', true);

	resBG_Mami = new FunkinSprite(-780, -480);
	resBG_Mami.loadSprite(Paths.image("stages/resonance/mamibg"));
	resBG_Mami.addAnim('bop', 'mami resvibe', 24, false, false);
	resBG_Mami.scale.set(0.8, 0.8);
	resBG_Mami.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), resBG_Mami);
	resBG_Mami.playAnim('bop', true);

	kyubeySpeaker = new FunkinSprite(300, -250);
	kyubeySpeaker.loadSprite(Paths.image("game/speakersmain"));
	kyubeySpeaker.addAnim('bop', 'speaker dancing beat0', 24, false, false);
	kyubeySpeaker.scale.set(0.9, 0.9);
	kyubeySpeaker.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), kyubeySpeaker);
	kyubeySpeaker.playAnim('bop');

	kyubey = new Character(375, -780, 'kyubey-big-bald', false);
	kyubey.scale.set(0.9, 0.9);
	kyubey.scrollFactor.set(1.0, 1.0);
	add(kyubey);

	resBG_resBG_fog = new FunkinSprite(-200, 100);
	resBG_resBG_fog.loadSprite(Paths.image("stages/resonance/middleground_fog"));
	resBG_resBG_fog.scale.set(1.75, 1.75);
	resBG_resBG_fog.scrollFactor.set(1.1, 1.1);
	add(resBG_resBG_fog);
	resBG_resBG_fog.alpha = 0.5;

	resBG_flowerL = new FunkinSprite(-900, -250);
	resBG_flowerL.loadSprite(Paths.image("stages/resonance/foreground_flowerL"));
	resBG_flowerL.scale.set(1.25, 1.25);
	resBG_flowerL.scrollFactor.set(1.2, 1.2);
	add(resBG_flowerL);

	resBG_flowerR = new FunkinSprite(1250, -100);
	resBG_flowerR.loadSprite(Paths.image("stages/resonance/foreground_flowerR"));
	resBG_flowerR.scale.set(1.25, 1.25);
	resBG_flowerR.scrollFactor.set(1.2, 1.2);
	add(resBG_flowerR);
}

function postCreate()
{
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;
}

function beatHit(curBeat:Int)
{
	if ((curBeat % 2) == 0)
	{
		resBG_Madoka.playAnim('bop', true);
		resBG_Mami.playAnim('bop', true);
		kyubeySpeaker.playAnim('bop', true);
	}
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			default:
		}
	}
}

function onGamePause(e)
{
	if (!Options.lowMemoryMode)
	{
		resBG_Video.pause();
	}
}

function onSubstateClose(e)
{
	if (paused)
	{
		if (!Options.lowMemoryMode)
		{
			resBG_Video.resume();
		}
	}
}
