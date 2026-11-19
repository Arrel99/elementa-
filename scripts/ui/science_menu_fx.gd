extends Control

## Elemen dekorasi sains/kimia 2D untuk latar Main Menu:
## orbit elektron berputar & ubin unsur periodik mengambang halus di sisi kiri/kanan.

const COLOR_CYAN := Color(0.22, 0.78, 1.0, 0.55)
const COLOR_CRIMSON := Color(1.0, 0.36, 0.44, 0.50)
const COLOR_EMERALD := Color(0.26, 0.94, 0.70, 0.55)

const ELEMENTS := [
	{"sym": "H", "num": "1", "rx": 0.11, "ry": 0.22, "col": COLOR_CYAN, "phase": 0.0},
	{"sym": "O", "num": "8", "rx": 0.17, "ry": 0.48, "col": COLOR_EMERALD, "phase": 1.3},
	{"sym": "Na", "num": "11", "rx": 0.10, "ry": 0.76, "col": COLOR_CYAN, "phase": 2.4},
	{"sym": "C", "num": "6", "rx": 0.89, "ry": 0.24, "col": COLOR_CRIMSON, "phase": 0.7},
	{"sym": "Fe", "num": "26", "rx": 0.83, "ry": 0.52, "col": COLOR_CRIMSON, "phase": 1.9},
	{"sym": "Ne", "num": "10", "rx": 0.90, "ry": 0.78, "col": COLOR_EMERALD, "phase": 3.1},
]

var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var s := clampf(minf(w / 1920.0, h / 1080.0), 0.45, 1.25)

	# Orbit atom kiri (biru-cyan) & kanan (merah-crimson)
	_draw_atom(Vector2(w * 0.14, h * 0.50), 145.0 * s, COLOR_CYAN, 1.0)
	_draw_atom(Vector2(w * 0.86, h * 0.50), 145.0 * s, COLOR_CRIMSON, -0.88)

	# Ubin unsur tabel periodik mengambang halus
	var font := ThemeDB.fallback_font
	for el in ELEMENTS:
		var phase: float = el.phase
		var bob := sin(_t * 1.15 + phase) * 8.0 * s
		var center := Vector2(w * float(el.rx), h * float(el.ry) + bob)
		_draw_element_tile(font, center, 68.0 * s, el.num, el.sym, el.col)

func _draw_atom(center: Vector2, radius: float, col: Color, dir: float) -> void:
	# Inti atom
	draw_circle(center, radius * 0.08, Color(col.r, col.g, col.b, 0.45))
	draw_circle(center, radius * 0.045, Color(1.0, 1.0, 1.0, 0.7))

	# 3 orbit elips miring + elektron yang mengorbit
	var angles := [0.25, -0.55, 1.15]
	for i in angles.size():
		var rot: float = angles[i] + _t * 0.12 * dir
		var pts := PackedVector2Array()
		var segs := 48
		for k in segs + 1:
			var a := float(k) * TAU / float(segs)
			var local := Vector2(cos(a) * radius, sin(a) * radius * 0.36)
			pts.append(center + local.rotated(rot))
		draw_polyline(pts, Color(col.r, col.g, col.b, 0.28), 2.0, true)

		# Elektron
		var ea := _t * (1.2 + float(i) * 0.35) * dir + float(i) * 2.1
		var e_pos := center + Vector2(cos(ea) * radius, sin(ea) * radius * 0.36).rotated(rot)
		draw_circle(e_pos, 5.5, Color(col.r, col.g, col.b, 0.55))
		draw_circle(e_pos, 3.0, Color(0.95, 0.99, 1.0, 0.95))

func _draw_element_tile(font: Font, center: Vector2, tile_sz: float,
		atomic_num: String, symbol: String, col: Color) -> void:
	var rect := Rect2(center - Vector2(tile_sz, tile_sz) * 0.5, Vector2(tile_sz, tile_sz))
	draw_rect(rect, Color(0.03, 0.06, 0.11, 0.62), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 2.0)

	var num_sz := maxi(10, int(tile_sz * 0.20))
	var sym_sz := maxi(14, int(tile_sz * 0.42))
	draw_string(font, rect.position + Vector2(7.0, num_sz + 4.0), atomic_num,
		HORIZONTAL_ALIGNMENT_LEFT, -1, num_sz, Color(col.r, col.g, col.b, 0.85))
	draw_string(font, Vector2(rect.position.x, center.y + sym_sz * 0.38), symbol,
		HORIZONTAL_ALIGNMENT_CENTER, tile_sz, sym_sz, Color(0.92, 0.97, 1.0, 0.88))
