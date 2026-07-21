shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dark_wood : source_color = vec3(0.075, 0.018, 0.012);
uniform vec3 light_wood : source_color = vec3(0.25, 0.065, 0.035);
uniform float grain_scale = 9.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float noise = hash(floor(UV * vec2(90.0, 26.0)));
	float grain = sin((UV.x + noise * 0.045 + sin(UV.y * 18.0) * 0.025) * grain_scale * 40.0);
	grain = smoothstep(-0.65, 0.85, grain);
	ALBEDO = mix(dark_wood, light_wood, grain * 0.72 + noise * 0.12);
	ROUGHNESS = 0.31 + noise * 0.12;
	METALLIC = 0.08;
}
