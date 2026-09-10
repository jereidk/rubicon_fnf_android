#pragma header

uniform float strength;

void main() {
	vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
	gl_FragColor = mix(color, vec4(color.a), strength);
}