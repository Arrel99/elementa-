extends CanvasLayer

## Drawer Battle Log bergaya Pokemon TCG Live.
## Tersembunyi secara default; dibuka lewat tombol heksagonal di bawah skor & jam.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HEADER_ME := Color(0.18, 0.34, 0.52, 1.0)
const HEADER_OPP := Color(0.56, 0.20, 0.23, 1.0)
const ROW_BG := Color(0.145, 0.172, 0.210, 1.0)
const ROW_BORDER := Color(0.24, 0.29, 0.36, 1.0)

@onready var _root: Control = $Root
@onready var _scroll: ScrollContainer = $Root/Drawer/V/Scroll
@onready var _list: VBoxContainer = $Root/Drawer/V/Scroll/List
@onready var _empty_lbl: Label = $Root/Drawer/V/Scroll/List/Empty

var _last_sig := ""

func _ready() -> void:
	_root.hide()
	$Root/Drawer/V/Header/Close.pressed.connect(close)
	$Root/Dim.gui_input.connect(_on_dim_input)

func open() -> void:
	_root.show()
	_scroll_to_bottom.call_deferred()

func close() -> void:
	_root.hide()

func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()

func is_open() -> bool:
	return _root.visible

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()

func update_history(v: Dictionary, is_local_test := false) -> void:
	if v.is_empty():
		return
	var turn_no := int(v.get("turn_no", 1))
	var me_idx := int(v.get("me_index", 0))
	var entries: Array = v.get("history", [])

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

	# Kelompokkan aksi per giliran menjadi kartu giliran (gaya Pokemon TCG Live)
	var groups: Array = []
	for item in entries:
		var t := int(item.get("turn", 1))
		var p := int(item.get("player", 0))
		if groups.is_empty() or int(groups[groups.size() - 1].turn) != t:
			groups.append({"turn": t, "player": p, "items": []})
		(groups[groups.size() - 1].items as Array).append(item)

	for g in groups:
		_add_turn_card(int(g.turn), int(g.player), g.items, me_idx, is_local_test)

	if _root.visible:
		_scroll_to_bottom.call_deferred()

func _add_turn_card(turn_no: int, p: int, items: Array, me_idx: int, is_local_test: bool) -> void:
	var is_blue := (p == 0) if is_local_test else (p == me_idx)
	var header_col := HEADER_ME if is_blue else HEADER_OPP
	var owner_name := ("Giliran Pemain %d" % (p + 1)) if is_local_test else ("Giliran Kamu" if is_blue else "Giliran Lawan")

	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.11, 0.132, 0.162, 1.0)
	csb.border_width_left = 1
	csb.border_width_top = 1
	csb.border_width_right = 1
	csb.border_width_bottom = 1
	csb.border_color = ROW_BORDER
	csb.corner_radius_top_left = 8
	csb.corner_radius_top_right = 8
	csb.corner_radius_bottom_right = 8
	csb.corner_radius_bottom_left = 8
	card.add_theme_stylebox_override("panel", csb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	card.add_child(vbox)

	# Header Giliran (nomor giliran di kiri, nama pemain di kanan)
	var hdr := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.content_margin_left = 12.0
	hsb.content_margin_right = 12.0
	hsb.content_margin_top = 6.0
	hsb.content_margin_bottom = 6.0
	hsb.bg_color = header_col
	hsb.corner_radius_top_left = 7
	hsb.corner_radius_top_right = 7
	hdr.add_theme_stylebox_override("panel", hsb)

	var hrow := HBoxContainer.new()
	hdr.add_child(hrow)

	var t_lbl := Label.new()
	t_lbl.text = str(turn_no)
	t_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	t_lbl.add_theme_font_size_override("font_size", 14)
	hrow.add_child(t_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(sp)

	var o_lbl := Label.new()
	o_lbl.text = owner_name
	o_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	o_lbl.add_theme_font_size_override("font_size", 14)
	hrow.add_child(o_lbl)
	vbox.add_child(hdr)

	# Baris-baris kartu yang dimainkan secara urut
	for idx in items.size():
		var it: Dictionary = items[idx]
		vbox.add_child(_make_action_row(it, header_col, idx < items.size() - 1))

	_list.add_child(card)

func _make_action_row(item: Dictionary, accent_col: Color, show_divider: bool) -> PanelContainer:
	var row_panel := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.content_margin_left = 10.0
	rsb.content_margin_right = 12.0
	rsb.content_margin_top = 8.0
	rsb.content_margin_bottom = 8.0
	rsb.bg_color = ROW_BG
	rsb.border_width_left = 3
	rsb.border_width_bottom = 1 if show_divider else 0
	rsb.border_color = accent_col if not show_divider else ROW_BORDER
	row_panel.add_theme_stylebox_override("panel", rsb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row_panel.add_child(h)

	# Miniatur kartu yang dimainkan (seperti di Battle Log Pokemon TCG Live)
	var cid := String(item.get("card_id", ""))
	if cid != "" and CardDB.cards.has(cid):
		var thumb: Control = CARD_SCENE.instantiate()
		thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(thumb)
		thumb.fit(Vector2(48, 64))
		thumb.setup({"uid": -1, "id": cid, "placed_turn": -1}, true, false, false)

	var detail_lbl := Label.new()
	detail_lbl.text = String(item.get("detail", ""))
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.96, 1.0))
	detail_lbl.add_theme_font_size_override("font_size", 14)
	h.add_child(detail_lbl)

	return row_panel

func _scroll_to_bottom() -> void:
	if is_instance_valid(_scroll):
		var bar := _scroll.get_v_scroll_bar()
		if bar != null:
			_scroll.scroll_vertical = int(bar.max_value)
