shader_type canvas_item;
render_mode unshaded;

// Noise burn from the fly. burn is capped at 0.5 so half the cloth always remains.
// Ember edge 0.035, char band 0.09 (UV space).
uniform sampler2D flag_tex : filter_linear, repeat_disable;
uniform sampler2D field_mask : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float burn = 0.0;
uniform float seed = 1.0;
uniform float time_s = 0.0;
uniform float tint_mix = 0.0;
uniform float apply_tint = 0.0;
uniform float use_mask = 0.0;
uniform vec4 nation_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float b = clamp(burn, 0.0, 0.5);
	vec4 tex = texture(flag_tex, UV);
	float mask = 0.0;
	if (use_mask > 0.5) {
		mask = texture(field_mask, UV).r;
	}
	vec3 rgb = mix(tex.rgb, nation_colour.rgb, clamp(tint_mix, 0.0, 1.0) * mask * clamp(apply_tint, 0.0, 1.0));
	float n = texture(noise_tex, UV * vec2(3.2, 2.1) + vec2(seed * 0.17, seed * 0.05)).r;
	float field = UV.x * 0.72 + n * 0.28;
	float front = 1.0 - b * 2.0;
	float dist = field - front;
	if (dist > 0.09) {
		discard;
	}
	if (dist > 0.0) {
		float flicker = 0.75 + 0.25 * sin(time_s * 14.0 + n * 6.0);
		vec3 ember = vec3(1.0, 0.42, 0.10) * flicker;
		vec3 charr = vec3(0.08, 0.07, 0.06);
		float edge = smoothstep(0.0, 0.035, dist);
		rgb = mix(ember, charr, edge);
		if (dist < 0.035) {
			rgb = mix(rgb, ember, 0.85);
		}
	}
	COLOR = vec4(rgb, tex.a);
}
