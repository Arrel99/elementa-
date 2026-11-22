shader_type canvas_item;

// Latar Main Menu matte minimalis bergaya buku laboratorium modern (tanpa neon).
// Dengan pergeseran kisi heksagonal & gradasi cahaya lembut yang hidup.
uniform vec3 bg_base : source_color = vec3(0.082, 0.098, 0.122);
uniform vec3 bg_slate_blue : source_color = vec3(0.122, 0.162, 0.212);
uniform vec3 bg_terracotta : source_color = vec3(0.168, 0.115, 0.126);
uniform vec3 bg_sage : source_color = vec3(0.105, 0.148, 0.142);
uniform vec3 ink_line : source_color = vec3(0.30, 0.39, 0.48);

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

	// Pergerakan sangat halus pada pusat gradasi matte (terasa hidup tapi tenang)
	float t = TIME * 0.22;
	vec2 blue_pos = vec2(-0.56 + sin(t) * 0.08, 0.32 + cos(t * 0.8) * 0.07);
	vec2 red_pos  = vec2( 0.58 + cos(t * 0.9) * 0.08, -0.30 + sin(t * 0.7) * 0.07);
	vec2 sage_pos = vec2( sin(t * 0.6) * 0.18, -0.45 + cos(t * 0.5) * 0.06);

	float blue_w = exp(-length(p - blue_pos) * 1.35);
	float red_w  = exp(-length(p - red_pos) * 1.45);
	float sage_w = exp(-length(p - sage_pos) * 1.75);

	vec3 col = bg_base;
	col = mix(col, bg_slate_blue, blue_w * 0.62);
	col = mix(col, bg_terracotta, red_w * 0.52);
	col = mix(col, bg_sage, sage_w * 0.36);

	// Cetakan kisi heksagonal tipis yang meluncur pelan secara diagonal
	vec2 drift_p = p * 6.2 + vec2(TIME * 0.055, -TIME * 0.032);
	float hx = hex_edge(drift_p);
	float hex_line = smoothstep(0.024, 0.008, hx);
	float wave = 0.75 + 0.25 * sin(p.x * 2.2 - p.y * 1.6 + TIME * 0.65);
	col = mix(col, ink_line, hex_line * 0.16 * wave);

	// Vignette lembut
	float vig = clamp(1.06 - length(p) * 0.28, 0.70, 1.0);
	COLOR = vec4(col * vig, 1.0);
}
