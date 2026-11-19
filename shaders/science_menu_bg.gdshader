shader_type canvas_item;

uniform vec3 bg_deep : source_color = vec3(0.024, 0.045, 0.082);
uniform vec3 glow_cyan : source_color = vec3(0.14, 0.72, 1.0);
uniform vec3 glow_emerald : source_color = vec3(0.20, 0.92, 0.68);
uniform vec3 glow_crimson : source_color = vec3(0.95, 0.28, 0.38);

float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.7320508)));
	return max(c, p.x);
}

vec2 hex_grid(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	float edge = 0.5 - hex_dist(gv);
	float node = smoothstep(0.09, 0.03, length(gv));
	return vec2(edge, node);
}

float ring(vec2 p, vec2 center, float radius, float width) {
	return smoothstep(width, 0.0, abs(length(p - center) - radius));
}

void fragment() {
	vec2 res = vec2(1.0) / SCREEN_PIXEL_SIZE;
	float aspect = res.x / max(res.y, 1.0);
	vec2 uv = UV;
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

	// Latar gradien laboratorium dua warna (biru-cyan kiri-bawah vs crimson kanan-atas)
	float cyan_field = exp(-length(p - vec2(-0.55, 0.35)) * 1.45);
	float crimson_field = exp(-length(p - vec2(0.62, -0.35)) * 1.55);
	float mid_field = exp(-length(p) * 1.7);

	vec3 col = bg_deep;
	col += glow_cyan * cyan_field * 0.16;
	col += glow_crimson * crimson_field * 0.13;
	col += glow_emerald * mid_field * 0.09;

	// Kisi heksagonal molekul bergerak super halus
	vec2 hx = hex_grid(p * 7.5 + vec2(TIME * 0.06, -TIME * 0.04));
	float hex_line = smoothstep(0.045, 0.012, hx.x);
	float hex_node = hx.y;

	// Gelombang energi diagonal halus
	float wave = 0.5 + 0.5 * sin((p.x * 2.4 - p.y * 1.8) * 2.5 - TIME * 1.2);
	vec3 line_col = mix(glow_cyan, glow_emerald, wave * 0.65);
	line_col = mix(line_col, glow_crimson, crimson_field * 0.75);

	col += line_col * hex_line * (0.14 + 0.10 * wave);
	col += line_col * hex_node * 0.10;

	// Cincin orbital atom raksasa di kiri & kanan layar
	float r1 = ring(p, vec2(-0.62, 0.02), 0.34, 0.004) + ring(p, vec2(-0.62, 0.02), 0.46, 0.003) * 0.65;
	float r2 = ring(p, vec2(0.62, 0.02), 0.34, 0.004) + ring(p, vec2(0.62, 0.02), 0.46, 0.003) * 0.65;
	col += glow_cyan * r1 * 0.30;
	col += glow_crimson * r2 * 0.26;

	// Vignette halus supaya panel menu di tengah tetap kontras dan tajam
	float vig = clamp(1.12 - length(p) * 0.48, 0.42, 1.0);
	col *= vig;

	COLOR = vec4(col, 1.0);
}
