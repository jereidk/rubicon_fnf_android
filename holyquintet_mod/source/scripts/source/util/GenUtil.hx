import sys.io.Process;
import openfl.display.BlendMode;
import hxvlc.flixel.FlxVideoSprite;
import gamejolt.GameJolt;
import gamejolt.GJRequest;
import gamejolt.types.RequestType;

class GenUtil
{
	public static function playUISound(type:String)
	{
		switch (type)
		{
			case 'move':
				FlxG.sound.play(Paths.sound('ui/ui_move' + FlxG.random.int(1, 3)), 1.0 * Options.volumeSFX).persist = true;
			case 'confirm':
				FlxG.sound.play(Paths.sound('ui/ui_confirm' + FlxG.random.int(1, 3)), 1.0 * Options.volumeSFX).persist = true;
			case 'confirmbad':
				FlxG.sound.play(Paths.sound('ui/ui_confirm_bad', 1.0 * Options.volumeSFX)).persist = true;
			case 'error':
				FlxG.sound.play(Paths.sound('ui/ui_error'), 1.0 * Options.volumeSFX).persist = true;
			case 'back':
				FlxG.sound.play(Paths.sound('ui/ui_back' + FlxG.random.int(1, 2)), 1.0 * Options.volumeSFX).persist = true;
			case 'open':
				FlxG.sound.play(Paths.sound('ui/ui_open' + FlxG.random.int(1, 2)), 1.0 * Options.volumeSFX).persist = true;
			case 'close':
				FlxG.sound.play(Paths.sound('ui/ui_close' + FlxG.random.int(1, 2)), 1.0 * Options.volumeSFX).persist = true;
			case 'on':
				FlxG.sound.play(Paths.sound('ui/ui_tick_true'), 1.0 * Options.volumeSFX).persist = true;
			case 'off':
				FlxG.sound.play(Paths.sound('ui/ui_tick_false'), 1.0 * Options.volumeSFX).persist = true;
		}
	}

	public static function alignToCenter(t1:FlxSprite, t2:FlxSprite)
	{
		t1.x = t2.x + (t2.width - t1.width) * 0.5;
		t1.y = t2.y + (t2.height - t1.height) * 0.5;
	}

	public static function glowPulse(sprite:Dynamic, startingAlpha:Float, size:Float, time:Float):FunkinSprite
	{
		var glowSprite:FunkinSprite = FunkinSprite.copyFrom(sprite);
		glowSprite.alpha = startingAlpha;
		glowSprite.blend = BlendMode.ADD;
		FlxTween.tween(glowSprite, {'scale.x': glowSprite.scale.x + size, 'scale.y': glowSprite.scale.y + size, alpha: 0.0}, time, {
			ease: FlxEase.sineOut,
			onComplete: function(twn:FlxTween)
			{
				glowSprite.destroy();
			}
		});

		return glowSprite;
	}

	public static function createVideo(videoName:String, videoSize:Float, loop:Bool, ?x:Float, ?y:Float):FlxVideoSprite
	{
		var videoSizeScale:Float = videoSize;
		var video:FlxVideoSprite = new FlxVideoSprite(0, 0);
		video.antialiasing = true;
		video.bitmap.onFormatSetup.add(function():Void
		{
			if (video.bitmap != null && video.bitmap.bitmapData != null)
			{
				final scale:Float = Math.min((FlxG.width / video.bitmap.bitmapData.width) * videoSizeScale,
					(FlxG.height / video.bitmap.bitmapData.height) * videoSizeScale);

				video.setGraphicSize(video.bitmap.bitmapData.width * scale, video.bitmap.bitmapData.height * scale);

				video.screenCenter();
			}
		});
		if (!loop)
			video.load(Paths.video(videoName));
		else
			video.load(Paths.video(videoName), ['input-repeat=99999']);
		video.visible = false;
		video.play();
		video.pause();
		video.bitmap.time = 0;
		return video;
	}

	public static function toggleVolControl(enabled:Bool)
	{
		if (enabled)
		{
			FlxG.sound.volumeUpKeys = Options.SOLO_VOLUME_UP;
			FlxG.sound.volumeDownKeys = Options.SOLO_VOLUME_DOWN;
			FlxG.sound.muteKeys = Options.SOLO_VOLUME_MUTE;
		}
		else
		{
			FlxG.sound.volumeUpKeys = null;
			FlxG.sound.volumeDownKeys = null;
			FlxG.sound.muteKeys = null;
		}
	}

	public static function isAchievementLocked(achievement:String):Bool
	{
		var locked:Bool = !StringTools.contains(FlxG.save.data.unlockedAchievements, achievement);

		return locked;
	}

	public static function achievementUnlock(achievement:String)
	{
		if (isAchievementLocked(achievement))
		{
			FlxG.save.data.unlockedAchievements.push(achievement);
			FlxG.save.flush();

			promptAchievementPopUp(achievement);
		}

		if (signedIntoGJ && !onOutdatedBuild && !lockGJprogression)
		{
			var id = achievementData.get(achievement);
			var grantAchievementRequest:GJRequest = new GJRequest(RequestType.TROPHIES_ADD(id.gjid));
			grantAchievementRequest.onComplete.add(function(res)
			{
				trace('Completed ' + res);
			});
			grantAchievementRequest.onError.add(e ->
			{
				trace('Error ' + e);
			});
			grantAchievementRequest.send(false);
		}
	}

	public static function achievementBatchUnlock(achievements:Array<String>)
	{
		var achievementsToUnlock:String = [];
		var achievementsRequests:Array<Dynamic> = [];

		for (i in 0...achievements.length)
		{
			if (isAchievementLocked(achievements[i]))
			{
				FlxG.save.data.unlockedAchievements.push(achievement);
				FlxG.save.flush();
			}

			var id = achievementData.get(achievements[i]);

			achievementsRequests.push(RequestType.TROPHIES_ADD(id.gjid));
		}

		if (signedIntoGJ && !onOutdatedBuild && !lockGJprogression)
		{
			var grabScores:GJRequest = new GJRequest(RequestType.BATCH(false, false, achievementsRequests));
			grabScores.onComplete.add(function(res)
			{
			});
			grabScores.onError.add(function(e)
			{
			});
			grabScores.send(false);

			/*
				var id = achievementData.get(achievement);
				var grantAchievementRequest:GJRequest = new GJRequest(RequestType.TROPHIES_ADD(id.gjid));
				grantAchievementRequest.onComplete.add(function(res)
				{
					trace('Completed ' + res);
				});
				grantAchievementRequest.onError.add(e ->
				{
					trace('Error ' + e);
				});
				grantAchievementRequest.send(false);
			 */
		}
	}

	public static function ownsAllAchievements():Bool
	{
		var ownedAll:Bool = true;

		var achievementsToCheck:Array<String> = [
			'FCInitium',
			'FCResonance',
			'FCPartea',
			'FCEternalStar',
			'FCVexation',
			'FCOutOfTime',
			'CompleteAct1',
			'FCMeguca',
			'FCReconnect',
			'FCStardom',
			'ResOutheal',
			'VexYikes',
			'YoureOnMyTime',
			'TimeWaitsForMe',
			'Tenacious',
			'ThanksForPlaying',
			'ChamberOfLight',
			'PinpointAccuracy',
			'Devoted'
		];

		for (i in 0...achievementsToCheck.length)
		{
			if (isAchievementLocked(achievementsToCheck[i]))
			{
				ownedAll = false;
			}
		}

		return ownedAll;
	}

	public static function sessionStatus()
	{
		var grantAchievementRequest:GJRequest = new GJRequest(RequestType.USER_AUTH);
		grantAchievementRequest.onComplete.add(function(res)
		{
			trace('Completed ' + res);
		});
		grantAchievementRequest.onError.add(e ->
		{
			trace('Error ' + e);
		});
		grantAchievementRequest.send(false);
	}

	public static function sendScore(leaderboardID:Int, score:Int, additonalData:String)
	{
		if (signedIntoGJ && !onOutdatedBuild && !lockGJprogression)
		{
			var requestLeaderboardScore:GJRequest = new GJRequest(RequestType.SCORES_ADD('$score', score, additonalData, leaderboardID));
			requestLeaderboardScore.onComplete.add(function(res)
			{
				trace('Completed ' + res);
			});
			requestLeaderboardScore.onError.add(e ->
			{
				trace('Error ' + e);
			});
			requestLeaderboardScore.send(false);
		}
	}

	public static function returnFCStatus():String
	{
		var returnedString:String = '';

		if (PlayState.instance.hits.get('sick') >= 1
			&& PlayState.instance.hits.get('good') == 0
			&& PlayState.instance.hits.get('bad') == 0
			&& PlayState.instance.hits.get('shit') == 0
			&& PlayState.instance.misses == 0)
			returnedString = 'MFC';
		else if (PlayState.instance.hits.get('good') >= 1
			&& PlayState.instance.hits.get('bad') == 0
			&& PlayState.instance.hits.get('shit') == 0
			&& PlayState.instance.misses == 0)
			returnedString = 'GFC';
		else if (PlayState.instance.hits.get('bad') >= 1 && PlayState.instance.hits.get('shit') == 0 && PlayState.instance.misses == 0)
			returnedString = 'FC';
		else if (PlayState.instance.hits.get('shit') >= 1 && PlayState.instance.misses == 0)
			returnedString = 'FC';
		else if (PlayState.instance.misses >= 1 && PlayState.instance.misses <= 9)
			returnedString = 'SDCB';
		else if (PlayState.instance.misses >= 10)
			returnedString = 'Clear';

		return returnedString;
	}

	public static function padMultiplier(string:Float):String
	{
		var returnedString = Std.string(string);

		var addZero:Bool = false;
		if (StringTools.endsWith(returnedString, '0'))
			addZero = true;

		if (returnedString.length == 1)
			returnedString += '.0';

		if (returnedString.length == 2)
			returnedString += '.0';

		if (returnedString.length == 3)
			addZero = true;
		if (addZero)
			returnedString += '0';

		returnedString += 'x';

		return returnedString;
	}
}
