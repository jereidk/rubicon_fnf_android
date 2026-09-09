import util.GenUtil;
import funkin.game.PlayState.ComboRating;

public var disablePlayerInput:Bool = true;

// Health
public var purity:Float = 1.0;
public var alreadyDied:Bool = false;

// Score
public var targetScore:Int = 0;
public var underTargetScoreLength:Float = 0.0;
public var useTargetScoreMech:Bool = true;
public var playerHitFirstNote:Bool = false;
public var pauseTargetScoreMech:Bool = false;

// Combo
public var comboMulti:Float = 1.0;
var baseComboMulti:Float = 1.0;
var noteStreakMutliAdd(default, set):Float = 0.0;

function create()
{
	baseComboMulti = 1.0;

	canDie = false;

	comboRatings = [
		new ComboRating(0, "F", 0xFFFF4444),
		new ComboRating(0.5, "E", 0xFFFF4444),
		new ComboRating(0.6, "D", 0xFFFF8844),
		new ComboRating(0.7, "C", 0xFFFFAA44),
		new ComboRating(0.8, "B", 0xFFFFFF44),
		new ComboRating(0.9, "A", 0xFFAAFF44),
		new ComboRating(0.95, "S", 0xFF88FF44),
		new ComboRating(0.99, "SS", 0xFF44FFFF),
		new ComboRating(0.9999, "SSS", 0xFF44FFFF),
	];
}

function onInputUpdate(e)
{
	if (e == null)
		return;

	if (disablePlayerInput)
	{
		e.cancel();
		if (e.strumLine == playerStrums)
			e.cancel();
	}
}

function onPlayerHit(e)
{
	e.cancel();

	if (e == null)
		return;

	playerHitFirstNote = true;

	var rewardHit:Bool = true;
	if (e.note.noteType == 'Timestop Note')
		rewardHit = false;

	var punishForBadHit:Bool = true;
	if (e.note.noteType == 'Bullet Note')
		punishForBadHit = false;

	// Health Changes
	if (rewardHit)
	{
		if (e.note.isSustainNote)
		{
			healthChange(0.005);
			songScore = FlxMath.bound(songScore + (5 * comboMulti), 0, 9999999);
		}
		else
		{
			switch (e.rating)
			{
				case 'sick':
					healthChange(0.05);
					songScore = FlxMath.bound(songScore + (100 * comboMulti), 0, 9999999);
				case 'good':
					healthChange(0.02);
					songScore = FlxMath.bound(songScore + (50 * comboMulti), 0, 9999999);
				case 'bad':
					if (punishForBadHit)
						healthChange(-0.025);
					songScore = FlxMath.bound(songScore + (25 * comboMulti), 0, 9999999);
				case 'shit':
					if (punishForBadHit)
						healthChange(-0.1);
					songScore = FlxMath.bound(songScore + (10 * comboMulti), 0, 9999999);
			}
		}

		if (!e.note.isSustainNote)
			PlayState.instance.hits[e.rating] += 1;

		if (useTargetScoreMech && playerHitFirstNote)
		{
			var increaseAmt:Int = 50;

			if (curMods.contains('ComboCountRequirement'))
				increaseAmt = 95;

			if (!e.note.isSustainNote)
				targetScore += Std.int(increaseAmt * comboMulti);
			else
				targetScore += Std.int(1 * comboMulti);
		}
	}

	// Accuracy Changes
	if (rewardHit)
	{
		switch (e.rating)
		{
			case 'sick':
				e.accuracy = 1.0;
			case 'good':
				e.accuracy = 0.75;
			case 'bad':
				e.accuracy = 0.05;
			case 'shit':
				e.accuracy = 0.0;
		}

		if (!e.note.isSustainNote)
		{
			accuracyPressedNotes += ((e.note.tailCount * 0.10) + 1);
			totalAccuracyAmount += e.accuracy;
		}
		else
			totalAccuracyAmount += 0.10;
	}

	updateRating();

	// Combo Changes
	if (rewardHit)
	{
		if (!e.note.isSustainNote)
			combo += 1;
	}
	else
	{
		if (!e.note.isSustainNote)
			combo = 0;
		misses += 1;
	}

	if (rewardHit && !e.note.isSustainNote)
		judgementDisplay.updateJudgement(e.rating, e);
	else if (!rewardHit && !e.note.isSustainNote)
		judgementDisplay.updateJudgement('break', e);

	updateScoreText();
}

function onPlayerMiss(e)
{
	e.cancel();

	if (e == null)
		return;

	var allowMiss:Bool = false;
	if (e.note.noteType == 'Timestop Note')
		allowMiss = true;

	if (e.note.isSustainNote)
		allowMiss = true;

	if (!allowMiss)
	{
		// Health Changes

		var baseHealthChange = -0.075;

		healthChange(baseHealthChange);

		// Score Changes
		songScore = FlxMath.bound(songScore - 300, 0, 9999999);

		// Accuracy Changes
		accuracyPressedNotes += 1;
		totalAccuracyAmount += e.accuracy;
		misses += 1;

		updateRating();

		// FlxG.sound.play(Paths.sound('missnote' + FlxG.random.int(1, 3)), 0.75).pitch = FlxG.random.float(0.95, 1.05);

		// Combo Changes
		if (!allowMiss && combo != 0)
			judgementDisplay.updateJudgement('break', e);
		combo = 0;
		noteStreakMutliAdd = 0.0;
		multiAnimation('hide');
	}

	playerHitFirstNote = true;

	updateScoreText();
}

function postUpdate(elapsed:Float)
{
	comboMulti = baseComboMulti + noteStreakMutliAdd;

	// Score Requirement Check
	if (useTargetScoreMech && playerHitFirstNote && !pauseTargetScoreMech)
	{
		if (songScore < targetScore)
		{
			aboveTargetScore = false;
			underTargetScoreLength += elapsed;
			if (songScore < targetScore)
				healthChange(-((underTargetScoreLength / 200) * elapsed));
		}
		else
		{
			aboveTargetScore = true;
			underTargetScoreLength = 0.0;
		}
	}
}

function onNoteHit(e)
{
	e.cancel();

	if (e == null)
		return;

	// Cheap broken botplay script, reminder to remove this when this releases
	if (playerStrums != null)
	{
		if (playerStrums.cpu && !e.player && e.characters[0].curCharacter == 'gf-base')
		{
			e.accuracy = 1;
			e.rating = 'sick';
			onPlayerHit(e);
		}
	}
}

function onNoteCreation(e)
{
	e.note.earlyPressWindow = 1.0;
	e.note.latePressWindow = 1.0;
}

public function healthChange(amount:Float)
{
	if (amount >= 0)
	{
		amount *= 1 - (0.25 * reducedRecovery_Stack);
	}

	var healthDebt:Float = health + amount;

	if (healthDebt < 0)
	{
		purity = FlxMath.bound(purity + (healthDebt / 2), 0, 1);
		scripts.call('soulGemUpdate');

		if (purity <= 0 && !alreadyDied)
		{
			canDie = true;
			health = 0;
		}
	}

	health = healthDebt;
}

public function killPlayer()
{
	canDie = true;
	health = 0.0;
	purity = 0.0;
}

function set_noteStreakMutliAdd(newMulti:Float):Float
{
	if (PlayState.SONG.meta.customValues.uiStyle != 'MegucaUI')
	{
		switch (newMulti)
		{
			case 0.0:
				noteStreakMutliAdd_mainSprite.playAnim('0', true);
			case 0.25:
				noteStreakMutliAdd_mainSprite.playAnim('1', true);
			case 0.5:
				noteStreakMutliAdd_mainSprite.playAnim('2', true);
			case 0.75:
				noteStreakMutliAdd_mainSprite.playAnim('3', true);
			case 1.0:
				noteStreakMutliAdd_mainSprite.playAnim('4', true);
		}
	}

	return (noteStreakMutliAdd = newMulti);
}
