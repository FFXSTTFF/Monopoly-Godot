shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.025, 0.16, 0.095);
uniform vec3 fiber_color : source_color = vec3(0.055, 0.28, 0.16);
uniform float fiber_scale = 170.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float fine = hash(UV * fiber_scale);
	float weave = sin(UV.x * 620.0) * sin(UV.y * 570.0) * 0.5 + 0.5;
	float fibers = mix(fine, weave, 0.34);
	float edge = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0);
	ALBEDO = mix(base_color, fiber_color, fibers * 0.22 + edge * 0.16);
	ROUGHNESS = 0.91 - fibers * 0.08;
	METALLIC = 0.0;
}
