shader_type canvas_item;
render_mode unshaded;

// Packed skyline: R far-only, G mid, B keep (protected core), A silhouette.
// Roof strip is 1280×2, row 0 (v≈0.25) = mid roofline. y = round(R*255)*256 + round(G*255).
uniform sampler2D skyline_tex : filter_linear, repeat_disable;
uniform sampler2D roof_tex : filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float ruin = 0.0;
uniform float seed = 2.0;
uniform float char_amt = 0.55;
uniform float ember_amt = 1.0;
uniform float time_s = 0.0;
uniform float use_roof = 1.0;
uniform vec4 far_color : source_color = vec4(0.55, 0.42, 0.40, 1.0);
uniform vec4 mid_color : source_color = vec4(0.15, 0.15, 0.26, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.50, 1.0);

void fragment() {
	vec4 tex = texture(skyline_tex, UV);
	float a = tex.a;
	float mid_m = clamp(tex.g, 0.0, 1.0);
	float keep = tex.b;
	vec3 col = mix(far_color.rgb, mid_color.rgb, smoothstep(0.15, 0.75, mid_m));
	float y_px = UV.y * 480.0;
	float top = 0.0;
	float has_roof = 0.0;
	if (use_roof > 0.5) {
		vec4 roof = texture(roof_tex, vec2(UV.x, 0.25));
		top = round(roof.r * 255.0) * 256.0 + round(roof.g * 255.0);
		if (roof.b > 0.45 && top > 1.0 && top < 470.0) {
			has_roof = 1.0;
		}
	}
	float r = clamp(ruin, 0.0, 1.0);
	if (has_roof > 0.5 && r > 0.001 && keep < 0.55) {
		float n1 = texture(noise_tex, vec2(UV.x * 0.35 + seed * 0.01, 0.2)).r;
		float stepped = floor(n1 * 6.0) / 6.0;
		float depth = mix(8.0, 48.0, stepped);
		if (y_px < top + r * depth) {
			a = 0.0;
		}
		float n2 = texture(noise_tex, UV * vec2(18.0, 9.0) + vec2(seed, 0.3)).r;
		if (a > 0.05 && y_px > top + 6.0 && n2 > 1.0 - 0.18 * r) {
			a = 0.0;
		}
	}
	col = mix(col, vec3(0.10, 0.09, 0.09), char_amt * r);
	float grime = texture(noise_tex, UV * vec2(4.0, 3.0) + vec2(seed)).r;
	col += vec3(grime) * 0.08 * r;
	if (a > 0.2 && r > 0.05) {
		float above = texture(skyline_tex, UV + vec2(0.0, -2.0 / 480.0)).a;
		float n4 = texture(noise_tex, UV * 5.0 + vec2(time_s * 0.05, seed)).r;
		if (above < 0.2 && n4 > 0.6) {
			float flicker = 0.6 + 0.4 * sin(time_s * 4.4);
			col += vec3(1.0, 0.45, 0.12) * ember_amt * r * flicker;
		}
	}
	if (r < 0.5 && mid_m > 0.4) {
		col += rim_color.rgb * 0.18 * (1.0 - r);
	}
	COLOR = vec4(col, a);
}
