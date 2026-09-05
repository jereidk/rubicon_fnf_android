import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import funkin.backend.scripting.events.sprite.PlayAnimEvent;

using StringTools;

var camMovementTween:FlxTween;
var camMovementDistance:Float = 15;
var charOriginalOffsets:Map<String, Array<Float>> = [];
var overwriteCharacter:Character;

function postCreate()
{
	for (strum in strumLines.members)
	{
		for (character in strum.characters)
		{
			if (!charOriginalOffsets.exists(character.curCharacter))
				charOriginalOffsets.set(character.curCharacter, [character.cameraOffset.x, character.cameraOffset.y]);
		}
	}
}

function update(elapsed:Float)
{
	for (strum in strumLines.members)
	{
		for (character in strum.characters)
		{
			if (character.getAnimName().contains('idle') || character.getAnimName().contains('dance'))
			{
				character.cameraOffset.x = charOriginalOffsets.get(character.curCharacter)[0];
				character.cameraOffset.y = charOriginalOffsets.get(character.curCharacter)[1];
			}
		}
	}
}

function onNoteHit(e)
{
	if (e.note.isSustainNote)
		return;

	if (charOriginalOffsets.exists(e.character.curCharacter))
	{
		e.character.cameraOffset.x = charOriginalOffsets.get(e.character.curCharacter)[0];
		e.character.cameraOffset.y = charOriginalOffsets.get(e.character.curCharacter)[1];

		if (camMovementTween != null)
			camMovementTween.complete();

		switch (e.direction)
		{
			case 0:
				e.character.cameraOffset.x -= camMovementDistance;
			case 1:
				e.character.cameraOffset.y += camMovementDistance;
			case 2:
				e.character.cameraOffset.y -= camMovementDistance;
			case 3:
				e.character.cameraOffset.x += camMovementDistance;
		}
	}
}

function onEvent(e)
{
	var params:Array = e.event.params;
	if (e.event.name == "Camera Position")
	{
		if (params[7])
			curCameraTarget = 0;
	}
}
