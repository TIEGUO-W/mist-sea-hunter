shader_type canvas_item;
render_mode unshaded;

// Left-weighted scrim so the briefing text sits on darkness while the
// encounter stays visible on the right.
uniform float strength = 0.90;
uniform vec3 tint = vec3(0.006, 0.011, 0.017);

void fragment() {
	float horizontal = smoothstep(0.62, 0.06, UV.x);
	float vertical = smoothstep(0.98, 0.42, UV.y) * 0.62;
	COLOR = vec4(tint, clamp(horizontal + vertical, 0.0, 1.0) * strength);
}
