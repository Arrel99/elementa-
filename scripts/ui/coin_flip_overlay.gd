extends CanvasLayer

## Overlay animasi koin awal pertandingan (sebelum draw kartu pertama):
## 1) Salah satu pemain memilih HEADS atau TAILS
## 2) Animasi lempar & putar koin 50/50
## 3) Pemenang koin memilih mau Giliran Pertama atau Giliran Kedua

signal coin_call_chosen(side: String)
signal turn_order_chosen(go_first: bool)

@onready var _card: PanelContainer = $Root/Center/Card
@onready var _badge: Label = $Root/Center/Card/V/Badge
@onready var _title: Label = $Root/Center/Card/V/Title
@onready var _coin_draw: Control = $Root/Center/Card/V/CoinArea/Coin
@onready var _status: Label = $Root/Center/Card/V/Status
@onready var _call_row: HBoxContainer = $Root/Center/Card/V/CallButtons
@onready var _order_row: HBoxContainer = $Root/Center/Card/V/OrderButtons

var _flip_angle := 0.0           # sudut putar koin dalam radian
var _flip_lift := 0.0            # ketinggian lompatan koin saat dilempar
var _is_animating := false
var _last_stage := ""
var _last_result := ""
var _pending_order_cp := {}
var _pending_local := false
var _pending_me_idx := 0

func _ready() -> void:
	hide()
	$Root/Center/Card/V/CallButtons/Heads.pressed.connect(func(): coin_call_chosen.emit("heads"))
	$Root/Center/Card/V/CallButtons/Tails.pressed.connect(func(): coin_call_chosen.emit("tails"))
	$Root/Center/Card/V/OrderButtons/First.pressed.connect(func(): turn_order_chosen.emit(true))
	$Root/Center/Card/V/OrderButtons/Second.pressed.connect(func(): turn_order_chosen.emit(false))
	_coin_draw.draw.connect(_draw_coin)

func sync(v: Dictionary, is_local_test: bool) -> void:
	var cp: Dictionary = v.get("coin_phase", {})
	if cp.is_empty():
		_last_stage = ""
		_last_result = ""
		_is_animating = false
		hide()
		return

	show()
	var stage := String(cp.get("stage", ""))
	var me_idx := int(v.get("me_index", 0))

	if stage == "pick_call":
		if _last_stage != "pick_call":
			_last_stage = "pick_call"
			_last_result = ""
			_flip_angle = 0.0
			_flip_lift = 0.0
			_coin_draw.queue_redraw()
		var caller := int(cp.get("caller", 0))
		var can_call := is_local_test or (caller == me_idx)
		_badge.text = "PENENTUAN GILIRAN  •  TAHAP 1 / 2"
		if is_local_test:
			_title.text = "Pemain %d Memilih Sisi Koin" % (caller + 1)
			_status.text = "Pilih HEADS atau TAILS. Pemenang koin berhak memilih giliran pertama."
		elif can_call:
			_title.text = "Pilih Sisi Koin"
			_status.text = "Pilih HEADS atau TAILS. Jika tebakanmu benar, kamu pilih urutan giliran."
		else:
			_title.text = "Menunggu Lawan..."
			_status.text = "Lawan sedang memilih HEADS atau TAILS untuk lempar koin awal."
		_call_row.visible = can_call
		_order_row.visible = false

	elif stage == "pick_order":
		var res := String(cp.get("result", "heads"))
		_pending_order_cp = cp.duplicate(true)
		_pending_local = is_local_test
		_pending_me_idx = me_idx
		if _last_result != res or _last_stage != "pick_order":
			_last_stage = "pick_order"
			_last_result = res
			_play_flip_animation(res)
		elif not _is_animating:
			_show_order_choice()

func _play_flip_animation(result_side: String) -> void:
	_is_animating = true
	_call_row.visible = false
	_order_row.visible = false
	_badge.text = "LEMPAR KOIN  •  50 / 50"
	_title.text = "Memutar Koin..."
	_status.text = "Menentukan pemenang lempar koin..."

	# Target sudut: kelipatan genap PI = HEADS (0), kelipatan ganjil PI = TAILS (PI)
	var spins := 6
	var target_angle := float(spins * 2) * PI + (0.0 if result_side == "heads" else PI)
	_flip_angle = 0.0
	_flip_lift = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_set_flip_angle, 0.0, target_angle, 1.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_flip_lift, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_method(_set_flip_lift, 1.0, 0.0, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.20)
	tw.chain().tween_callback(func():
		_is_animating = false
		_show_order_choice())

func _set_flip_angle(a: float) -> void:
	_flip_angle = a
	_coin_draw.queue_redraw()

func _set_flip_lift(v: float) -> void:
	_flip_lift = v
	_coin_draw.queue_redraw()

func _show_order_choice() -> void:
	var cp := _pending_order_cp
	if cp.is_empty():
		return
	var res := String(cp.get("result", "heads")).to_upper()
	var call_side := String(cp.get("call", "heads")).to_upper()
	var win_p := int(cp.get("winner", 0))
	var can_pick := _pending_local or (win_p == _pending_me_idx)

	_badge.text = "HASIL KOIN: %s  (PILIHAN: %s)" % [res, call_side]
	if _pending_local:
		_title.text = "Pemain %d Menang Koin!" % (win_p + 1)
		_status.text = "Pemain %d, pilih apakah kamu ingin mengambil giliran pertama atau kedua." % (win_p + 1)
	elif can_pick:
		_title.text = "Kamu Menang Lempar Koin!"
		_status.text = "Pilih apakah kamu ingin bermain duluan (Giliran Pertama) atau belakangan (Giliran Kedua)."
	else:
		_title.text = "Lawan Menang Lempar Koin"
		_status.text = "Menunggu lawan memilih urutan giliran pertama atau kedua..."

	_call_row.visible = false
	_order_row.visible = can_pick

func _draw_coin() -> void:
	var sz := _coin_draw.size
	var center := Vector2(sz.x * 0.5, sz.y * 0.55 - _flip_lift * 42.0)
	var radius := minf(sz.x, sz.y) * 0.34 * (1.0 + _flip_lift * 0.14)

	# Bayangan lembut di bawah koin (mengecil saat koin melompat tinggi)
	var sh_w := radius * (0.95 - _flip_lift * 0.32)
	var sh_c := Vector2(sz.x * 0.5, sz.y * 0.55 + radius * 0.85)
	_coin_draw.draw_set_transform(sh_c, 0.0, Vector2(1.0, 0.25))
	_coin_draw.draw_circle(Vector2.ZERO, sh_w, Color(0.02, 0.03, 0.05, 0.45 * (1.0 - _flip_lift * 0.4)))
	_coin_draw.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Proyeksi 3D putaran koin pada sumbu vertikal
	var cos_a := cos(_flip_angle)
	var is_heads := cos_a >= 0.0
	var sx := maxf(absf(cos_a), 0.06)

	var base_col := Color(0.76, 0.60, 0.26, 1.0) if is_heads else Color(0.28, 0.46, 0.64, 1.0)
	var rim_col := Color(0.94, 0.80, 0.46, 1.0) if is_heads else Color(0.58, 0.78, 0.94, 1.0)
	var inner_col := base_col.darkened(0.22)

	# Ketebalan pinggiran koin saat miring
	_coin_draw.draw_set_transform(center + Vector2(4.0 * (1.0 - sx), 0.0), 0.0, Vector2(sx, 1.0))
	_coin_draw.draw_circle(Vector2.ZERO, radius, base_col.darkened(0.35))

	# Muka koin utama
	_coin_draw.draw_set_transform(center, 0.0, Vector2(sx, 1.0))
	_coin_draw.draw_circle(Vector2.ZERO, radius, rim_col)
	_coin_draw.draw_circle(Vector2.ZERO, radius * 0.90, base_col)
	_coin_draw.draw_circle(Vector2.ZERO, radius * 0.78, inner_col)

	if sx > 0.22:
		if is_heads:
			# Emblem HEADS: Heksagon Atom
			var hex := PackedVector2Array()
			for i in 7:
				var a := float(i) * TAU / 6.0 - PI * 0.5
				hex.append(Vector2(cos(a), sin(a)) * radius * 0.42)
			_coin_draw.draw_polyline(hex, rim_col, 3.0, true)
			_coin_draw.draw_circle(Vector2.ZERO, radius * 0.14, rim_col)
		else:
			# Emblem TAILS: 3 Lingkaran Molekul (H2O)
			var r_o := radius * 0.19
			var r_h := radius * 0.13
			var p_o := Vector2(0.0, -radius * 0.14)
			var p_h1 := Vector2(-radius * 0.28, radius * 0.18)
			var p_h2 := Vector2(radius * 0.28, radius * 0.18)
			_coin_draw.draw_line(p_o, p_h1, rim_col, 4.0, true)
			_coin_draw.draw_line(p_o, p_h2, rim_col, 4.0, true)
			_coin_draw.draw_circle(p_o, r_o, rim_col)
			_coin_draw.draw_circle(p_h1, r_h, rim_col)
			_coin_draw.draw_circle(p_h2, r_h, rim_col)

		var font := ThemeDB.fallback_font
		var lbl := "HEADS" if is_heads else "TAILS"
		_coin_draw.draw_string(font, Vector2(-radius * 0.5, radius * 0.62), lbl,
			HORIZONTAL_ALIGNMENT_CENTER, radius, 16, rim_col)

	_coin_draw.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
