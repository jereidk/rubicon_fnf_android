#pragma header 
uniform float iTime;
uniform float scale;
uniform vec3 iResolution;

void findRatio (in vec2 res, out vec2 rat) {
    vec2 r = res;
    float gcf;
    for(float i = 1.; i <= r.x && i <= r.y; ++i)  
    {  
        if (mod(r.x,float(i)) == 0. && mod(r.y,float(i)) == 0.)  
            gcf = float(i);
    }
    r /= gcf;
    rat = r;
}

vec2 hash(in vec2 x) {
    vec2 p = fract(sin(x.yx*3000.)*54321.);
    return fract(p);
}

void main()
{
        vec2 ires = iResolution.xy;
        vec2 rRatio;
        findRatio(ires,rRatio);
        
        vec2 uv = openfl_TextureCoordv;
        vec2 uv2 = fract(uv*rRatio*iResolution.x*16.);
        
        vec2 rand = (hash(uv+iTime)-0.5)*scale;
        rand.y /= 10.;
        
        vec3 col1 = flixel_texture2D(bitmap,uv+rand/-10.).rgb;
        
        float disp = dot(col1,vec3(5.,5.,5.));
        uv2 /= (disp-0.5)*0.1+rand;
        uv2 += fract((disp-0.5)*10.);
        
        
        vec3 col2 = flixel_texture2D(bitmap,uv2).rgb*(col1/12.);
        
        col1 -= col2;
        
        
        gl_FragColor = vec4(col1,1.0)* flixel_texture2D(bitmap, uv).a;
}