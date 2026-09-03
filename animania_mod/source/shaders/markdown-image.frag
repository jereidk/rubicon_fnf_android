#pragma header

float udRoundBox( in vec2 p, in vec2 b, in float r )
{
    return length(max(abs(p)-b+r,0.0)) / r;
}

void main()
{
    float yAdj = openfl_TextureSize.y / openfl_TextureSize.x;
    vec2 size = vec2(1.0, yAdj);
    vec2 p = (openfl_TextureCoordv * 2.0*size)-size;
    float f = udRoundBox(p, size, 0.05);
    gl_FragColor = texture2D(bitmap, openfl_TextureCoordv);
    // gl_FragColor *= smoothstep(1.0, 0.0, f);
    gl_FragColor *= 1.0 - f;

    gl_FragColor = applyFlixelEffects(gl_FragColor);
}
