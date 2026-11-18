shader_type canvas_item;
render_mode unshaded;

// Vertex wave: amplitude 0.085×height, 1.5 waves + 0.35 harmonic at 3.1, ~1.2 rad/s.
// Fragment shades ±22% from the slope and can tint the GENERIC slate field.
uniform sampler2D flag_tex : filter_linear, repeat_disable;
uniform sampler2D field_mask : filter_linear, repeat_disable;
uniform float amp_px = 20.4;
uniform float time_s = 0.0;
uniform float furled = 0.0;
uniform float tint_mix = 0.0;
uniform float apply_tint = 0.0;
uniform float use_mask = 1.0;
uniform vec4 nation_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	float x = clamp(UV.x, 0.0, 1.0);
	float phase = time_s * 1.2;
	float wave = sin(x * 1.5 * 6.2831853 + phase) + 0.35 * sin(x * 3.1 * 6.2831853 + phase * 1.17);
	float env = x * (1.0 - furled);
	VERTEX.y += wave * amp_px * env;
	VERTEX.x *= mix(1.0, 0.08, furled);
}

void fragment() {
	vec4 tex = texture(flag_tex, UV);
	float mask = 1.0;
	if (use_mask > 0.5) {
		mask = texture(field_mask, UV).r;
	} else {
		vec3 key = vec3(46.0 / 255.0, 58.0 / 255.0, 78.0 / 255.0);
		mask = 1.0 - smoothstep(0.02, 0.14, distance(tex.rgb, key));
	}
	vec3 rgb = mix(tex.rgb, nation_colour.rgb, clamp(tint_mix, 0.0, 1.0) * mask * clamp(apply_tint, 0.0, 1.0));
	float x = clamp(UV.x, 0.0, 1.0);
	float phase = time_s * 1.2;
	float slope = cos(x * 1.5 * 6.2831853 + phase) + 0.35 * 3.1 / 1.5 * cos(x * 3.1 * 6.2831853 + phase * 1.17);
	float shade = 1.0 + clamp(slope, -1.0, 1.0) * 0.22 * x * (1.0 - furled);
	rgb *= shade;
	COLOR = vec4(rgb, tex.a);
}
