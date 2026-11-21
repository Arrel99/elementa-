extends CanvasLayer

## Panel Riwayat Giliran & Kartu yang Dimainkan (pojok kanan atas arena).
## Menampilkan nomor giliran aktif serta daftar urut setiap kartu yang dimainkan.

const COLOR_ME := Color(0.56, 0.76, 0.92, 1.0)
const COLOR_OPP := Color(0.88, 0.56, 0.58, 1.0)
const COLOR_TURN := Color(0.54, 0.78, 0.72, 1.0)

@onready var _panel: PanelContainer = $Root/Panel
@onready var _collapsed_btn: Button = $Root/CollapsedBtn
@onready var _turn_lbl: Label = $Root/Panel/V/Top/TurnLabel
@onready var _scroll: ScrollContainer = $Root/Panel/V/Scroll
@onready var _list: VBoxContainer = $Root/Panel/V/Scroll/List
@onready var _empty_lbl: Label = $Root/Panel/V/Scroll/List/Empty

var _expanded := true
var _last_sig := ""

func _ready() -> void:
	_expanded = bool(Settings.get_value("ui", "show_history", true))
	$Root/Panel/V/Top/HideBtn.pressed.connect(_set_expanded.bind(false))
	_collapsed_btn.pressed.connect(_set_expanded.bind(true))
	_apply_visibility()

func _set_expanded(on: bool) -> void:
	_expanded = on
	Settings.set_value("ui", "show_history", on)
	_apply_visibility()

func _apply_visibility() -> void:
	_panel.visible = _expanded
	_collapsed_btn.visible = not _expanded

func update_history(v: Dictionary, is_local_test := false) -> void:
	if v.is_empty():
		return
	var turn_no := int(v.get("turn_no", 1))
	var me_idx := int(v.get("me_index", 0))
	var entries: Array = v.get("history", [])

	var who_now := ""
	if is_local_test:
		who_now = "Pemain %d" % (me_idx + 1)
	else:
		who_now = "Giliranmu" if bool(v.get("my_turn", false)) else "Giliran Lawan"

	var cd := int(v.get("countdown", -1))
	var cd_txt := "  •  Sisa %d" % cd if cd > 0 else ""
	_turn_lbl.text = "GILIRAN %d  •  %s%s" % [turn_no, who_now, cd_txt]
	_collapsed_btn.text = "Giliran %d  •  Riwayat (%d)" % [turn_no, entries.size()]

	var sig := "%d:%d:%d:%s" % [turn_no, me_idx, entries.size(), str(is_local_test)]
	if sig == _last_sig:
		return
	_last_sig = sig

	for ch in _list.get_children():
		if ch != _empty_lbl:
			_list.remove_child(ch)
			ch.queue_free()

	_empty_lbl.visible = entries.is_empty()
	if entries.is_empty():
		return

	var current_turn_group := -1
	var step_in_turn := 0
	for item in entries:
		var t := int(item.get("turn", 1))
		if t != current_turn_group:
			current_turn_group = t
			step_in_turn = 0
			_add_turn_header(t)
		step_in_turn += 1
		var p := int(item.get("player", 0))
		var is_me := (p == me_idx)
		var tag := ("P%d" % (p + 1)) if is_local_test else ("Kamu" if is_me else "Lawan")
		var col := COLOR_ME if (p == 0 if is_local_test else is_me) else COLOR_OPP
		_add_entry_row(step_in_turn, tag, String(item.get("detail", "")), col)

	# Gulir otomatis ke catatan terbaru di bagian bawah
	_scroll_to_bottom.call_deferred()

func _add_turn_header(turn_no: int) -> void:
	var lbl := Label.new()
	lbl.text = "Giliran %d" % turn_no
	lbl.add_theme_color_override("font_color", COLOR_TURN)
	lbl.add_theme_font_size_override("font_size", 12)
	_list.add_child(lbl)

func _add_entry_row(idx: int, tag: String, detail: String, tag_col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var num := Label.new()
	num.text = "%d." % idx
	num.add_theme_color_override("font_color", Color(0.52, 0.58, 0.66, 0.9))
	num.add_theme_font_size_override("font_size", 12)
	num.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(num)

	var who := Label.new()
	who.text = "[%s]" % tag
	who.add_theme_color_override("font_color", tag_col)
	who.add_theme_font_size_override("font_size", 12)
	who.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(who)

	var txt := Label.new()
	txt.text = detail
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95, 1.0))
	txt.add_theme_font_size_override("font_size", 12)
	row.add_child(txt)

	_list.add_child(row)

func _scroll_to_bottom() -> void:
	if is_instance_valid(_scroll):
		var bar := _scroll.get_v_scroll_bar()
		if bar != null:
			_scroll.scroll_vertical = int(bar.max_value)
