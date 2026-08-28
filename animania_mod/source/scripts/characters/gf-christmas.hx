import funkin.play.character.AnimateAtlasCharacter;
import funkin.play.character.CharacterType;
import funkin.play.PlayState;
import funkin.Conductor;
import funkin.modding.module.Module;
import funkin.modding.module.ModuleHandler;
import funkin.play.CountdownStep;

using StringTools;

class GirlfriendChristmasCharacter extends AnimateAtlasCharacter
{
	function new()
	{
		super('gf-christmas');
	}

	var fgSnow;
	function onAdd()
	{
		super.onAdd();
		if (parentStage != null)
		{
			fgSnow = FunkinSprite.create(this.x + 285, this.y + 600, "characters/amtake/gf/gf-snow");
			parentStage.add(fgSnow);
			fgSnow.zIndex = zIndex + 1;
			fgSnow.shader = this.shader;
			parentStage.refresh();
		}
	}

	function onCountdownStep(e)
	{
		super.onCountdownStep(e);
		switch (e.step)
		{
			case CountdownStep.THREE:
				playAnimation("count3", true, false, false);
			case CountdownStep.TWO:
				playAnimation("count2", true, false, false);
			case CountdownStep.ONE:
				playAnimation("count1", true, false, false);
			case CountdownStep.GO:
				playAnimation("cheer", true, false, false);
		}
	}

	override function onAnimationFinished(prefix:String):Void
	{
		switch (prefix)
		{
			case "combo251":
				hasDanced = false;
				super.onAnimationFinished(prefix);

			default:
				super.onAnimationFinished(prefix);
		}
	}

	override function onUpdate(e)
	{
		/*if (parentStage != null && fgSnow != null)
		{
			if (fgSnow.shader != this.shader)
				fgSnow.shader = this.shader;
		}*/
	}
}
