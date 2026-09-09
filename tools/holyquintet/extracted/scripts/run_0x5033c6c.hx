 Score';
			}
		});
		FlxTween.tween(gauntletMultiCount, {y: gauntletMultiCount.y - 50}, 1.0, {ease: FlxEase.expoIn});
		FlxTween.tween(accuracyCount, {y: accuracyCount.y - 26}, 0.5, {ease: FlxEase.sineOut, startDelay: 1.0});
	}
}

function increaseRank(newRank:String)
{
	if (curRank != 0)
	{
		rankIcon.playAnim(newRank);

		if (animationGrade != "BAD")
		{
			rankIncreaseFX = new FunkinSprite(1327, 723).loadSprite(Paths.image('game/results/rankadd'));
			rankIncreaseFX.blend = BlendMode.ADD;
			if (curRank <= 6)
				rankIncreaseFX.scale.x = 0.5;
			else if (curRank <= 7)
				rankIncreaseFX.scale.x = 0.75;
			else
				rankIncreaseFX.scale.x = 1.0;
			add(GenUtil.glowPulse(rankIncreaseFX, 0.75, 0.5, 0.75)).cameras = [resultsCam];

			FlxG.sound.play(Paths.sound('game/results/results_rankup'), 1.25 * Options.volumeSFX).pitch = 1.25 + (0.1 * curRank);
		}
	}
}

function startGFAnimation()
{
	var introLength:Float = 2.0;
	var songDelay:Float = 0.0;
	switch (animationGrade)
	{
		case "PERFECT":
			introLength = 1.6;
			songDelay = 2.0;

		case "GREAT":
			introLength = 4.5;
			songDelay = 3.0;

		case "GOOD":
			introLength = 1.5;
			songDelay = 1.25;

		case "BAD":
			introLength = 4.75;
	}

	new FlxTimer().start(songDelay, function(tmr:FlxTimer)
	{
		FlxG.sound.play(Paths.sound('game/results/result-${animationGrade.toLowerCase()}-intro')).onComplete = function()
		{
			CoolUtil.playMusic(Paths.music('result-${animationGrade.toLowerCase()}-loop'));
		};
	});

	new FlxTimer().start(introLength, function(tmr:FlxTimer)
	{
		gf.playAnim('start', true);
		gf.visible = true;
	});

	if (animationGrade == 'PERFECT')
	{
		var duration:Float = 3.35;

		new FlxTimer().start(duration, function(tmr:FlxTimer)
		{
			zoomTween?.cancel();
			camera.zoom = 1.0;
			zoomTween = FlxTween.tween(camera, {zoom: 1.2}, 1.0, {ease: FlxEase.expoIn});

			FlxTween.tween(whiteOverlay, {alpha: 0.35}, 0.75, {ease: FlxEase.expoIn, startDelay: 0.25});
		});

		new FlxTimer().start(duration + 1, function(tmr:FlxTimer)
		{
			FlxTween.cancelTweensOf(whiteOverlay);
			FlxTween.tween(whiteOverlay, {alpha: 0.0}, 1.5, {ease: FlxEase.quadOut});

			starsBG.alpha = 0.25;

			if (Options.flashingLights)
			{
				pinkglow.alpha = 1.0;
				FlxTween.tween(pinkglow, {alpha: 0.25}, 1.5, {ease: FlxEase.quadOut});
			}
			else
			{
				pingglow.alpha = 0.25;
			}

			if (!Options.lowMemoryMode)
			{
				var colors:Array<FlxColor> = [0xFFD00D2B, 0xFF72AEDA, 0xFFFFEC76, 0xFFFBA8BC, 0xFFA83658, 0xFF3A3A3A];

				for (i in 0...50)
				{
					var conf = new FunkinSprite(-75, 1080).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.velocity.set(FlxG.random.int(150, 850), -FlxG.random.int(600, 1300));
					conf.acceleration.set(-FlxG.random.int(25, 50), FlxG.random.int(750, 1000));
					conf.angularVelocity = FlxG.random.int(-250, 250);
					conf.color = colors[FlxG.random.int(0, colors.length - 1)];

					conf.moves = true;
				}

				for (i in 0...50)
				{
					var conf = new FunkinSprite(1960, 1080).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.velocity.set(-FlxG.random.int(150, 850), -FlxG.random.int(600, 1300));
					conf.acceleration.set(FlxG.random.int(25, 50), FlxG.random.int(750, 1000));
					conf.angularVelocity = FlxG.random.int(-250, 250);
					conf.color = colors[FlxG.random.int(0, colors.length - 1)];

					conf.moves = true;
				}
			}

			zoomTween?.cancel();
			camera.zoom = 1.10;
			zoomTween = FlxTween.tween(camera, {zoom: 1.0}, 1.0, {
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween)
				{
					doEffects = true;
				}
			});
		});

		/*
			new FlxTimer().start(3.0, function(tmr:FlxTimer)
			{
				new FlxTimer().start(0.05, function(tmr:FlxTimer)
				{
					var conf = new FunkinSprite(500, 500).loadSprite(Paths.image('game/results/confet${FlxG.random.int(1, 4)}'));
					add(conf);
					conf.x = FlxG.random.int(-1000, 1000);
					conf.y = FlxG.random.int(-1000, 1000);
					conf.velocity.y += FlxG.random.int(-1000, 1000);
				}, 0);
			});
		 */
	}
}

function update(elapsed:Float)
{
	if (controls.ACCEPT && canControl)
	{
		if (!PlayState.isGauntletMode)
		{
			FunkinSave.setSongHighscore(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation, {
				score: psi.songScore,
				misses: psi.misses,
				accuracy: psi.accuracy,
				hits: psi.hits,
				date: Date.now().toString(),
				customData: {
					rank: psi.curRating.rating,
					fcrank: GenUtil.returnFCStatus()
				}
			}, []);
		}
		canControl = false;

		doEffects = false;

		GenUtil.playUISound('confirm');

		FlxG.sound.music.fadeOut(0.75, 0.0);

		camFadeOverlay = new FlxSprite(-FlxG.width * 1, -FlxG.height * 1).makeGraphic(1, 1, FlxColor.BLACK);
		camFadeOverlay.scale.set(FlxG.width * 4, FlxG.height * 4);
		add(camFadeOverlay);
		camFadeOverlay.scrollFactor.set(0.0, 0.0);
		camFadeOverlay.alpha = 0.0;

		FlxG.save.data.freeplayUnlocked = true;

		godukaEnabled = false;
		godukaCooldown = -1;

		FlxTween.tween(camFadeOverlay, {alpha: 1.0}, 1.5, {
			ease: FlxEase.quadInOut,
			onComplete: function(twn:FlxTween)
			{
				new FlxTimer().start(0.5, function(tmr:FlxTimer)
				{
					if (!PlayState.isGauntletMode)
						GenUtil.sendScore(PlayState.SONG.meta.customValues.gjid, psi.songScore, 'null');

					if (!PlayState.isGauntletMode)
					{
						if (PlayState.isStoryMode)
						{
							FlxG.save.data.unlockableSongs.push(PlayState.SONG.meta.name);
							FlxG.save.data.curStoryProgress += 1;
							if (PlayState.SONG.meta.name == 'out-of-time')
							{
								if (!FlxG.save.data.unlockableSongs.contains('meguca') && !FlxG.save.data.viewedMenu.contains(1))
								{
									FlxG.save.data.viewedMenu.push(1);
									FlxG.save.flush();
								}

								FlxG.save.data.unlockableSongs.push('meguca');

								FlxG.save.data.curStoryProgress = 0;

								FlxG.save.data.accoladesUnlocked = true;

								nextact = new FunkinSprite(0, 0).loadSprite(Paths.image('game/results/act1end'));
								add(nextact);
								nextact.alpha = 0.0;
								FlxTween.tween(nextact, {alpha: 1.0}, 3.0, {
									ease: FlxEase.quadIn,
									onComplete: function(twn:FlxTween)
									{
										FlxTween.tween(nextact, {alpha: 0.0}, 1.0, {
											ease: FlxEase.quadIn,
											startDelay: 1.0,
											onComplete: function(twn:FlxTween)
											{
												psi.endingSong = true;
												psi.nextSong();
											}
										});
									}
								});
							}
							else
							{
								psi.endingSong = true;
								psi.nextSong();
							}
						}
						else
						{
							switch (PlayState.SONG.meta.name)
							{
								case 'meguca':
									FlxG.save.data.unlockableSongs.push('reconnect');
								case 'reconnect':
									FlxG.save.data.unlockableSongs.push('stardom');
									FlxG.save.data.gauntletUnlocked = true;
								case 'stardom':
									FlxG.save.data.galleryUnlocked = true;
							}

							psi.endingSong = true;
							psi.nextSong();
						}
					}
					else
					{
						MusicBeatState.skipTransIn = true;
						MusicBeatState.skipTransOut = true;

						// if (curGauntletGamemode == 'Standard')
						// {
						//	psi.endingSong = true;
						///	psi.nextSong();
						// }

						if (PlayState.storyPlaylist.length >= 2)
						{
							MusicBeatState.skipTransIn = true;
							MusicBeatState.skipTransOut = true;
							if (curGauntletGamemode == 'Standard')
							{
								psi.endingSong = true;
								psi.nextSong();
							}
							else
							{
								PlayState.campaignScore += psi.songScore;
								PlayState.campaignMisses += psi.misses;
								FlxG.switchState(new ModState("HQGauntletTransition", {endGauntlet: false}));
							}
						}
						else
						{
							MusicBeatState.skipTransIn = true;
							MusicBeatState.skipTransOut = true;
							PlayState.campaignScore += psi.songScore;
							PlayState.campaignMisses += psi.misses;

							FlxG.switchState(new ModState("HQGauntletTransition", {endGauntlet: true}));
						}
					}
				});
			}
		});
	}
}

function beatHit()
{
	if (doEffects)
	{
		if ((curBeat % 2) == 0)
		{
			zoomTween?.cancel();
			camera.zoom = 1.01;
			zoomTween = FlxTween.tween(camera, {zoom: 1.0}, 0.5, {ease: FlxEase.quadOut});

			if (Options.flashingLights)
			{
				pinkglow.alpha = 0.35;
				FlxTween.tween(pinkglow, {alpha: 0.25}, 0.75, {ease: FlxEase.quadOut});
			}
		}
	}
}
