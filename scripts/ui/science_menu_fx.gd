extends Control

## Animasi latar Main Menu bergaya laboratorium sains minimalis:
## - 6 kartu Elementa full-art melayang halus di sisi kiri & kanan dengan bayangan,
##   paralaks kursor lembut, dan rotasi pergantian kartu berkala (efek flip 2D).
## - Ubin unsur tabel periodik mengambang perlahan dengan garis ikatan & partikel kecil.

const LINE_BLUE := Color(0.45, 0.62, 0.78, 0.26)
const LINE_RED := Color(0.76, 0.48, 0.50, 0.26)
const LINE_SAGE := Color(0.48, 0.70, 0.64, 0.26)

const ELEMENTS := [
	{"sym": "H",  "num": "1",  "rx": 0.07, "ry": 0.16, "col": LINE_BLUE, "phase": 0.0},
	{"sym": "O",  "num": "8",  "rx": 0.25, "ry": 0.86, "col": LINE_SAGE, "phase": 1.3},
	{"sym": "Na", "num": "11", "rx": 0.06, "ry": 0.84, "col": LINE_BLUE, "phase": 2.4},
	{"sym": "C",  "num": "6",  "rx": 0.93, "ry": 0.16, "col": LINE_RED,  "phase": 0.8},
	{"sym": "Fe", "num": "26", "rx": 0.75, "ry": 0.86, "col": LINE_RED,  "phase": 2.1},
	{"sym": "Ne", "num": "10", "rx": 0.94, "ry": 0.84, "col": LINE_SAGE, "phase": 3.5},
]

# Slot kartu melayang di kiri & kanan agar membingkai panel menu tanpa menutupinya
const CARD_SLOTS := [
	# Sisi Kiri
	{"rx": 0.15, "ry": 0.30, "rot": -11.0, "scale": 1.00, "depth": 1.0, "phase": 0.0, "init_id": "H2O"},
	{"rx": 0.22, "ry": 0.56, "rot":   7.5, "scale": 0.92, "depth": 0.7, "phase": 1.8, "init_id": "C"},
	{"rx": 0.12, "ry": 0.66, "rot":  -6.5, "scale": 0.84, "depth": 0.5, "phase": 3.4, "init_id": "katalis"},
	# Sisi Kanan
	{"rx": 0.85, "ry": 0.30, "rot":  10.5, "scale": 1.00, "depth": 1.0, "phase": 0.9, "init_id": "NaCl"},
	{"rx": 0.78, "ry": 0.56, "rot":  -8.0, "scale": 0.92, "depth": 0.7, "phase": 2.6, "init_id": "Fe"},
	{"rx": 0.88, "ry": 0.66, "rot":   6.0, "scale": 0.84, "depth": 0.5, "phase": 4.2, "init_id": "spektrometer"},
]

const CARD_BASE_SIZE := Vector2(154.0, 214.0)

var _time := 0.0
var _mouse_offset := Vector2.ZERO
var _mouse_smooth := Vector2.ZERO
var _card_nodes: Array[Dictionary] = []
var _all_card_ids: Array[String] = []
var _swap_timer := 0.0
var _swap_cursor := 0
var _particles: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_collect_card_ids()
	_init_particles()
	_spawn_floating_cards()

func _collect_card_ids() -> void:
	_all_card_ids.clear()
	for cid in CardDB.cards:
		var d: CardData = CardDB.cards[cid]
		if d != null and d.art != null:
			_all_card_ids.append(String(cid))
	_all_card_ids.shuffle()

func _init_particles() -> void:
	_particles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4201
	for i in 22:
		_particles.append({
			"rx": rng.randf(),
			"ry": rng.randf(),
			"speed": rng.randf_range(0.012, 0.030),
			"rad": rng.randf_range(1.6, 3.6),
			"phase": rng.randf_range(0.0, TAU),
			"alpha": rng.randf_range(0.10, 0.24),
			"col_i": i % 3,
		})

func _spawn_floating_cards() -> void:
	for info in _card_nodes:
		if is_instance_valid(info.root):
			info.root.queue_free()
	_card_nodes.clear()

	for i in CARD_SLOTS.size():
		var slot: Dictionary = CARD_SLOTS[i]
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		# Bayangan matte lembut di belakang kartu
		var shadow := Panel.new()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh_style := StyleBoxFlat.new()
		sh_style.bg_color = Color(0.02, 0.03, 0.05, 0.42)
		sh_style.set_corner_radius_all(12)
		shadow.add_theme_stylebox_override("panel", sh_style)
		root.add_child(shadow)

		# Bingkai matte tipis
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fr_style := StyleBoxFlat.new()
		fr_style.bg_color = Color(0.10, 0.12, 0.15, 0.96)
		fr_style.border_color = Color(0.32, 0.42, 0.52, 0.55)
		fr_style.set_border_width_all(2)
		fr_style.set_corner_radius_all(10)
		fr_style.set_content_margin_all(3)
		frame.add_theme_stylebox_override("panel", fr_style)
		root.add_child(frame)

		var tex_rect := TextureRect.new()
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		frame.add_child(tex_rect)

		var cid := String(slot.init_id)
		var d: CardData = CardDB.get_card(cid)
		if d != null and d.art != null:
			tex_rect.texture = d.art

		# Animasi masuk halus bergelombang saat membuka Main Menu
		root.modulate.a = 0.0
		var tw := root.create_tween()
		tw.tween_interval(0.12 + float(i) * 0.09)
		tw.tween_property(root, "modulate:a", 0.72 if slot.depth < 0.8 else 0.88, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		_card_nodes.append({
			"root": root,
			"shadow": shadow,
			"frame": frame,
			"tex": tex_rect,
			"slot": slot,
			"cid": cid,
			"flip_x": 1.0,
		})

	_on_resized()

func _on_resized() -> void:
	var s := _ui_scale()
	for info in _card_nodes:
		var slot: Dictionary = info.slot
		var sz := (CARD_BASE_SIZE * s * float(slot.scale)).round()
		var root: Control = info.root
		var shadow: Control = info.shadow
		var frame: Control = info.frame
		root.size = sz
		root.pivot_offset = sz * 0.5
		shadow.size = sz
		shadow.position = Vector2(8.0, 14.0) * s
		frame.size = sz
		frame.position = Vector2.ZERO
	queue_redraw()

func _ui_scale() -> float:
	return clampf(minf(size.x / 1920.0, size.y / 1080.0), 0.48, 1.25)

func _process(delta: float) -> void:
	_time += delta

	# Paralaks sangat lembut mengikuti kursor
	if size.x > 10.0 and size.y > 10.0:
		var mp := get_local_mouse_position()
		_mouse_offset = Vector2((mp.x / size.x) - 0.5, (mp.y / size.y) - 0.5)
	_mouse_smooth = _mouse_smooth.lerp(_mouse_offset, clampf(delta * 4.5, 0.0, 1.0))

	var s := _ui_scale()
	for info in _card_nodes:
		var root: Control = info.root
		var slot: Dictionary = info.slot
		var ph := float(slot.phase)
		var depth := float(slot.depth)
		var base_pos := Vector2(size.x * float(slot.rx), size.y * float(slot.ry)) - root.size * 0.5
		var bob := Vector2(
			sin(_time * 0.65 + ph) * 7.0 * s,
			cos(_time * 0.90 + ph * 1.2) * 11.0 * s
		)
		var parallax := -_mouse_smooth * Vector2(26.0, 18.0) * depth * s
		root.position = base_pos + bob + parallax
		root.rotation_degrees = float(slot.rot) + sin(_time * 0.72 + ph) * 2.4
		root.scale = Vector2(float(info.flip_x), 1.0)

	# Setiap 3.8 detik, satu kartu showcase berbalik halus menampilkan kartu Elementa lain
	_swap_timer += delta
	if _swap_timer >= 3.8 and _all_card_ids.size() > CARD_SLOTS.size():
		_swap_timer = 0.0
		_flip_next_card()

	# Perbarui partikel mikro yang naik perlahan
	for p in _particles:
		p.ry -= float(p.speed) * delta
		if p.ry < -0.04:
			p.ry = 1.04

	queue_redraw()

func _flip_next_card() -> void:
	if _card_nodes.is_empty():
		return
	var idx := _swap_cursor % _card_nodes.size()
	_swap_cursor += 1
	var info: Dictionary = _card_nodes[idx]
	var used := {}
	for other in _card_nodes:
		used[String(other.cid)] = true
	var next_id := ""
	for cid in _all_card_ids:
		if not used.has(cid):
			next_id = cid
			break
	if next_id == "":
		return
	var d: CardData = CardDB.get_card(next_id)
	if d == null or d.art == null:
		return

	info.cid = next_id
	var root: Control = info.root
	var tex: TextureRect = info.tex
	var tw := root.create_tween()
	tw.tween_method(func(v: float): info.flip_x = v, 1.0, 0.02, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): tex.texture = d.art)
	tw.tween_method(func(v: float): info.flip_x = v, 0.02, 1.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 100.0 or h < 100.0:
		return
	var s := _ui_scale()
	var font := ThemeDB.fallback_font

	# Partikel molekul lembut yang naik perlahan di latar
	var p_cols := [LINE_BLUE, LINE_SAGE, LINE_RED]
	for p in _particles:
		var px := float(p.rx) * w + sin(_time * 0.8 + float(p.phase)) * 12.0 * s
		var py := float(p.ry) * h
		var c: Color = p_cols[int(p.col_i)]
		c.a = float(p.alpha)
		draw_circle(Vector2(px, py), float(p.rad) * s, c)

	# Hitung posisi ubin unsur yang mengambang perlahan
	var pts: Array[Vector2] = []
	for el in ELEMENTS:
		var ph := float(el.phase)
		var base := Vector2(w * float(el.rx), h * float(el.ry))
		var drift := Vector2(cos(_time * 0.55 + ph) * 5.0 * s, sin(_time * 0.85 + ph) * 7.0 * s)
		pts.append(base + drift - _mouse_smooth * 10.0 * s)

	# Garis ikatan kimia tipis + titik ikatan berjalan halus di antara ubin
	var bonds := [[0, 2, LINE_BLUE], [2, 1, LINE_SAGE], [3, 5, LINE_RED], [5, 4, LINE_SAGE]]
	for b in bonds:
		var a: Vector2 = pts[int(b[0])]
		var c_pt: Vector2 = pts[int(b[1])]
		var col: Color = b[2]
		draw_line(a, c_pt, Color(col.r, col.g, col.b, 0.22), 1.3, true)
		var prog := fmod(_time * 0.18 + float(int(b[0])) * 0.27, 1.0)
		var dot_pos := a.lerp(c_pt, prog)
		draw_circle(dot_pos, 3.0 * s, Color(col.r, col.g, col.b, 0.55))

	# Ubin unsur tabel periodik datar & bersih
	for i in ELEMENTS.size():
		var el: Dictionary = ELEMENTS[i]
		_draw_element_tile(font, pts[i], 58.0 * s, el.num, el.sym, el.col)

func _draw_element_tile(font: Font, center: Vector2, tile_sz: float,
		atomic_num: String, symbol: String, col: Color) -> void:
	var rect := Rect2(center - Vector2(tile_sz, tile_sz) * 0.5, Vector2(tile_sz, tile_sz))
	draw_rect(rect, Color(0.09, 0.11, 0.14, 0.72), true)
	draw_rect(rect, Color(col.r, col.g, col.b, 0.42), false, 1.5)

	var num_sz := maxi(10, int(tile_sz * 0.20))
	var sym_sz := maxi(14, int(tile_sz * 0.40))
	draw_string(font, rect.position + Vector2(6.0, num_sz + 3.0), atomic_num,
		HORIZONTAL_ALIGNMENT_LEFT, -1, num_sz, Color(col.r, col.g, col.b, 0.75))
	draw_string(font, Vector2(rect.position.x, center.y + sym_sz * 0.36), symbol,
		HORIZONTAL_ALIGNMENT_CENTER, tile_sz, sym_sz, Color(0.86, 0.90, 0.94, 0.56))
