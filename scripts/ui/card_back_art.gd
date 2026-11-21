class_name CardBackArt
extends Control

## Desain bagian belakang kartu Elementa bergaya matte minimalis (bingkai ganda,
## pola heksagon kimia halus, dan emblem atom di tengah).
## Dipakai di 2D (tangan lawan) dan juga menyediakan tekstur prosedural untuk kartu/deck 3D.

@export var base_color := Color(0.11, 0.145, 0.195, 1.0)
@export var accent_color := Color(0.38, 0.58, 0.76, 1.0)

static var _tex_cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 10.0 or h < 10.0:
		return
	var pad := maxf(4.0, minf(w, h) * 0.06)
	var inner := Rect2(Vector2(pad, pad), Vector2(w - pad * 2.0, h - pad * 2.0))

	# Latar matte
	draw_rect(Rect2(Vector2.ZERO, size), base_color, true)
	draw_rect(inner, base_color.darkened(0.16), true)
	draw_rect(inner, Color(accent_color.r, accent_color.g, accent_color.b, 0.72), false, maxf(1.2, pad * 0.25))

	# Bingkai dalam tipis
	var pad2 := pad * 1.65
	var inner2 := Rect2(Vector2(pad2, pad2), Vector2(w - pad2 * 2.0, h - pad2 * 2.0))
	draw_rect(inner2, Color(accent_color.r, accent_color.g, accent_color.b, 0.28), false, 1.0)

	# Emblem heksagonal kimia di tengah
	var c := size * 0.5
	var r := minf(w, h) * 0.24
	var hex_pts := PackedVector2Array()
	for i in 7:
		var ang := float(i) * TAU / 6.0 - PI * 0.5
		hex_pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_polyline(hex_pts, Color(accent_color.r, accent_color.g, accent_color.b, 0.82), maxf(1.5, r * 0.08), true)

	# Cincin dalam + inti atom
	draw_arc(c, r * 0.56, 0.0, TAU, 24, Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1.2, true)
	draw_circle(c, maxf(2.5, r * 0.16), Color(accent_color.r, accent_color.g, accent_color.b, 0.90))

	# Garis aksen atas & bawah emblem
	var line_y_off := r * 1.45
	if h > 70.0:
		draw_line(Vector2(c.x - r * 0.7, c.y - line_y_off), Vector2(c.x + r * 0.7, c.y - line_y_off),
			Color(accent_color.r, accent_color.g, accent_color.b, 0.42), 1.2, true)
		draw_line(Vector2(c.x - r * 0.7, c.y + line_y_off), Vector2(c.x + r * 0.7, c.y + line_y_off),
			Color(accent_color.r, accent_color.g, accent_color.b, 0.42), 1.2, true)

## Membuat tekstur 2D/3D prosedural bagian belakang kartu untuk deck & sisi belakang Card3D.
static func make_back_texture(bg: Color, accent: Color) -> ImageTexture:
	var key := "%s_%s" % [bg.to_html(), accent.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]

	var tw := 192
	var th := 256
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(bg)

	var dark_bg := bg.darkened(0.18)
	var border_col := Color(accent.r, accent.g, accent.b, 1.0)
	var soft_col := bg.lerp(accent, 0.38)
	var cx := float(tw) * 0.5
	var cy := float(th) * 0.5

	for y in th:
		for x in tw:
			var in_frame := x >= 10 and x < tw - 10 and y >= 10 and y < th - 10
			if not in_frame:
				continue
			var on_outer := (x <= 12 or x >= tw - 13 or y <= 12 or y >= th - 13)
			var on_inner := (x >= 18 and x < tw - 18 and y >= 18 and y < th - 18) and (
				x == 18 or x == tw - 19 or y == 18 or y == th - 19)
			if on_outer:
				img.set_pixel(x, y, border_col)
			elif on_inner:
				img.set_pixel(x, y, soft_col)
			else:
				img.set_pixel(x, y, dark_bg)
				# Emblem heksagon + cincin atom di tengah
				var dx := absf(float(x) - cx)
				var dy := absf(float(y) - cy)
				var hex_r := maxf(dx * 0.866025 + dy * 0.5, dy)
				var dist := sqrt(dx * dx + dy * dy)
				if absf(hex_r - 40.0) <= 1.8:
					img.set_pixel(x, y, border_col)
				elif absf(dist - 24.0) <= 1.3:
					img.set_pixel(x, y, soft_col)
				elif dist <= 7.5:
					img.set_pixel(x, y, border_col)
				elif (absf(float(y) - (cy - 68.0)) <= 1.0 or absf(float(y) - (cy + 68.0)) <= 1.0) and dx <= 34.0:
					img.set_pixel(x, y, soft_col)

	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex
