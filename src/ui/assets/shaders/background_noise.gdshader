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
	vec2 drift_dir = vec2(cos(drift_angle), sin(drift_angle));
	float drift_offset = drift_speed * TIME;

	// Sample warp texture at offset UVs for independent X/Y distortion
	float warp_x = texture(warp_texture, (UV + vec2(0.0, 0.37)) * noise_scale + drift_dir * drift_offset * 0.7).r - 0.5;
	float warp_y = texture(warp_texture, (UV + vec2(0.37, 0.0)) * noise_scale + drift_dir * drift_offset * 0.7).r - 0.5;
	vec2 warp_offset = vec2(warp_x, warp_y) * warp_strength;

	// Sample base noise with drift + warp
	float noise_val = texture(noise_texture, UV * noise_scale + drift_dir * drift_offset + warp_offset).r;

	vec3 color = mix(color_dark.rgb, color_bright.rgb, noise_val);
	COLOR = vec4(color, 1.0);
}
