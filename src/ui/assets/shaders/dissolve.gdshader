shader_type canvas_item;

uniform sampler2D dissolve_texture : source_color;
uniform float dissolve_value : hint_range(0,1);
uniform float burn_size: hint_range(0.0, 1.0, 0.01);
uniform vec4 burn_color: source_color;

// A CanvasGroup composites its children into a buffer that is exposed to the
// node's material through the SCREEN texture, NOT through TEXTURE (TEXTURE is
// left unbound and samples as solid white, which is why the whole card turned
// white). Sample the composited card from the screen texture instead.
// See godotengine/godot#69885 and #89341.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment(){
	vec4 main_texture = texture(screen_tex, SCREEN_UV);
	vec4 noise_texture = texture(dissolve_texture, UV);

	// Shrink the burn band to ~0 at the extremes so no stray burn_color dot
	// lingers when fully visible/hidden...
	float burn_size_step = burn_size * step(0.001, dissolve_value) * step(dissolve_value, 0.999);
	// ...but keep a tiny non-zero edge width: a zero-width smoothstep (edge0 == edge1)
	// divides by zero and yields NaN on many GPUs.
	float edge = max(burn_size_step, 0.0001);
	float threshold = smoothstep(noise_texture.x - edge, noise_texture.x, dissolve_value);
	float border = smoothstep(noise_texture.x, noise_texture.x + edge, dissolve_value);

	COLOR.a *= threshold;
	COLOR.rgb = mix(burn_color.rgb, main_texture.rgb, border);
}
