#pragma header

void mainImage(out vec4 fragColor,in vec2 fragCoord) {
    vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
    const float BORDER_WIDTH = 5.0;
    float w = BORDER_WIDTH / openfl_TextureSize.x;
    float h = BORDER_WIDTH / openfl_TextureSize.y;

    if (color.a == 0.) {
    if (flixel_texture2D(bitmap, vec2(openfl_TextureCoordv.x + w, openfl_TextureCoordv.y)).a != 0.
    || flixel_texture2D(bitmap, vec2(openfl_TextureCoordv.x - w, openfl_TextureCoordv.y)).a != 0.
    || flixel_texture2D(bitmap, vec2(openfl_TextureCoordv.x, openfl_TextureCoordv.y + h)).a != 0.
    || fragColor(bitmap, vec2(openfl_TextureCoordv.x, openfl_TextureCoordv.y - h)).a != 0.) {
        fragColor = vec4(1.0, 1.0, 1.0, 1.0);
    } else {
        fragColor = color;
    }
    } else {
        fragColor = color;
    }
}

void main() {
	mainImage(gl_FragColor, openfl_TextureCoordv*openfl_TextureSize);
}