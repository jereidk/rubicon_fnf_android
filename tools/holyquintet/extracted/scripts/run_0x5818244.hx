import funkin.backend.scripting.events.sprite.PlayAnimEvent;

using StringTools;

var ignorePlayerAnims:Array<String> = [
	'dodgeLEFT',
	'dodgeRIGHT',
	'dodgeUP',
	'dodgeDOWN',
	'ootmidanim',
	'hurt',
	'hurt-short',
	'hurt-small',
	'hurt-shot',
	'transition'
];

var ignorePlayerAnimation:Bool = false;

var ignoreCPUAnims:Array<String> = [
	'attack',
	'transition',
	'ootmidanim',
	'timestop',
	'shoot',
	'healstart',
	'healend',
	'letsgo',
	'bow',
	'intro'
];

public var ignoreCPUAnimation:Bool = false;
public var playerIgnoreNoteAnims:Bool = false;

function update(elapsed:Float)
{
	if (bf != null)
	{
		if ((bf.animation.curAnim.name.contains('-end') && bf.animation.curAnim.finished) && !playerIgnoreNoteAnims)
			bf.dance();

		if ((bf.animation.curAnim.name.contains('dodge') && bf.animation.curAnim.finished) && !playerIgnoreNoteAnims)
			bf.dance();
	}

	if (dad != null)
	{
		if ((dad.animation.curAnim.name.contains('-end') && dad.animation.curAnim.finished) && !ignoreCPUAnimation)
			dad.dance();
	}
}

function onStrumCreation(e)
{
	e.cancelAnimation();
}

function onPlayerHit(e)
{
	e.cancel();

	if (e == null)
		return;

	ignorePlayerAnimation = false;

	var strumGlow:Bool = true;
	if (e.noteType == 'Timestop Note')
		strumGlow = false;

	if (e.note.__strum != null && strumGlow)
	{
		if (!e.strumGlowCancelled)
			e.note.__strum.press(e.note.strumTime);
		if (e.showSplash && Options.splashesEnabled)
			splashHandler.showSplash(e.note.splash, e.note.__strum);
	}

	for (char in e.characters)
		if (char != null)
		{
			for (anim in ignorePlayerAnims)
			{
				if (char.animation.curAnim.name == anim)
				{
					ignorePlayerAnimation = true;
					return;
				}
			}
		}

	if (e.character != null)
	{
		if (e.character.curCharacter == 'gf-meguca' && FlxG.random.bool(50) && !e.note.isSustainNote)
		{
			e.animSuffix = '-alt';
		}
	}

	var playSingAnimation:Bool = true;
	if (e.noteType == 'Timestop Note' || e.noteType == 'Bullet Note')
		playSingAnimation = false;

	if (playSingAnimation)
	{
		for (char in e.characters)
			if (char != null)
			{
				if (!ignorePlayerAnimation && !playerIgnoreNoteAnims)
				{
					char.playAnim(char.getSingAnim(e.direction, '') + e.animSuffix, e.forceAnim, PlayAnimEvent.SING);
					char.animation.finishCallback = () ->
					{
						char.animation.pause();
						char.animation.finishCallback = null;
					};
				}
			}
	}
}

function onPlayerMiss(e)
{
	e.cancel();

	if (e == null)
		return;

	ignorePlayerAnimation = false;

	var playMissAnimation:Bool = true;
	if (e.noteType == 'Timestop Note')
		playMissAnimation = false;

	for (char in e.characters)
	{
		if (char == null)
			continue;

		for (anim in ignorePlayerAnims)
		{
			if (char.animation.curAnim.name == anim)
			{
				ignorePlayerAnimation = true;
				continue;
			}
		}

		if (playMissAnimation)
		{
			if (!ignorePlayerAnimation && !playerIgnoreNoteAnims)
			{
				if (e.stunned)
					char.stunned = true;

				char.playAnim(char.getSingAnim(e.direction, '') + e.animSuffix, e.forceAnim, PlayAnimEvent.SING);
			}
		}
	}

	var muteVocals:Bool = true;
	if (e.noteType == 'Timestop Note')
		muteVocals = false;

	if (muteVocals)
	{
		if (e.note != null && e.muteVocals)
			e.note.strumLine.vocals.volume = 0;
		else if (e.muteVocals)
			playerStrums.vocals.volume = 0;
	}

	if (e.deleteNote && e.note != null)
		e.note.strumLine.deleteNote(e.note);
}

function onNoteHit(e)
{
	e.cancel();

	if (e == null)
		return;

	ignoreCPUAnimation = false;

	if (!e.player)
	{
		for (char in e.characters)
			if (char != null)
			{
				for (anim in ignoreCPUAnims)
				{
					if (char.animation.curAnim.name == anim)
					{
						ignoreCPUAnimation = true;
						return;
					}
				}

				if (char.curCharacter == 'madoka-meguca' && FlxG.random.bool(50) && !e.note.isSustainNote)
				{
					e.animSuffix = '-alt';
				}

				if (!ignoreCPUAnimation)
				{
					char.playAnim(char.getSingAnim(e.direction, '') + e.animSuffix, e.forceAnim, PlayAnimEvent.SING);
					char.animation.finishCallback = () ->
					{
						char.animation.pause();
						char.animation.finishCallback = null;
					};
				}
			}
	}
}

function onNoteCreation(e)
{
}
