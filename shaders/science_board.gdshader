shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Playmat meja laboratorium matte minimalis (tanpa efek neon / bloom).
uniform vec3 player_bg : source_color = vec3(0.095, 0.125, 0.165);
uniform vec3 player_line : source_color = vec3(0.28, 0.44, 0.58);
uniform vec3 opp_bg : source_color = vec3(0.160, 0.108, 0.118);
uniform vec3 opp_line : source_color = vec3(0.56, 0.32, 0.35);
uniform vec3 mid_bg : source_color = vec3(0.098, 0.138, 0.132);
uniform vec3 mid_line : source_color = vec3(0.32, 0.52, 0.46);
uniform float hex_scale = 1.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.7320508)));
	return max(c, p.x);
}

float hex_edge(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	return 0.5 - hex_dist(gv);
}

void fragment() {
	vec2 p = world_pos.xz;
	float z = p.y;

	// Wilayah dua pemain yang tenang & kontras (Steel Blue vs Warm Terracotta)
	float side_t = smoothstep(-0.75, 0.75, z);
	vec3 base_col = mix(opp_bg, player_bg, side_t);
	vec3 line_col = mix(opp_line, player_line, side_t);

	// Pita reaksi tengah (Sage Lab Slate)
	float mid_band = smoothstep(0.82, 0.52, abs(z + 0.05));
	base_col = mix(base_col, mid_bg, mid_band);
	line_col = mix(line_col, mid_line, mid_band);

	// Garis cetak halus heksagonal (seperti cetakan playmat neoprena / buku lab)
	float hx = hex_edge(p * hex_scale);
	float hex_line = smoothstep(0.022, 0.008, hx);

	// Kisi milimeter tipis ala kertas grafik laboratorium
	vec2 g = abs(fract(p * 2.0 - 0.5) - 0.5) / max(fwidth(p * 2.0), vec2(0.001));
	float graph = (1.0 - min(min(g.x, g.y), 1.0)) * 0.08;

	// Vignette lembut di tepi luar
	float vig = clamp(1.08 - length(p * vec2(0.06, 0.10)) * 0.25, 0.72, 1.0);

	float ink = clamp(hex_line * 0.18 + graph, 0.0, 0.28);
	ALBEDO = mix(base_col, line_col, ink) * vig;
	ROUGHNESS = 0.84;
	METALLIC = 0.04;
}
