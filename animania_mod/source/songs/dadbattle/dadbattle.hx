import funkin.modding.module.Module;
import funkin.Paths;
import funkin.play.PlayState;
import funkin.play.song.Song;
import funkin.audio.FunkinSound;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import funkin.play.cutscene.CutsceneType;
import funkin.play.cutscene.VideoCutscene;
import funkin.play.PlayStatePlaylist;

class DadbattleSong extends Song
{
	function new()
	{
		super("dadbattle");
		isBoss = true;
	}
}
