shader_type canvas_item;
render_mode unshaded;

uniform vec2 surface_size = vec2(1050.0, 400.0);

float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

float noise_at(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * surface_size;
	vec2 edge = surface_size * 0.5 - vec2(17.0, 17.0);
	float d = rounded_box(p, edge, edge.y * 0.91);
	float detail = noise_at(floor(p * 1.18)) - 0.5;
	float light = 1.0 - smoothstep(0.0, 0.80, length((UV - vec2(0.44, 0.34)) * vec2(1.0, 0.89)));

	vec3 rail = mix(vec3(0.080, 0.060, 0.051), vec3(0.22, 0.17, 0.12), light);
	rail += vec3(detail * 0.017 + 0.085 * smoothstep(-8.0, -1.0, d));
	vec3 brass = mix(vec3(0.28, 0.18, 0.099), vec3(0.61, 0.46, 0.25), light);
	rail = mix(rail, brass, 1.0 - smoothstep(0.6, 2.0, abs(d + 2.0)));
	rail = mix(rail, brass * 0.66, 1.0 - smoothstep(0.6, 1.7, abs(d + 21.0)));

	vec3 felt = mix(vec3(0.036, 0.146, 0.110), vec3(0.081, 0.316, 0.226), light);
	felt += vec3(detail * 0.023);
	felt *= mix(0.65, 1.0, smoothstep(24.0, 40.0, -d));
	float stitch = rounded_box(p, edge - vec2(47.0), edge.y * 0.91 - 47.0);
	felt = mix(felt, vec3(0.19, 0.41, 0.28), 0.65 * (1.0 - smoothstep(0.25, 1.28, abs(stitch))));
	vec3 table = mix(rail, felt, smoothstep(22.0, 24.0, -d));

	float mask = 1.0 - smoothstep(-0.5, 1.0, d);
	float shadow_d = rounded_box(p - vec2(0.0, 8.0), edge, edge.y * 0.91);
	float shadow = 0.70 * (1.0 - smoothstep(-2.0, 17.0, shadow_d));
	float alpha = max(mask, shadow);
	COLOR = vec4(table * mask / max(alpha, 0.001), alpha);
}
