#pragma header

const float SIZE = 2.35;
const float SIZE2 = SIZE / 2.;
float getGrad(float time)
{
    return 1. - pow(abs(time*SIZE - SIZE2), 15.);
}
void main()
{
	gl_FragColor = texture2D(bitmap, openfl_TextureCoordv.xy) * getGrad(openfl_TextureCoordv.y - .025);
}