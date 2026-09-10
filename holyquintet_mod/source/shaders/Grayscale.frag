#pragma header 
uniform float grayness;

void main()
{
    vec2 uv = openfl_TextureCoordv;

    vec4 color = flixel_texture2D(bitmap, uv);
    float scale = (color.x + color.y + color.z)/3.0;

    float colorPerc = 1.0 - grayness;
    color.r = (color.r * colorPerc) + (grayness * scale);
    color.g = (color.g * colorPerc) + (grayness * scale);
    color.b = (color.b * colorPerc) + (grayness * scale);
    gl_FragColor = color;
}