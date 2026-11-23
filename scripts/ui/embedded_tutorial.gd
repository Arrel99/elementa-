extends CanvasLayer

## Embedded Tutorial interaktif terarah di dalam arena 2.5D Elementa:
## - Menggelapkan & memblokir area di luar zona langkah aktif (spotlight mask).
## - Tidak bisa di-skip; memaksa pemain menyelesaikan setiap langkah.
## - Kalimat singkat, padat, dan posisi callout berpindah dekat zona aksi.

signal back_to_menu_requested

const BANNER_W := 360.0

const STEPS := [
	{
		"title": "Pasang H & O",
		"body": "Klik atau seret H dan O ke Zona Dasar.",
		"pos": Vector2(0.50, 0.44),
		"spot": Rect2(0.18, 0.55, 0.64, 0.45),   # Tangan + Zona Dasar pemain
		"arrow": "▼",
		"align": HORIZONTAL_ALIGNMENT_CENTER,
	},
	{
		"title": "Akhiri Giliran",
		"body": "Kartu baru cooldown 1 giliran. Klik END TURN.",
		"pos": Vector2(0.75, 0.48),
		"spot": Rect2(0.89, 0.39, 0.11, 0.17),   # Tombol END TURN di HUD kanan
		"arrow": "▶",
		"align": HORIZONTAL_ALIGNMENT_RIGHT,
	},
	{
		"title": "Sintesis H2O",
		"body": "Klik H lalu O di Zona Dasar.",
		"pos": Vector2(0.50, 0.45),
		"spot": Rect2(0.28, 0.56, 0.46, 0.25),   # Zona Dasar pemain
		"arrow": "▼",
		"align": HORIZONTAL_ALIGNMENT_CENTER,
	},
	{
		"title": "Pakai Korosi",
		"body": "Klik Spell Korosi di tangan.",
		"pos": Vector2(0.50, 0.66),
		"spot": Rect2(0.18, 0.77, 0.64, 0.23),   # Tangan pemain
		"arrow": "▼",
		"align": HORIZONTAL_ALIGNMENT_CENTER,
	},
	{
		"title": "Zoom Kartu",
		"body": "Klik kanan kartu H2O di kiri.",
		"pos": Vector2(0.20, 0.44),
		"spot": Rect2(0.04, 0.54, 0.27, 0.32),   # Zona Senyawa pemain (kiri)
		"arrow": "▼",
		"align": HORIZONTAL_ALIGNMENT_LEFT,
	},
	{
		"title": "Siap Bermain!",
		"body": "Buat 8 senyawa untuk langsung menang.",
		"pos": Vector2(0.50, 0.44),
		"spot": Rect2(0.0, 0.0, 0.0, 0.0),       # Gelapkan seluruh latar di balik kartu selesai
		"arrow": "",
		"align": HORIZONTAL_ALIGNMENT_CENTER,
		"is_final": true,
	},
]

@onready var _mask_root: Control = $MaskRoot
@onready var _dim_top: ColorRect = $MaskRoot/DimTop
@onready var _dim_bottom: ColorRect = $MaskRoot/DimBottom
@onready var _dim_left: ColorRect = $MaskRoot/DimLeft
@onready var _dim_right: ColorRect = $MaskRoot/DimRight
@onready var _spot_frame: Panel = $MaskRoot/SpotlightFrame

@onready var _banner: PanelContainer = $Banner
@onready var _badge: Label = $Banner/V/TopRow/Badge
@onready var _title: Label = $Banner/V/TopRow/Title
@onready var _body: Label = $Banner/V/Body
@onready var _pointer: Label = $Banner/V/Pointer
@onready var _actions: HBoxContainer = $Banner/V/Actions
@onready var _menu_btn: Button = $Banner/V/Actions/MenuBtn
@onready var _next_btn: Button = $Banner/V/Actions/NextBtn

var _active := false
var _step := 0
var _turn_at_step1 := 1
var _spell_targeting := false
var _cur_spot := Rect2()

func _ready() -> void:
	_mask_root.hide()
	_banner.hide()
	_banner.custom_minimum_size = Vector2(BANNER_W, 0.0)
	_body.custom_minimum_size = Vector2(BANNER_W - 36.0, 0.0)

	# Gaya bingkai spotlight matte teal
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.border_color = Color(0.36, 0.80, 0.70, 0.85)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(8)
	_spot_frame.add_theme_stylebox_override("panel", fsb)

	# Klik di area gelap akan memberi getaran pengingat pada kotak tutorial
	for d in [_dim_top, _dim_bottom, _dim_left, _dim_right]:
		d.mouse_filter = Control.MOUSE_FILTER_STOP
		d.gui_input.connect(_on_mask_click)

	_next_btn.pressed.connect(_on_next_pressed)
	_menu_btn.pressed.connect(func():
		stop()
		back_to_menu_requested.emit())
	get_viewport().size_changed.connect(func():
		if _active:
			_place_banner(false)
			_apply_spotlight(false))

func _on_mask_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		nudge()

func start() -> void:
	_active = true
	_step = 0
	_turn_at_step1 = 1
	_spell_targeting = false
	_mask_root.show()
	_banner.show()
	_apply_step(false)

func stop() -> void:
	_active = false
	_mask_root.hide()
	_banner.hide()

func is_active() -> bool:
	return _active

## Memaksa pemain hanya menjalankan aksi yang sesuai dengan langkah tutorial saat ini.
func is_action_allowed(action: Dictionary, v: Dictionary) -> bool:
	if not _active or _step >= STEPS.size() - 1:
		return true
	var t := String(action.get("type", ""))
	if t == "give_up":
		return true

	match _step:
		0:
			if t != "place":
				return false
			var uid := int(action.get("uid", -1))
			var cid := _hand_card_id(v, uid)
			return cid == "H" or cid == "O"
		1:
			return t == "end"
		2:
			return t == "synth"
		3:
			if t == "spell":
				var uid := int(action.get("uid", -1))
				return _hand_card_id(v, uid) == "korosi"
			return t == "spell_target"
		4:
			return false
	return true

func is_end_turn_allowed() -> bool:
	return (not _active) or _step == 1 or _step >= STEPS.size() - 1

func nudge() -> void:
	if not _active or not _banner.visible:
		return
	Audio.play_sfx("error", -5.0)
	var base_x := _banner.position.x
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "position:x", base_x - 8.0, 0.05)
	tw.tween_property(_banner, "position:x", base_x + 8.0, 0.06)
	tw.tween_property(_banner, "position:x", base_x - 5.0, 0.05)
	tw.tween_property(_banner, "position:x", base_x, 0.05)

func on_view_updated(v: Dictionary) -> void:
	if not _active or v.is_empty():
		return
	if int(v.get("winner", -2)) != -2:
		stop()
		return

	match _step:
		0:
			var has_h := false
			var has_o := false
			for c in v.me.base:
				if String(c.get("id", "")) == "H":
					has_h = true
				elif String(c.get("id", "")) == "O":
					has_o = true
			if has_h and has_o:
				_turn_at_step1 = int(v.get("turn_no", 1))
				_advance()
		1:
			if bool(v.get("my_turn", false)) and int(v.get("turn_no", 1)) > _turn_at_step1:
				_advance()
		2:
			if v.me.special.size() >= 1:
				_advance()
		3:
			var in_target := String(v.pending.get("type", "")) == "spell_target"
			if in_target != _spell_targeting:
				_spell_targeting = in_target
				_apply_step(true)
			if v.pending.is_empty() and (int(v.get("spell_left", 1)) == 0 or not v.me.discard.is_empty()):
				_spell_targeting = false
				_advance()

func on_preview_pinned() -> void:
	if _active and _step == 4:
		_advance()

func _on_next_pressed() -> void:
	if not _active:
		return
	if _step >= STEPS.size() - 1:
		stop()
	else:
		_advance()

func _advance() -> void:
	if _step < STEPS.size() - 1:
		_step += 1
		Audio.play_sfx("turn_start", -4.0)
		_apply_step(true)

func _apply_step(animate: bool) -> void:
	var info: Dictionary = STEPS[_step]
	var is_final: bool = bool(info.get("is_final", false))
	_badge.text = "%d / %d" % [_step + 1, STEPS.size()]
	_title.text = String(info.title)
	_body.text = String(info.body)
	var arrow := String(info.get("arrow", ""))
	var align: HorizontalAlignment = info.get("align", HORIZONTAL_ALIGNMENT_CENTER)

	if _step == 3 and _spell_targeting:
		_title.text = "Pilih Target"
		_body.text = "Klik kartu Fe di Zona Dasar lawan."
		arrow = "▲"
		align = HORIZONTAL_ALIGNMENT_CENTER

	_pointer.text = arrow
	_pointer.visible = arrow != ""
	_pointer.horizontal_alignment = align

	_actions.visible = is_final
	_menu_btn.visible = is_final
	_next_btn.text = "Lanjut Main"

	_banner.size = Vector2(BANNER_W, 156.0 if is_final else 118.0)
	call_deferred("_place_banner", animate)
	call_deferred("_apply_spotlight", animate)

func _apply_spotlight(animate: bool) -> void:
	if not is_instance_valid(_mask_root):
		return
	var vp := get_viewport().get_visible_rect().size
	var norm_rect: Rect2 = STEPS[_step].spot
	if _step == 3 and _spell_targeting:
		norm_rect = Rect2(0.28, 0.15, 0.46, 0.25)   # Zona Dasar lawan

	var target_rect := Rect2(
		vp.x * norm_rect.position.x,
		vp.y * norm_rect.position.y,
		vp.x * norm_rect.size.x,
		vp.y * norm_rect.size.y
	)

	if not animate or _cur_spot.size == Vector2.ZERO or target_rect.size == Vector2.ZERO:
		_cur_spot = target_rect
		_set_mask_rect(target_rect)
	else:
		var start_r := _cur_spot
		_cur_spot = target_rect
		var tw := create_tween()
		tw.tween_method(
			func(t: float):
				var r := Rect2(
					start_r.position.lerp(target_rect.position, t),
					start_r.size.lerp(target_rect.size, t)
				)
				_set_mask_rect(r),
			0.0, 1.0, 0.28
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_mask_rect(r: Rect2) -> void:
	var vp := get_viewport().get_visible_rect().size
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		# Gelapkan seluruh layar di balik kartu selesai
		_dim_top.position = Vector2.ZERO
		_dim_top.size = vp
		_dim_bottom.size = Vector2.ZERO
		_dim_left.size = Vector2.ZERO
		_dim_right.size = Vector2.ZERO
		_spot_frame.visible = false
		return

	var x1 := clampf(r.position.x, 0.0, vp.x)
	var y1 := clampf(r.position.y, 0.0, vp.y)
	var x2 := clampf(r.position.x + r.size.x, x1, vp.x)
	var y2 := clampf(r.position.y + r.size.y, y1, vp.y)

	_dim_top.position = Vector2(0.0, 0.0)
	_dim_top.size = Vector2(vp.x, y1)

	_dim_bottom.position = Vector2(0.0, y2)
	_dim_bottom.size = Vector2(vp.x, maxf(0.0, vp.y - y2))

	_dim_left.position = Vector2(0.0, y1)
	_dim_left.size = Vector2(x1, maxf(0.0, y2 - y1))

	_dim_right.position = Vector2(x2, y1)
	_dim_right.size = Vector2(maxf(0.0, vp.x - x2), maxf(0.0, y2 - y1))

	_spot_frame.visible = true
	_spot_frame.position = Vector2(x1, y1)
	_spot_frame.size = Vector2(x2 - x1, y2 - y1)

func _place_banner(animate: bool) -> void:
	if not is_instance_valid(_banner):
		return
	var vp := get_viewport().get_visible_rect().size
	var info: Dictionary = STEPS[_step]
	var is_final: bool = bool(info.get("is_final", false))
	var norm: Vector2 = info.pos
	if _step == 3 and _spell_targeting:
		norm = Vector2(0.50, 0.47)
	var bsz := Vector2(BANNER_W, 156.0 if is_final else 118.0)
	_banner.size = bsz
	var target := Vector2(
		clampf(vp.x * norm.x - bsz.x * 0.5, 16.0, vp.x - bsz.x - 16.0),
		clampf(vp.y * norm.y - bsz.y * 0.5, 16.0, vp.y - bsz.y - 16.0)
	)
	if animate:
		_banner.pivot_offset = bsz * 0.5
		var tw := _banner.create_tween().set_parallel(true)
		tw.tween_property(_banner, "position", target, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_banner, "scale", Vector2(1.03, 1.03), 0.14).set_trans(Tween.TRANS_CUBIC)
		tw.chain().tween_property(_banner, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_CUBIC)
	else:
		_banner.position = target
		_banner.scale = Vector2.ONE

func _hand_card_id(v: Dictionary, uid: int) -> String:
	if v.is_empty():
		return ""
	for c in v.me.hand:
		if int(c.get("uid", -1)) == uid:
			return String(c.get("id", ""))
	return ""
