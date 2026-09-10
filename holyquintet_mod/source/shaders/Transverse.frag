/*
Transverse Chromatic Aberration

Based on https://github.com/FlexMonkey/Filterpedia/blob/7a0d4a7070894eb77b9d1831f689f9d8765c12ca/Filterpedia/customFilters/TransverseChromaticAberration.swift

Simon Gladman | http://flexmonkey.blogspot.co.uk | September 2017
*/

#pragma header
uniform vec2 iResolution;
vec2 fragCoord = openfl_TextureCoordv * iResolution;
vec2 uv = openfl_TextureCoordv;

int sampleCount = 50;
float blur = 0.25; 
uniform float falloff = 7.0; 

// use iChannel0 for video, iChannel1 for test grid

void main()
{
    vec2 uv = openfl_TextureCoordv;

    vec2 destCoord = openfl_TextureCoordv;

    vec2 direction = normalize(destCoord - 0.5); 
    vec2 velocity = direction * blur * pow(length(destCoord - 0.5), falloff);
    float inverseSampleCount = 1.0 / float(sampleCount); 
    
    mat3x2 increments = mat3x2(velocity * 1.0 * inverseSampleCount,
                            velocity * 2.0 * inverseSampleCount,
                            velocity * 4.0 * inverseSampleCount);

    vec3 accumulator = vec3(0);
    mat3x2 offsets = mat3x2(0); 
    
    for (int i = 0; i < sampleCount; i++) {
        accumulator.r += texture2D(bitmap, destCoord + offsets[0]).r; 
        accumulator.g += texture2D(bitmap, destCoord + offsets[1]).g; 
        accumulator.b += texture2D(bitmap, destCoord + offsets[2]).b; 
        
        offsets -= increments;
    }

    gl_FragColor = vec4(accumulator / float(sampleCount), 1.0);
}