extends CanvasLayer

## Drawer Battle Log bergaya Pokemon TCG Live (lebar 1/3 layar di sisi kanan).
## Urutan terbaru di paling atas, dengan miniatur kartu besar & gambar kartu pada dropdown.

signal preview_pin(data: Dictionary, source: Node)

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HEADER_ME := Color(0.18, 0.34, 0.52, 1.0)
const HEADER_OPP := Color(0.56, 0.20, 0.23, 1.0)
const ROW_BG := Color(0.145, 0.172, 0.210, 1.0)
const ROW_BORDER := Color(0.24, 0.29, 0.36, 1.0)

const MAIN_THUMB_SIZE := Vector2(68, 92)
const SUB_THUMB_SIZE := Vector2(52, 70)
const SUB_PAIR_THUMB_SIZE := Vector2(46, 62)

@onready var _root: Control = $Root
@onready var _drawer: PanelContainer = $Root/Drawer
@onready var _scroll: ScrollContainer = $Root/Drawer/V/Scroll
@onready var _list: VBoxContainer = $Root/Drawer/V/Scroll/List
@onready var _empty_lbl: Label = $Root/Drawer/V/Scroll/List/Empty

var _last_sig := ""

func _ready() -> void:
	_root.hide()
	$Root/Drawer/V/Header/Close.pressed.connect(close)
	$Root/Dim.gui_input.connect(_on_dim_input)
	get_viewport().size_changed.connect(_resize_drawer)
	_resize_drawer()

func _resize_drawer() -> void:
	if not is_instance_valid(_drawer):
		return
	var vp := get_viewport().get_visible_rect().size
	var w := roundf(clampf(vp.x / 3.0, 420.0, 760.0))
	_drawer.offset_left = -w
	_drawer.offset_right = 0.0

func open() -> void:
	_resize_drawer()
	_root.show()
	_scroll_to_top.call_deferred()

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

	var sub_total := 0
	for it in entries:
		sub_total += (it.get("sub_moves", []) as Array).size()
	var sig := "%d:%d:%d:%d:%s" % [turn_no, me_idx, entries.size(), sub_total, str(is_local_test)]
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

	# Kelompokkan aksi per giliran
	var groups: Array = []
	for item in entries:
		var t := int(item.get("turn", 1))
		var p := int(item.get("player", 0))
		if groups.is_empty() or int(groups[groups.size() - 1].turn) != t:
			groups.append({"turn": t, "player": p, "items": []})
		(groups[groups.size() - 1].items as Array).append(item)

	# Tampilkan dari giliran TERBARU di paling atas -> lama di paling bawah
	for gi in range(groups.size() - 1, -1, -1):
		var g: Dictionary = groups[gi]
		_add_turn_card(int(g.turn), int(g.player), g.items, me_idx, is_local_test)

	if _root.visible:
		_scroll_to_top.call_deferred()

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

	# Header Giliran
	var hdr := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.content_margin_left = 14.0
	hsb.content_margin_right = 14.0
	hsb.content_margin_top = 8.0
	hsb.content_margin_bottom = 8.0
	hsb.bg_color = header_col
	hsb.corner_radius_top_left = 7
	hsb.corner_radius_top_right = 7
	hdr.add_theme_stylebox_override("panel", hsb)

	var hrow := HBoxContainer.new()
	hdr.add_child(hrow)

	var t_lbl := Label.new()
	t_lbl.text = "Giliran %d" % turn_no
	t_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	t_lbl.add_theme_font_size_override("font_size", 15)
	hrow.add_child(t_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(sp)

	var o_lbl := Label.new()
	o_lbl.text = owner_name
	o_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	o_lbl.add_theme_font_size_override("font_size", 15)
	hrow.add_child(o_lbl)
	vbox.add_child(hdr)

	# Baris aksi dalam giliran ini: TERBARU di paling atas -> lama di bawah
	for idx in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[idx]
		vbox.add_child(_make_action_row(it, header_col, idx > 0))

	_list.add_child(card)

func _make_action_row(item: Dictionary, accent_col: Color, show_divider: bool) -> PanelContainer:
	var row_panel := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.content_margin_left = 12.0
	rsb.content_margin_right = 12.0
	rsb.content_margin_top = 10.0
	rsb.content_margin_bottom = 10.0
	rsb.bg_color = ROW_BG
	rsb.border_width_left = 3
	rsb.border_width_bottom = 1 if show_divider else 0
	rsb.border_color = accent_col if not show_divider else ROW_BORDER
	row_panel.add_theme_stylebox_override("panel", rsb)

	var outer_v := VBoxContainer.new()
	outer_v.add_theme_constant_override("separation", 8)
	row_panel.add_child(outer_v)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	outer_v.add_child(h)

	# Miniatur kartu utama yang dimainkan (klik kanan untuk zoom detail!)
	var cid := String(item.get("card_id", ""))
	if cid != "" and CardDB.cards.has(cid):
		var thumb: Control = CARD_SCENE.instantiate()
		thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(thumb)
		thumb.fit(MAIN_THUMB_SIZE)
		thumb.setup({"uid": -1, "id": cid, "placed_turn": -1}, true, false, true)
		thumb.preview_pin.connect(func(d, s): preview_pin.emit(d, s))

	var detail_lbl := Label.new()
	detail_lbl.text = String(item.get("detail", ""))
	detail_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98, 1.0))
	detail_lbl.add_theme_font_size_override("font_size", 16)
	h.add_child(detail_lbl)

	# Dropdown sub-move (khusus Spell / aksi yang memengaruhi kartu)
	var subs: Array = item.get("sub_moves", [])
	if not subs.is_empty():
		var toggle_btn := Button.new()
		toggle_btn.text = "v"
		toggle_btn.custom_minimum_size = Vector2(34, 34)
		toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.11, 0.14, 0.18, 1.0)
		bsb.border_width_left = 1
		bsb.border_width_top = 1
		bsb.border_width_right = 1
		bsb.border_width_bottom = 1
		bsb.border_color = Color(0.28, 0.35, 0.44, 1.0)
		bsb.corner_radius_top_left = 6
		bsb.corner_radius_top_right = 6
		bsb.corner_radius_bottom_right = 6
		bsb.corner_radius_bottom_left = 6
		toggle_btn.add_theme_stylebox_override("normal", bsb)
		var bsbh := bsb.duplicate() as StyleBoxFlat
		bsbh.bg_color = Color(0.18, 0.23, 0.30, 1.0)
		toggle_btn.add_theme_stylebox_override("hover", bsbh)
		toggle_btn.add_theme_font_size_override("font_size", 14)
		h.add_child(toggle_btn)

		var sub_panel := PanelContainer.new()
		sub_panel.visible = false
		var ssb := StyleBoxFlat.new()
		ssb.content_margin_left = 12.0
		ssb.content_margin_right = 10.0
		ssb.content_margin_top = 8.0
		ssb.content_margin_bottom = 8.0
		ssb.bg_color = Color(0.105, 0.125, 0.155, 1.0)
		ssb.border_width_left = 2
		ssb.border_color = accent_col.lightened(0.15)
		ssb.corner_radius_top_right = 6
		ssb.corner_radius_bottom_right = 6
		sub_panel.add_theme_stylebox_override("panel", ssb)

		var sub_v := VBoxContainer.new()
		sub_v.add_theme_constant_override("separation", 8)
		sub_panel.add_child(sub_v)

		var is_spektro := (cid == "spektrometer")
		for s in subs:
			var sr := HBoxContainer.new()
			sr.add_theme_constant_override("separation", 10)
			var use_back := is_spektro or bool(s.get("card_back", false))
			var scids: Array = s.get("card_ids", [])
			var scid := String(s.get("card_id", ""))

			if use_back:
				# Khusus Spektrometer (dan tarik kartu dari deck): tampilkan lambang punggung deck
				_add_sub_thumb(sr, "back", false, SUB_THUMB_SIZE)
			elif not scids.is_empty():
				var pair_box := HBoxContainer.new()
				pair_box.add_theme_constant_override("separation", 4)
				pair_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				sr.add_child(pair_box)
				for raw_id in scids:
					var sid := String(raw_id)
					if CardDB.cards.has(sid):
						_add_sub_thumb(pair_box, sid, true, SUB_PAIR_THUMB_SIZE)
			elif scid != "" and CardDB.cards.has(scid):
				_add_sub_thumb(sr, scid, true, SUB_THUMB_SIZE)

			var slbl := Label.new()
			slbl.text = String(s.get("text", ""))
			slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slbl.add_theme_color_override("font_color", Color(0.80, 0.86, 0.92, 1.0))
			slbl.add_theme_font_size_override("font_size", 14)
			sr.add_child(slbl)
			sub_v.add_child(sr)

		outer_v.add_child(sub_panel)
		toggle_btn.pressed.connect(func():
			sub_panel.visible = not sub_panel.visible
			toggle_btn.text = "^" if sub_panel.visible else "v")

	return row_panel

func _add_sub_thumb(parent: Control, cid: String, face_up: bool, sz: Vector2) -> void:
	var sthumb: Control = CARD_SCENE.instantiate()
	sthumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sthumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(sthumb)
	sthumb.fit(sz)
	sthumb.setup({"uid": -1, "id": cid, "placed_turn": -1}, face_up, false, face_up)
	if face_up:
		sthumb.preview_pin.connect(func(d, s): preview_pin.emit(d, s))

func _scroll_to_top() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0
