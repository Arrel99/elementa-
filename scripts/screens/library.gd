extends Control

## Library kartu Elementa bergaya matte minimalis dengan pencarian, filter
## kategori, grid responsif, dan tombol informasi kecil (i) pada tiap kartu.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_SIZE := Vector2(196, 262)

@onready var _back_btn: Button = $Margin/Layout/TopBar/H/Back
@onready var _search: LineEdit = $Margin/Layout/TopBar/H/Search
@onready var _btn_all: Button = $Margin/Layout/FilterBar/All
@onready var _btn_basic: Button = $Margin/Layout/FilterBar/Basic
@onready var _btn_special: Button = $Margin/Layout/FilterBar/Special
@onready var _btn_spell: Button = $Margin/Layout/FilterBar/Spell
@onready var _count_lbl: Label = $Margin/Layout/FilterBar/CountLabel
@onready var _scroll: ScrollContainer = $Margin/Layout/Shelf/Scroll
@onready var _grid: GridContainer = $Margin/Layout/Shelf/Scroll/Grid
@onready var _empty_lbl: Label = $Margin/Layout/Shelf/EmptyLabel

var _active_filter := "all"       # all | basic | special | spell
var _query := ""

func _ready() -> void:
	_back_btn.pressed.connect(_back_to_menu)
	_btn_all.pressed.connect(_set_filter.bind("all"))
	_btn_basic.pressed.connect(_set_filter.bind("basic"))
	_btn_special.pressed.connect(_set_filter.bind("special"))
	_btn_spell.pressed.connect(_set_filter.bind("spell"))
	_search.text_changed.connect(_on_search_changed)
	resized.connect(_update_grid_columns)

	var basic_n := CardDB.ids_of(CardData.Type.BASIC).size()
	var special_n := CardDB.ids_of(CardData.Type.SPECIAL).size()
	var spell_n := CardDB.ids_of(CardData.Type.SPELL).size()
	var total_n := basic_n + special_n + spell_n
	_btn_all.text = "Semua (%d)" % total_n
	_btn_basic.text = "Kartu Dasar (%d)" % basic_n
	_btn_special.text = "Senyawa (%d)" % special_n
	_btn_spell.text = "Spell (%d)" % spell_n

	_update_grid_columns()
	_refresh_filter_styles()
	_render_grid()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if $Detail.is_open():
			$Detail.close()
		else:
			_back_to_menu()

func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _set_filter(f: String) -> void:
	_active_filter = f
	_refresh_filter_styles()
	_render_grid()

func _on_search_changed(txt: String) -> void:
	_query = txt.strip_edges().to_lower()
	_render_grid()

func _update_grid_columns() -> void:
	var avail_w := maxf(_scroll.size.x, size.x - 96.0)
	var cols := clampi(int((avail_w + 18.0) / (CARD_SIZE.x + 18.0)), 2, 7)
	_grid.columns = cols

func _refresh_filter_styles() -> void:
	var buttons := {
		"all": [_btn_all, Color(0.18, 0.44, 0.42), Color(0.32, 0.64, 0.59)],
		"basic": [_btn_basic, Color(0.18, 0.31, 0.45), Color(0.36, 0.54, 0.72)],
		"special": [_btn_special, Color(0.18, 0.38, 0.34), Color(0.36, 0.64, 0.56)],
		"spell": [_btn_spell, Color(0.42, 0.21, 0.24), Color(0.66, 0.38, 0.41)],
	}
	for key in buttons:
		var btn: Button = buttons[key][0]
		var active_bg: Color = buttons[key][1]
		var active_border: Color = buttons[key][2]
		var is_active: bool = (key == _active_filter)

		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 14.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_right = 8
		sb.corner_radius_bottom_left = 8
		sb.bg_color = active_bg if is_active else Color(0.13, 0.16, 0.20, 1)
		sb.border_color = active_border if is_active else Color(0.24, 0.29, 0.36, 1)

		var sb_hover := sb.duplicate() as StyleBoxFlat
		sb_hover.bg_color = sb.bg_color.lightened(0.08)
		sb_hover.border_color = sb.border_color.lightened(0.15)

		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_color_override("font_color",
			Color(0.96, 0.98, 1.0) if is_active else Color(0.76, 0.82, 0.88))

func _collect_ids() -> Array[String]:
	var ids: Array[String] = []
	if _active_filter == "all" or _active_filter == "basic":
		for id in CardDB.ids_of(CardData.Type.BASIC):
			ids.append(String(id))
	if _active_filter == "all" or _active_filter == "special":
		for id in CardDB.ids_of(CardData.Type.SPECIAL):
			ids.append(String(id))
	if _active_filter == "all" or _active_filter == "spell":
		for id in CardDB.ids_of(CardData.Type.SPELL):
			ids.append(String(id))

	if _query == "":
		return ids

	var filtered: Array[String] = []
	for id in ids:
		var d: CardData = CardDB.get_card(id)
		if d == null:
			continue
		var hay := ("%s %s %s %s %s" % [
			d.id, d.display_name, d.symbol, d.description, d.spell_effect]).to_lower()
		if hay.contains(_query):
			filtered.append(id)
	return filtered

func _render_grid() -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()

	var ids := _collect_ids()
	_count_lbl.text = "Menampilkan %d kartu" % ids.size()
	_empty_lbl.visible = ids.is_empty()

	for id in ids:
		var n: Control = CARD_SCENE.instantiate()
		_grid.add_child(n)
		n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.fit(CARD_SIZE)
		n.setup({"uid": -1, "id": id, "placed_turn": -1}, true, true, false)
		n.set_info_button(true)
		n.clicked.connect(func(_u): $Detail.show_card(id))
		n.info_clicked.connect(func(cid: String): $Detail.show_card(cid))
