#pragma header

const float blurSize = 1.0/512.0;
const float intensity = 0.35;
uniform float amt;

void main()
{
    vec4 sum = vec4(0);
    vec2 texcoord = openfl_TextureCoordv;
    int j;
    int i;

    sum += texture2D(bitmap, vec2(texcoord.x - 4.0*blurSize, texcoord.y)) * 0.05;
    sum += texture2D(bitmap, vec2(texcoord.x - 3.0*blurSize, texcoord.y)) * 0.09;
    sum += texture2D(bitmap, vec2(texcoord.x - 2.0*blurSize, texcoord.y)) * 0.12;
    sum += texture2D(bitmap, vec2(texcoord.x - blurSize, texcoord.y)) * 0.15;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y)) * 0.16;
    sum += texture2D(bitmap, vec2(texcoord.x + blurSize, texcoord.y)) * 0.15;
    sum += texture2D(bitmap, vec2(texcoord.x + 2.0*blurSize, texcoord.y)) * 0.12;
    sum += texture2D(bitmap, vec2(texcoord.x + 3.0*blurSize, texcoord.y)) * 0.09;
    sum += texture2D(bitmap, vec2(texcoord.x + 4.0*blurSize, texcoord.y)) * 0.05;
        
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y - 4.0*blurSize)) * 0.05;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y - 3.0*blurSize)) * 0.09;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y - 2.0*blurSize)) * 0.12;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y - blurSize)) * 0.15;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y)) * 0.16;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y + blurSize)) * 0.15;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y + 2.0*blurSize)) * 0.12;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y + 3.0*blurSize)) * 0.09;
    sum += texture2D(bitmap, vec2(texcoord.x, texcoord.y + 4.0*blurSize)) * 0.05;

    gl_FragColor = sum * -sin(amt)+ texture2D(bitmap, texcoord);
}
