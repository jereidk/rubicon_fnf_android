#pragma header

uniform vec3 bg_col;

void main()
{
	vec4 col = texture2D(bitmap, openfl_TextureCoordv);

	float maxrb = max( col.r, col.b );
	float dg = col.g;

	float k = clamp(dg - maxrb, 0.0, 1.0 );

	// col.rgb = vec3(min( dg, maxrb ));

	col.rgb = vec3(max( col.r, max( col.g, col.b ) ));
	// col.rgb *= bg_col.rgb * mix(bg_col.rgb, vec3(1.), 0.25);
	col.rgb *= bg_col.rgb * vec3(0.65);
	gl_FragColor = applyFlixelEffects(vec4( mix(col.rgb, bg_col.rgb, k), col.a ));

	// col.rgb = vec3(min( dg, maxrb ));
	// gl_FragColor = applyFlixelEffects(col);
}
