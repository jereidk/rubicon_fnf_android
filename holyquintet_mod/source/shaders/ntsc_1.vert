#pragma header

// by https://github.com/HEIHUAa/

void main(void) {
	openfl_TextureCoordv = openfl_TextureCoord;

	vec4 position = openfl_Position;
	position.x *= (openfl_TextureSize.x / openfl_TextureSize.x) * 1.0;

	gl_Position = openfl_Matrix * position;
}