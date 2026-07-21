shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 gold_color : source_color = vec3(0.78, 0.49, 0.11);
uniform float polish : hint_range(0.0, 1.0) = 0.72;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 951.135);
}

void fragment() {
	float scratches = step(0.985, hash(vec2(UV.x * 80.0, floor(UV.y * 520.0))));
	ALBEDO = gold_color * (0.78 + 0.22 * hash(floor(UV * 190.0)));
	METALLIC = 0.94;
	ROUGHNESS = mix(0.38, 0.16, polish) + scratches * 0.18;
}
