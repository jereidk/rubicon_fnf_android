import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxTextAlign;
import flixel.text.FlxTextBorderStyle;
import util.GenUtil;

FlxG.sound.load(Paths.sound("meguca_kyubeydies"));
FlxG.sound.load(Paths.sound("meguca_gfdies"));
function create()
{
	megucaBG_Color = new FunkinSprite(0, 0);
	megucaBG_Color.loadSprite(Paths.image("stages/meguca/charbgs"));
	megucaBG_Color.scale.set(1.5, 1.5);
	megucaBG_Color.scrollFactor.set(1.0, 1.0);
	insert(members.indexOf(bf), megucaBG_Color);

	megucaBG_Overlay = new FunkinSprite(0, 0);
	megucaBG_Overlay.loadSprite(Paths.image("stages/meguca/posts"));
	megucaBG_Overlay.scale.set(1.5, 1.5);
	megucaBG_Overlay.scrollFactor.set(1.0, 1.0);
	add(megucaBG_Overlay);

	topPostText = new FlxText(1120, 15, 600, 'being Meguca is suffering...');
	topPostText.setFormat(Paths.font("arial.ttf"), 12, 0xFF202938, FlxTextAlign.LEFT);
	add(topPostText);
	topPostText.scale.set(3.0, 3.0);

	bottomPostText = new FlxText(-395, 538, 600, 'Meguca');
	bottomPostText.setFormat(Paths.font("arial.ttf"), 12, 0xFF202938, FlxTextAlign.RIGHT);
	add(bottomPostText);
	bottomPostText.scale.set(3.0, 3.0);

	bf.visible = false;
}

function postCreate()
{
	PauseSubState.script = 'data/states/HQPauseMeguca';

	topBar = new FunkinSprite(0, -540).makeGraphic(1, 1, FlxColor.BLACK);
	topBar.scale.set(FlxG.width * 2, FlxG.height * 1);
	add(topBar);
	topBar.zoomFactor = 0.0;
	topBar.cameras = [camUI];

	btmBar = new FunkinSprite(0, FlxG.width * 1.5).makeGraphic(1, 1, FlxColor.BLACK);
	btmBar.scale.set(FlxG.width * 2, FlxG.height * 1);
	add(btmBar);
	btmBar.zoomFactor = 0.0;
	btmBar.cameras = [camUI];

	if (Options.gameplayShaders)
	{
		ntscShader = new CustomShader("ntsc_1");
		FlxG.camera.addShader(ntscShader);
	}

	preloadedVid = GenUtil.createVideo("meguca", 0.1, true, 0, 0);
	add(preloadedVid);
	preloadedVid.play();
	preloadedVid.pause();
	preloadedVid.visible = false;
}

var totalElapsed:Float = 0.0;

function update(elapsed:Float)
{
	totalElapsed += elapsed;
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Stage Event")
	{
		switch (params[0])
		{
			case "Swap Char":
				bf.visible = true;
				strumLines.members[2].characters[0].visible = false;

			case "Update Text":
				topPostText.text = params[1];
				bottomPostText.text = params[2];

			case "Play Sound":
				FlxG.sound.play(Paths.sound("meguca_kyubeydies"));

			case "Random Border":
				topBar.y = FlxG.random.int(-300, -200);
				btmBar.y = FlxG.random.int(1350, 1450);

			case "Remove Border":
				topBar.visible = false;
				btmBar.visible = false;
		}
	}
}

function onPlayerHit(e)
{
	e.cancel();

	if (e == null)
		return;

	updateGFText();
}

function onPlayerMiss(e)
{
	e.cancel();

	if (e == null)
		return;

	updateGFText();
}

function soulGemUpdate()
{
	updateGFText();
}

function updateGFText()
{
	// TODO: make this a general function to calc fc rank
	var fcRank:String = 'N/A';
	if (totalAccuracyAmount == 0)
		fcRank = 'N/A';
	else
	{
		if (hits.get('sick') >= 1 && hits.get('good') == 0 && hits.get('bad') == 0 && hits.get('shit') == 0 && misses == 0)
			fcRank = 'MFC';
		else if (hits.get('good') >= 1 && hits.get('bad') == 0 && hits.get('shit') == 0 && misses == 0)
			fcRank = 'GFC';
		else if (hits.get('bad') >= 1 && hits.get('shit') == 0 && misses == 0)
			fcRank = 'FC';
		else if (hits.get('shit') >= 1 && misses == 0)
			fcRank = 'FC';
		else if (misses >= 1 && misses <= 9)
			fcRank = 'SDCB';
		else if (misses >= 10)
			fcRank = 'Clear';
	}

	new FlxTimer().start(0.0001, function(tmr:FlxTimer)
	{
		bottomPostText.text = 'i is Meguca too!\nPurity: ${FlxMath.roundDecimal(purity * 100, 0)}%\nScore: ${songScore}\nTarget Score: ${targetScore}\nMultiplier: ${GenUtil.padMultiplier(comboMulti)}\nBreaks: ${misses}\nAccuracy: ${FlxMath.roundDecimal(accuracy * 100, 2)}% [${curRating.rating}]\nFC Rank: ${fcRank}';
		bottomPostText.y = 636;
	});
}

function onGamePause(e)
{
}

function onSubstateClose(e)
{
	if (paused)
	{
	}
}
