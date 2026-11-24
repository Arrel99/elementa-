extends CanvasLayer

## Katalog Resep Cepat (tombol pojok kiri atas atau tombol Tab).
## Menampilkan ke-9 resep senyawa dengan penanda hijau bila bahannya siap di Zona Dasar.

@onready var _toggle_btn: Button = $ToggleBtn
@onready var _root: Control = $Root
@onready var _list: VBoxContainer = $Root/Center/Card/V/List

var _last_view: Dictionary = {}

func _ready() -> void:
	_root.hide()
	_toggle_btn.pressed.connect(toggle)
	$Root/Center/Card/V/Header/Close.pressed.connect(close)
	$Root/Dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())

func set_button_visible(vis: bool) -> void:
	_toggle_btn.visible = vis

func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()

func open() -> void:
	_rebuild()
	_root.show()

func close() -> void:
	_root.hide()

func is_open() -> bool:
	return _root.visible

func sync_view(v: Dictionary) -> void:
	_last_view = v
	if _root.visible:
		_rebuild()

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_TAB:
		if _toggle_btn.visible:
			toggle()
			get_viewport().set_input_as_handled()

func _rebuild() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()

	var ready_base := {}
	var pile: Array = []
	if not _last_view.is_empty():
		var tno := int(_last_view.get("turn_no", 1))
		for c in _last_view.me.base:
			if int(c.get("placed_turn", -1)) != tno:
				ready_base[String(c.id)] = true
		pile = _last_view.get("compound_pile", [])

	var specials := CardDB.ids_of(CardData.Type.SPECIAL)
	specials.sort_custom(func(a, b):
		var da := CardDB.get_card(String(a))
		var db := CardDB.get_card(String(b))
		return (da.points if da else 0) > (db.points if db else 0))

	for raw_id in specials:
		var cid := String(raw_id)
		var d := CardDB.get_card(cid)
		if d == null or d.recipe.size() != 2:
			continue
		var r0 := String(d.recipe[0])
		var r1 := String(d.recipe[1])
		var stock := pile.count(cid) if not _last_view.is_empty() else CardDB.rules.compound_copies
		var can_now := ready_base.has(r0) and ready_base.has(r1) and stock > 0

		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		sb.bg_color = Color(0.11, 0.24, 0.20, 0.96) if can_now else Color(0.115, 0.140, 0.175, 0.95)
		sb.border_width_left = 3 if can_now else 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.32, 0.84, 0.62, 1.0) if can_now else Color(0.22, 0.27, 0.34, 1.0)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		row.add_theme_stylebox_override("panel", sb)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)

		var formula_lbl := Label.new()
		formula_lbl.text = "%s  +  %s" % [r0, r1]
		formula_lbl.custom_minimum_size = Vector2(120, 0)
		formula_lbl.add_theme_font_size_override("font_size", 17)
		formula_lbl.add_theme_color_override("font_color", Color(0.70, 0.94, 0.84) if can_now else Color(0.76, 0.86, 0.96))
		h.add_child(formula_lbl)

		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 17)
		arrow.add_theme_color_override("font_color", Color(0.55, 0.64, 0.72))
		h.add_child(arrow)

		var name_lbl := Label.new()
		name_lbl.text = "%s (%s)" % [d.display_name, d.symbol]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 0.99))
		h.add_child(name_lbl)

		var pts_lbl := Label.new()
		pts_lbl.text = "+%d poin" % d.points
		pts_lbl.add_theme_font_size_override("font_size", 16)
		pts_lbl.add_theme_color_override("font_color", Color(0.94, 0.82, 0.44))
		h.add_child(pts_lbl)

		var stock_lbl := Label.new()
		stock_lbl.text = "Stok %d" % stock
		stock_lbl.custom_minimum_size = Vector2(68, 0)
		stock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stock_lbl.add_theme_font_size_override("font_size", 14)
		stock_lbl.add_theme_color_override("font_color", Color(0.56, 0.66, 0.76) if stock > 0 else Color(0.78, 0.36, 0.38))
		h.add_child(stock_lbl)

		_list.add_child(row)
