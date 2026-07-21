shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.58;
uniform vec4 tint : source_color = vec4(0.012, 0.025, 0.018, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= 0.72;
	float edge = smoothstep(0.28, 1.05, length(uv));
	COLOR = vec4(tint.rgb, edge * strength);
}
