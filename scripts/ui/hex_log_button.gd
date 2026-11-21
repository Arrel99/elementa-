extends Control

## Tombol heksagonal minimalis untuk membuka Battle Log (gaya Pokemon TCG Live).
## Diletakkan tepat di bawah panel skor & jam pertandingan.

signal pressed

var _hovered := false
var _down := false

func _ready() -> void:
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	tooltip_text = "Buka Battle Log"
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; _down = false; queue_redraw())

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			pressed.emit()
		accept_event()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var pts := PackedVector2Array()
	for i in 6:
		var ang := float(i) * TAU / 6.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)

	var fill := Color(0.14, 0.18, 0.24, 0.96)
	var border := Color(0.36, 0.54, 0.72, 1.0)
	if _down:
		fill = Color(0.11, 0.14, 0.19, 1.0)
	elif _hovered:
		fill = Color(0.19, 0.25, 0.33, 1.0)
		border = Color(0.56, 0.76, 0.92, 1.0)

	draw_colored_polygon(pts, fill)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, border, 2.5, true)

	# Ikon daftar Battle Log + kaca pembesar kecil (gaya Pokemon TCG Live)
	var ink := Color(0.92, 0.95, 0.98, 1.0)
	var box := Rect2(c.x - r * 0.34, c.y - r * 0.36, r * 0.56, r * 0.68)
	draw_rect(box, ink, false, 2.0)
	for row in 3:
		var y := box.position.y + r * (0.16 + float(row) * 0.18)
		draw_line(Vector2(box.position.x + 6.0, y), Vector2(box.end.x - 6.0, y), ink, 2.0, true)

	# Lingkaran kaca pembesar di kanan bawah ikon
	var glass_c := Vector2(box.end.x + 1.0, box.end.y - 2.0)
	draw_circle(glass_c, r * 0.16, fill)
	draw_arc(glass_c, r * 0.16, 0.0, TAU, 18, ink, 2.0, true)
	draw_line(glass_c + Vector2(r * 0.11, r * 0.11), glass_c + Vector2(r * 0.24, r * 0.24), ink, 2.4, true)
