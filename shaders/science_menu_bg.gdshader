shader_type canvas_item;

// Latar Main Menu matte minimalis bergaya buku laboratorium modern (tanpa neon).
uniform vec3 bg_base : source_color = vec3(0.082, 0.098, 0.122);
uniform vec3 bg_slate_blue : source_color = vec3(0.115, 0.150, 0.195);
uniform vec3 bg_terracotta : source_color = vec3(0.155, 0.108, 0.118);
uniform vec3 ink_line : source_color = vec3(0.28, 0.36, 0.44);

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
	vec2 res = vec2(1.0) / SCREEN_PIXEL_SIZE;
	float aspect = res.x / max(res.y, 1.0);
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);

	// Gradasi matte sangat halus antara biru baja & terakota redup
	float blue_w = exp(-length(p - vec2(-0.55, 0.35)) * 1.4);
	float red_w = exp(-length(p - vec2(0.58, -0.35)) * 1.5);
	vec3 col = bg_base;
	col = mix(col, bg_slate_blue, blue_w * 0.55);
	col = mix(col, bg_terracotta, red_w * 0.45);

	// Cetakan kisi heksagonal tipis & tenang (statis, tanpa gelombang neon)
	float hx = hex_edge(p * 6.5);
	float hex_line = smoothstep(0.024, 0.008, hx);
	col = mix(col, ink_line, hex_line * 0.14);

	// Vignette lembut
	float vig = clamp(1.05 - length(p) * 0.28, 0.72, 1.0);
	COLOR = vec4(col * vig, 1.0);
}
