extends Control

## Dekorasi sains minimalis bergaya poster tabel periodik modern.
## Garis tipis tenang di sisi kiri/kanan latar Main Menu tanpa efek neon.

const LINE_BLUE := Color(0.45, 0.62, 0.78, 0.22)
const LINE_RED := Color(0.76, 0.48, 0.50, 0.22)
const LINE_SAGE := Color(0.48, 0.70, 0.64, 0.22)

const ELEMENTS := [
	{"sym": "H", "num": "1", "rx": 0.11, "ry": 0.24, "col": LINE_BLUE},
	{"sym": "O", "num": "8", "rx": 0.18, "ry": 0.48, "col": LINE_SAGE},
	{"sym": "Na", "num": "11", "rx": 0.11, "ry": 0.74, "col": LINE_BLUE},
	{"sym": "C", "num": "6", "rx": 0.89, "ry": 0.24, "col": LINE_RED},
	{"sym": "Fe", "num": "26", "rx": 0.82, "ry": 0.50, "col": LINE_RED},
	{"sym": "Ne", "num": "10", "rx": 0.89, "ry": 0.76, "col": LINE_SAGE},
]

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var s := clampf(minf(w / 1920.0, h / 1080.0), 0.45, 1.25)
	var font := ThemeDB.fallback_font

	# Garis struktural tipis di sisi kiri & kanan (menghubungkan ubin unsur)
	draw_line(Vector2(w * 0.11, h * 0.24), Vector2(w * 0.18, h * 0.48), LINE_BLUE, 1.2, true)
	draw_line(Vector2(w * 0.18, h * 0.48), Vector2(w * 0.11, h * 0.74), LINE_BLUE, 1.2, true)
	draw_line(Vector2(w * 0.89, h * 0.24), Vector2(w * 0.82, h * 0.50), LINE_RED, 1.2, true)
	draw_line(Vector2(w * 0.82, h * 0.50), Vector2(w * 0.89, h * 0.76), LINE_RED, 1.2, true)

	# Ubin unsur tabel periodik datar & bersih
	for el in ELEMENTS:
		var center := Vector2(w * float(el.rx), h * float(el.ry))
		_draw_element_tile(font, center, 66.0 * s, el.num, el.sym, el.col)

func _draw_element_tile(font: Font, center: Vector2, tile_sz: float,
		atomic_num: String, symbol: String, col: Color) -> void:
	var rect := Rect2(center - Vector2(tile_sz, tile_sz) * 0.5, Vector2(tile_sz, tile_sz))
	draw_rect(rect, Color(0.09, 0.11, 0.14, 0.75), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.42), false, 1.5)

	var num_sz := maxi(10, int(tile_sz * 0.20))
	var sym_sz := maxi(14, int(tile_sz * 0.40))
	draw_string(font, rect.position + Vector2(7.0, num_sz + 4.0), atomic_num,
		HORIZONTAL_ALIGNMENT_LEFT, -1, num_sz, Color(col.r, col.g, col.b, 0.75))
	draw_string(font, Vector2(rect.position.x, center.y + sym_sz * 0.36), symbol,
		HORIZONTAL_ALIGNMENT_CENTER, tile_sz, sym_sz, Color(0.86, 0.90, 0.94, 0.52))
