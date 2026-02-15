shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.03, 0.20, 0.42, 0.78);
uniform vec4 shallow_color : source_color = vec4(0.09, 0.55, 0.78, 0.70);
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.08;
uniform float fresnel_strength : hint_range(0.0, 4.0) = 1.8;

// Valeurs volontairement visibles pour valider l'animation.
uniform float wave_height : hint_range(0.0, 3.0) = 0.55;
uniform float wave_speed : hint_range(0.0, 8.0) = 2.2;
uniform float wave_tiling : hint_range(0.1, 32.0) = 8.0;
uniform float choppy_strength : hint_range(0.0, 1.0) = 0.25;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.15;
uniform float normal_detail : hint_range(0.1, 8.0) = 2.2;
uniform float normal_speed : hint_range(0.0, 6.0) = 1.4;

varying vec3 world_pos;
varying float wave_mix;

float wave_height_at(vec2 p, float t) {
	float w1 = sin(p.x * 1.7 + t);
	float w2 = cos(p.y * 2.3 - t * 1.15);
	float w3 = sin((p.x + p.y) * 1.2 + t * 0.7);
	return (w1 * 0.5 + w2 * 0.35 + w3 * 0.15) * wave_height;
}

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = UV * wave_tiling;
	float w1 = sin(p.x * 1.7 + t);
	float w2 = cos(p.y * 2.3 - t * 1.15);
	float h = wave_height_at(p, t);
	VERTEX.y += h;

	// Légère dérive latérale pour effet de vague "cassée".
	VERTEX.x += w2 * choppy_strength * 0.03;
	VERTEX.z += w1 * choppy_strength * 0.03;

	wave_mix = clamp(h / max(wave_height, 0.001) * 0.5 + 0.5, 0.0, 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = UV * wave_tiling;
	float eps = 0.02;
	float h = wave_height_at(p, t);
	float hx = wave_height_at(p + vec2(eps, 0.0), t) - h;
	float hy = wave_height_at(p + vec2(0.0, eps), t) - h;

	// Détail secondaire animé pour casser les reflets trop lisses.
	float dt = TIME * normal_speed;
	float d1 = sin((p.x + dt) * 5.5 * normal_detail) * cos((p.y - dt * 0.8) * 4.7 * normal_detail);
	float d2 = cos((p.x * 0.7 - dt * 0.6) * 7.2 * normal_detail) * sin((p.y * 1.1 + dt) * 6.4 * normal_detail);
	float dx = hx + (d1 + d2 * 0.6) * 0.03;
	float dy = hy + (d2 - d1 * 0.5) * 0.03;
	vec3 tangent_normal = normalize(vec3(-dx * normal_strength, -dy * normal_strength, 1.0));
	NORMAL_MAP = tangent_normal * 0.5 + 0.5;

	float height_mix = clamp((world_pos.y + 6.0) / 12.0, 0.0, 1.0) * 0.6 + wave_mix * 0.4;
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, height_mix);

	float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	vec3 final_color = base + vec3(0.22, 0.33, 0.45) * fresnel * fresnel_strength;

	ALBEDO = final_color;
	METALLIC = metallic_amount;
	ROUGHNESS = max(0.02, roughness_amount - 0.03);
	SPECULAR = 0.95;
	ALPHA = mix(deep_color.a, shallow_color.a, fresnel * 0.7);
}
