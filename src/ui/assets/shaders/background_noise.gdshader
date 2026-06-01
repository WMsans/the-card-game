shader_type canvas_item;

uniform sampler2D noise_texture;
uniform sampler2D warp_texture;
uniform float drift_speed : hint_range(0.0, 0.1) = 0.02;
uniform float drift_angle : hint_range(0.0, 6.283) = 0.785;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.0;
uniform float warp_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 color_dark : source_color = vec4(0.17, 0.13, 0.20, 1.0);
uniform vec4 color_bright : source_color = vec4(0.23, 0.18, 0.28, 1.0);

void fragment() {
	float rotating_angle = drift_angle + sin(TIME * 0.17) * 0.9;
	vec2 drift_dir = vec2(cos(rotating_angle), sin(rotating_angle));
	float drift_offset = drift_speed * TIME;

	float breathing_scale = noise_scale * (1.0 + sin(TIME * 0.23) * 0.08);
	float pulsed_warp = warp_strength * (1.0 + sin(TIME * 0.31 + 2.0) * 0.25);

	vec2 centered = UV - 0.5;
	float radius = length(centered);
	float angle = atan(centered.y, centered.x);
	float twirl_angle = angle + sin(TIME * 0.12 + 0.5) * radius * 2.5 + TIME * 0.03;
	vec2 twirled_uv = vec2(cos(twirl_angle), sin(twirl_angle)) * radius + 0.5;

	float warp_x = texture(warp_texture, (twirled_uv + vec2(0.0, 0.37)) * breathing_scale + drift_dir * drift_offset * 0.7).r - 0.5;
	float warp_y = texture(warp_texture, (twirled_uv + vec2(0.37, 0.0)) * breathing_scale + drift_dir * drift_offset * 0.7).r - 0.5;
	vec2 warp_offset = vec2(warp_x, warp_y) * pulsed_warp;

	float noise_val = texture(noise_texture, UV * breathing_scale + drift_dir * drift_offset + warp_offset).r;

	vec3 color = mix(color_dark.rgb, color_bright.rgb, noise_val);
	COLOR = vec4(color, 1.0);
}
