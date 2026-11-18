shader_type canvas_item;
render_mode unshaded;

// Dawn / dusk grade. grad_a is the start strip, grad_b the end strip.
// Both are 4×800 stretched full-frame; sample the vertical axis only.
uniform sampler2D grad_a : filter_linear, repeat_disable;
uniform sampler2D grad_b : filter_linear, repeat_disable;
uniform sampler2D clouds : filter_linear, repeat_enable;
uniform float light = 1.0;
uniform float rays = 0.0;
uniform float time_s = 0.0;
uniform float cloud_alpha = 0.35;
uniform vec2 sun_uv = vec2(0.789, 0.709);
uniform vec4 sun_color : source_color = vec4(1.0, 0.78, 0.45, 1.0);

void fragment() {
	vec3 a = texture(grad_a, vec2(0.5, UV.y)).rgb;
	vec3 b = texture(grad_b, vec2(0.5, UV.y)).rgb;
	float k = clamp(light, 0.0, 1.0);
	vec3 col = mix(a, b, k);
	vec2 cuv = UV * vec2(1.6, 1.0) + vec2(time_s * 0.012, 0.0);
	float n = texture(clouds, cuv).r;
	float cloud = smoothstep(0.52, 0.72, n);
	cloud *= smoothstep(0.62, 0.28, UV.y);
	col = mix(col, col + vec3(0.10, 0.07, 0.04), cloud * cloud_alpha);
	float d = distance(UV, sun_uv);
	col += sun_color.rgb * exp(-d * 7.5) * k * 0.55;
	float ang = atan(UV.y - sun_uv.y, UV.x - sun_uv.x);
	float ray = pow(max(cos(ang * 7.0), 0.0), 10.0) * exp(-d * 2.4);
	col += vec3(1.0, 0.90, 0.70) * ray * rays * k * 0.40;
	COLOR = vec4(col, 1.0);
}
