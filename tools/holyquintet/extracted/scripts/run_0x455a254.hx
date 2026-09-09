import util.GenUtil;

public static var queuedAchievements:Array<String> = [];
var hasPaused:Bool = false;
var resOutHeal_reachedpercent:Bool = false;

function update(elapsed:Float)
{
	if (health <= 0.6)
		resOutHeal_reachedpercent = true;
}

function onSongEnd()
{
	queuedAchievements = [];

	// UNLOCK: ACHIEVEMENT - FCs
	if (misses == 0 && PlayState.difficulty == 'hard' && !PlayState.isGauntletMode && !godukaEnabled)
	{
		switch (SONG.meta.name)
		{
			case 'initium':
				tryPush('FCInitium');
			case 'resonance':
				if (Options.mechanics)
					tryPush('FCResonance');
			case 'partea':
				tryPush('FCPartea');
			case 'eternalstar':
				tryPush('FCEternalStar');
			case 'vexation':
				if (Options.mechanics)
					tryPush('FCVexation');
			case 'out-of-time':
				if (Options.mechanics)
					tryPush('FCOutOfTime');
			case 'meguca':
				tryPush('FCMeguca');
			case 'reconnect':
				tryPush('FCReconnect');
			case 'stardom':
				tryPush('FCStardom');
		}
	}

	// UNLOCK: ACHIEVEMENT - Hope
	if (SONG.meta.name == 'out-of-time' && PlayState.isStoryMode && !PlayState.isGauntletMode)
		tryPush('CompleteAct1');

	// UNLOCK: ACHIEVEMENT - Outhealed the Healer
	if (!resOutHeal_reachedpercent && SONG.meta.name == 'resonance' && Options.mechanics)
		tryPush('ResOutheal');

	// UNLOCK: ACHIEVEMENT - Yikes!
	if (atksSustained == 0 && SONG.meta.name == 'vexation' && Options.mechanics)
		tryPush('VexYikes');

	// UNLOCK: ACHIEVEMENT - You're on my Time
	if (SONG.meta.name == 'out-of-time' && Options.mechanics)
	{
		if (!timeStopNoteHit && !bulletNoteMissed)
			tryPush('YoureOnMyTime');
	}

	// UNLOCK: ACHIEVEMENT - Time waits for ME!
	if (SONG.meta.name == 'out-of-time' && hasPaused)
	{
		tryPush('TimeWaitsForMe');
	}

	// UNLOCK: ACHIEVEMENT - Tenacious
	if (PlayState.deathCounter >= 15)
	{
		tryPush('Tenacious');
	}

	// UNLOCK: ACHIEVEMENT - Pinpoint Accuracy
	FlxG.save.data.pinpointAccuracyProgress += PlayState.instance.hits.get('sick');
	if (FlxG.save.data.pinpointAccuracyProgress >= 5000)
	{
		tryPush('PinpointAccuracy');
	}

	// UNLOCK: ACHIEVEMENT - Devoted
	FlxG.save.data.devotedProgress += 1;
	if (FlxG.save.data.devotedProgress >= 25)
	{
		tryPush('Devoted');
	}
}

function tryPush(achievement:String)
{
	if (GenUtil.isAchievementLocked(achievement))
	{
		queuedAchievements.push(achievement);
		GenUtil.achievementUnlock(achievement);
	}
}

function onGamePause(e)
{
	hasPaused = true;
}
