extends CanvasLayer

## Modal hasil pertandingan bergaya matte minimalis (Menang / Kalah / Seri)
## dengan ringkasan skor, jumlah senyawa, sisa waktu, dan animasi masuk halus.

signal back_to_menu_requested
signal rematch_requested

@onready var _card: PanelContainer = $Root/Center/Card
@onready var _accent: Panel = $Root/Center/Card/V/AccentBar
@onready var _title: Label = $Root/Center/Card/V/Title
@onready var _reason: Label = $Root/Center/Card/V/Reason
@onready var _me_who: Label = $Root/Center/Card/V/Scores/MeBox/V/Who
@onready var _me_pts: Label = $Root/Center/Card/V/Scores/MeBox/V/Points
@onready var _me_meta: Label = $Root/Center/Card/V/Scores/MeBox/V/Meta
@onready var _opp_who: Label = $Root/Center/Card/V/Scores/OppBox/V/Who
@onready var _opp_pts: Label = $Root/Center/Card/V/Scores/OppBox/V/Points
@onready var _opp_meta: Label = $Root/Center/Card/V/Scores/OppBox/V/Meta
@onready var _rematch_btn: Button = $Root/Center/Card/V/Buttons/Rematch
@onready var _back_btn: Button = $Root/Center/Card/V/Buttons/Back

func _ready() -> void:
	hide()
	_back_btn.pressed.connect(func(): back_to_menu_requested.emit())
	_rematch_btn.pressed.connect(func(): rematch_requested.emit())

func show_result(v: Dictionary, reason_text: String, is_local_test: bool) -> void:
	var w := int(v.winner)
	var me_idx := int(v.me_index)
	var accent_col := Color(0.36, 0.56, 0.72, 1.0)
	var title_col := Color(0.95, 0.98, 1.0, 1.0)

	if w == -1:
		_title.text = "SERI!"
		accent_col = Color(0.42, 0.58, 0.74, 1.0)
	elif is_local_test:
		_title.text = "PEMAIN %d MENANG!" % (w + 1)
		accent_col = Color(0.30, 0.70, 0.58, 1.0)
		title_col = Color(0.76, 0.96, 0.88, 1.0)
	elif w == me_idx:
		_title.text = "KAMU MENANG!"
		accent_col = Color(0.30, 0.70, 0.58, 1.0)
		title_col = Color(0.76, 0.96, 0.88, 1.0)
	else:
		_title.text = "KAMU KALAH"
		accent_col = Color(0.74, 0.30, 0.34, 1.0)
		title_col = Color(0.96, 0.74, 0.76, 1.0)

	_title.add_theme_color_override("font_color", title_col)
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent_col
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	_accent.add_theme_stylebox_override("panel", sb)

	_reason.text = reason_text
	_me_who.text = ("PEMAIN %d" % (me_idx + 1)) if is_local_test else "KAMU"
	_opp_who.text = ("PEMAIN %d" % ((1 - me_idx) + 1)) if is_local_test else "LAWAN"
	_me_pts.text = str(v.me.points)
	_opp_pts.text = str(v.opp.points)
	_me_meta.text = "%d Senyawa  •  %s" % [v.me.special.size(), _fmt_clock(float(v.me.get("time_left", 0.0)))]
	_opp_meta.text = "%d Senyawa  •  %s" % [v.opp.special.size(), _fmt_clock(float(v.opp.get("time_left", 0.0)))]
	_rematch_btn.visible = is_local_test

	if not visible:
		show()
		_card.pivot_offset = _card.size * 0.5
		_card.scale = Vector2(0.88, 0.88)
		_card.modulate.a = 0.0
		var tw := _card.create_tween().set_parallel(true)
		tw.tween_property(_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_card, "modulate:a", 1.0, 0.20)

func _fmt_clock(sec: float) -> String:
	var s := maxi(0, int(ceil(sec)))
	return "%02d:%02d" % [s / 60, s % 60]
