shader_type spatial;
render_mode cull_disabled;
uniform sampler2D wind_noise_sampler;

uniform sampler2D albedo_sampler : source_color;
uniform sampler2D orm_sampler;
uniform sampler2D normal_sampler;
uniform vec2 wind_direction = vec2(0.9, 4.3);
uniform float wind_strength = 0.155;
uniform float wind_speed = 10.22;
uniform float gust_strength = 1.03;
uniform float gust_speed = 0.6;
uniform float vertical_sway = 0.01;
uniform float trunk_rigidity = 9.8;

void vertex() {
	// Keep the base rigid and progressively increase motion toward tips.
	float stiffness_mask = pow(clamp(UV.y, 0.0, 1.0), trunk_rigidity);
	vec2 dir = normalize(wind_direction + vec2(0.0001, 0.0));
	vec2 world_uv = NODE_POSITION_WORLD.xz * 0.35;

	float base_noise = texture(
		wind_noise_sampler,
		world_uv + dir * (TIME * wind_speed)
	).x * 2.0 - 1.0;

	float gust_noise = texture(
		wind_noise_sampler,
		world_uv * 0.65 + vec2(TIME * gust_speed, -TIME * gust_speed * 0.7)
	).x;

	float gust_factor = smoothstep(0.55, 1.0, gust_noise);
	float sway_amount = (base_noise * wind_strength + gust_factor * gust_strength) * stiffness_mask;

	VERTEX.xz += dir * sway_amount;
	VERTEX.y += sway_amount * vertical_sway * (0.5 + 0.5 * gust_factor);
}

void fragment() {
	vec4 albedo = texture(albedo_sampler, UV);
	vec3 orm = texture(orm_sampler, UV).rgb;
	vec3 normal_map = texture(normal_sampler, UV).rgb;
	
	ALBEDO = albedo.rgb * orm.r;
	ROUGHNESS = orm.g;
	NORMAL_MAP = normal_map;
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
