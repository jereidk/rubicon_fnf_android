
import funkin.play.notes.notestyle.ScriptedNoteStyle;
import flixel.graphics.frames.FlxAtlasFrames;

import funkin.play.notes.Strumline;
import funkin.play.notes.NoteHoldCover;

class AmTakeBase extends ScriptedNoteStyle
{
	public function new()
	{
		super("amtake-base");
	}

	public override function buildNoteHoldCoverSprite(target:NoteHoldCover):Void
	{
		// Apply the note sprite frames.
		var atlas:FlxAtlasFrames = buildNoteHoldCoverFrames(false);

		if (atlas == null)
		{
			throw 'Could not load spritesheet for note hold cover style: $id';
		}

		target.frames = atlas;

		target.antialiasing = !_data.assets.holdNoteCover.isPixel;
		target.scale.set(_data.assets.holdNoteCover.scale, _data.assets.holdNoteCover.scale);
		target.updateHitbox();
		target.flipY = Preferences.downscroll;
		//target.frameOffset.set(_data.assets.holdNoteCover.offsets[0], !Preferences.downscroll ? _data.assets.holdNoteCover.offsets[1] : -(_data.assets.holdNoteCover.offsets[1] * 3));

		// Apply the animations.
		buildNoteHoldCoverAnimations(target);
	}

	override function getHoldCoverOffsets() {
		if (Preferences.downscroll)
			return [_data.assets.holdNoteCover.offsets[0], -_data.assets.holdNoteCover.offsets[1]];
		else
			return _data.assets.holdNoteCover.offsets;
	}
}
