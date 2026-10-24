shader_type canvas_item;
render_mode unshaded;

// Screen-space finish: split tone, vignette, faint aberration, static grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette_strength = 0.52;
uniform float vignette_inner = 0.42;
uniform float grain_amount = 0.022;
uniform float aberration = 0.0009;
uniform vec3 shadow_tint = vec3(0.88, 0.97, 1.08);
uniform vec3 highlight_tint = vec3(1.06, 1.01, 0.93);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r2 = dot(d, d);
	vec3 col;
	col.r = texture(screen_tex, uv + d * aberration * r2 * 6.0).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * aberration * r2 * 6.0).b;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.04, 0.55, luma));
	float edge = smoothstep(vignette_inner, 0.78, length(d) * 1.32);
	col *= mix(1.0 - vignette_strength, 1.0, 1.0 - edge);
	float n = fract(sin(dot(uv * vec2(1920.0, 1080.0), vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain_amount;
	COLOR = vec4(col, 1.0);
}
