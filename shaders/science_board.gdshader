shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 player_bg : source_color = vec3(0.032, 0.088, 0.165);
uniform vec3 player_accent : source_color = vec3(0.14, 0.72, 1.0);
uniform vec3 opp_bg : source_color = vec3(0.155, 0.042, 0.072);
uniform vec3 opp_accent : source_color = vec3(1.0, 0.28, 0.36);
uniform vec3 mid_accent : source_color = vec3(0.18, 0.92, 0.68);
uniform float hex_scale = 1.45;
uniform float grid_scale = 2.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Jarak ke tepi kisi heksagonal (pola molekul / sarang lebah kimia)
float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.7320508)));
	return max(c, p.x);
}

vec2 hex_edge(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	float d = 0.5 - hex_dist(gv);
	float center_dot = smoothstep(0.08, 0.03, length(gv));
	return vec2(d, center_dot);
}

// Cincin orbital atom halus pada permukaan papan
float orbital_ring(vec2 p, vec2 center, float radius, float thickness) {
	float d = abs(length(p - center) - radius);
	return smoothstep(thickness, 0.0, d);
}

void fragment() {
	vec2 p = world_pos.xz;
	float z = p.y;

	// Transisi warna wilayah: Lawan (z < 0, merah/crimson) vs Pemain (z > 0, biru/cyan)
	float side_t = smoothstep(-1.1, 1.1, z);
	vec3 base_col = mix(opp_bg, player_bg, side_t);
	vec3 accent_col = mix(opp_accent, player_accent, side_t);

	// Pita reaksi di tengah (z ~ -0.05) bernuansa hijau-teal
	float mid_band = exp(-pow((z + 0.05) * 1.15, 2.0));
	base_col = mix(base_col, vec3(0.03, 0.12, 0.12), mid_band * 0.72);
	accent_col = mix(accent_col, mid_accent, mid_band * 0.85);

	// Kisi heksagonal kimia (benzene / molecular lattice)
	vec2 hx = hex_edge(p * hex_scale);
	float hex_line = smoothstep(0.042, 0.012, hx.x);
	float hex_node = hx.y;

	// Kisi blueprint laboratorium tipis
	vec2 g = abs(fract(p * grid_scale - 0.5) - 0.5) / fwidth(p * grid_scale);
	float fine_grid = 1.0 - min(min(g.x, g.y), 1.0);
	fine_grid *= 0.14;

	// Cincin orbital atom besar di wilayah masing-masing pemain
	float orb_me = orbital_ring(p, vec2(0.35, 2.35), 2.85, 0.045)
		+ orbital_ring(p, vec2(0.35, 2.35), 4.15, 0.035) * 0.65;
	float orb_opp = orbital_ring(p, vec2(0.35, -2.45), 2.85, 0.045)
		+ orbital_ring(p, vec2(0.35, -2.45), 4.15, 0.035) * 0.65;
	float orbitals = clamp(orb_me + orb_opp, 0.0, 1.0);

	// Gelombang energi halus bergerak dari tengah ke kedua sisi
	float wave = 0.5 + 0.5 * sin(abs(z + 0.05) * 2.2 - TIME * 1.4);
	float pulse = mix(0.65, 1.0, wave);

	// Vignette halus di luar area arena agar fokus tetap ke kartu
	float dist_arena = length(p * vec2(0.075, 0.125));
	float vignette = clamp(1.18 - dist_arena * 0.42, 0.45, 1.0);

	float pattern = hex_line * 0.36 * pulse + hex_node * 0.18 + fine_grid + orbitals * 0.45;
	vec3 final_albedo = base_col * vignette + accent_col * pattern * 0.35;
	vec3 final_emission = accent_col * (hex_line * 0.16 * pulse + orbitals * 0.32 + mid_band * hex_line * 0.25);

	ALBEDO = final_albedo;
	EMISSION = final_emission;
	ROUGHNESS = mix(0.66, 0.34, clamp(hex_line + orbitals, 0.0, 1.0));
	METALLIC = mix(0.14, 0.42, clamp(hex_line + orbitals, 0.0, 1.0));
}
