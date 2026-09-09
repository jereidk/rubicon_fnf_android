class ColorUtil
{
	private static function convert_channel_to_float(channel:Int):Float
	{
		return channel / 255;
	}

	private static function get_rgba_int(color:Int):
		{
			r:Int,
			g:Int,
			b:Int,
			a:Int
		}
	{
		return {
			a: (color >> 24) & 0xFF,
			r: (color >> 16) & 0xFF,
			g: (color >> 8) & 0xFF,
			b: color & 0xFF
		};
	}

	private static function get_rgba_float(color:Int):
		{
			r:Float,
			g:Float,
			b:Float,
			a:Float
		}
	{
		var color_data = get_rgba_int(color);
		color_data.r = convert_channel_to_float(color_data.r);
		color_data.g = convert_channel_to_float(color_data.g);
		color_data.b = convert_channel_to_float(color_data.b);
		color_data.a = convert_channel_to_float(color_data.a);
		return color_data;
	}

	private static function combine_rgba(color_data:
		{
			r:Int,
			g:Int,
			b:Int,
			a:Int
		}):Int
	{
		return (color_data.a << 24) | (color_data.r << 16) | (color_data.g << 8) | color_data.b;
	}

	// Actual FlxColor Static Extensions here
	public static function getDarkened(color:Int, factor:Float = 0.2):Int
	{
		factor = FlxMath.bound(factor, 0, 1);

		var color_data = get_rgba_int(color);
		color_data.r *= (1 - factor);
		color_data.g *= (1 - factor);
		color_data.b *= (1 - factor);

		return combine_rgba(color_data);
	}

	public static function getLightened(color:Int, factor:Float = 0.2):Int
	{
		factor = FlxMath.bound(factor, 0, 1);

		var color_data = get_rgba_int(color);
		trace(color_data);
		color_data.r += (255 - color_data.r) * factor;
		color_data.g += (255 - color_data.g) * factor;
		color_data.b += (255 - color_data.b) * factor;
		trace(color_data);

		return combine_rgba(color_data);
	}

	public static function add(color:Int, addingColor:Int):Int
	{
		var color_data = get_rgba_int(color);
		var adding_color_data = get_rgba_int(addingColor);
		color_data.r += adding_color_data.r;
		color_data.g += adding_color_data.g;
		color_data.b += adding_color_data.b;
		return combine_rgba(color_data);
	}

	public static function subtract(color:Int, addingColor:Int):Int
	{
		var color_data = get_rgba_int(color);
		var adding_color_data = get_rgba_int(addingColor);
		color_data.r -= adding_color_data.r;
		color_data.g -= adding_color_data.g;
		color_data.b -= adding_color_data.b;
		return combine_rgba(color_data);
	}

	// utils
	public static function get_hue(color:Int):Float
	{
		var color_data = get_rgba_float(color);
		var hueRad = Math.atan2(Math.sqrt(3) * (color_data.g - color_data.b), 2 * color_data.r - color_data.g - color_data.b);
		var hue:Float = 0;
		if (hueRad != 0)
			hue = 180 / Math.PI * hueRad;
		return ((hue < 0) ? hue + 360 : hue);
	}

	public static function get_brightness(color:Int):Float
	{
		return maxColor(color);
	}

	public static function get_luminance(color:Int):Float
	{
		var color_data = get_rgba_float(color);
		return (color_data.r * 299 + color_data.g * 587 + color_data.b * 114) * 0.001;
	}

	public static function get_saturation(color:Int):Float
	{
		(maxColor(color) - minColor(color)) / get_brightness(color);
	}

	public static function get_lightness(color:Int):Float
	{
		return (maxColor(color) + minColor(color)) * 0.5;
	}

	public static function maxColor(color:Int):Float
	{
		var color_data = get_rgba_float(color);
		return Math.max(color_data.r, Math.max(color_data.g, color_data.b));
	}

	public static function minColor(color:Int):Float
	{
		var color_data = get_rgba_float(color);
		return Math.min(color_data.r, Math.min(color_data.g, color_data.b));
	}
}
