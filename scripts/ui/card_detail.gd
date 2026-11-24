extends CanvasLayer

## Modal informasi detail kartu untuk Library (bab 7.2).
## Menampilkan pratinjau kartu besar + statistik + resep/efek + catatan sains.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

@onready var _root: Control = $Root
@onready var _card_panel: PanelContainer = $Root/Center/Card
@onready var _type_badge: Label = $Root/Center/Card/V/TopBar/TypeBadge
@onready var _preview_slot: CenterContainer = $Root/Center/Card/V/Body/PreviewSlot
@onready var _name_lbl: Label = $Root/Center/Card/V/Body/Info/Name
@onready var _stats_row: HBoxContainer = $Root/Center/Card/V/Body/Info/StatsRow
@onready var _desc_lbl: Label = $Root/Center/Card/V/Body/Info/DescPanel/Desc
@onready var _recipe_panel: PanelContainer = $Root/Center/Card/V/Body/Info/RecipePanel
@onready var _recipe_lbl: Label = $Root/Center/Card/V/Body/Info/RecipePanel/Recipe
@onready var _ct_panel: PanelContainer = $Root/Center/Card/V/Body/Info/CTPanel
@onready var _ct_title: Label = $Root/Center/Card/V/Body/Info/CTPanel/V/CTTitle
@onready var _ct_lbl: Label = $Root/Center/Card/V/Body/Info/CTPanel/V/CT

var _preview_card: Control

func _ready() -> void:
	_root.hide()
	$Root/Center/Card/V/TopBar/Close.pressed.connect(close)
	$Root/Center/Card/V/Footer/CloseBottom.pressed.connect(close)
	$Root/Dim.gui_input.connect(_on_dim_input)
	get_viewport().size_changed.connect(_resize_modal)

	_preview_card = CARD_SCENE.instantiate()
	_preview_slot.add_child(_preview_card)
	_preview_card.fit(Vector2(296, 402))
	_resize_modal()

func show_card(id: String) -> void:
	var d: CardData = CardDB.get_card(id)
	if d == null:
		return

	_preview_card.setup({"uid": -1, "id": id, "placed_turn": -1}, true, false, false)
	_preview_card.fit(Vector2(296, 402))
	_preview_card.set_info_button(false)

	match d.type:
		CardData.Type.BASIC:
			_type_badge.text = "KARTU DASAR  •  UNSUR KIMIA"
			_type_badge.add_theme_color_override("font_color", Color(0.48, 0.68, 0.86, 1))
		CardData.Type.SPECIAL:
			_type_badge.text = "KARTU SPESIAL  •  SENYAWA KIMIA"
			_type_badge.add_theme_color_override("font_color", Color(0.46, 0.78, 0.68, 1))
		CardData.Type.SPELL:
			_type_badge.text = "KARTU SPELL  •  AKSI TAKTIS"
			_type_badge.add_theme_color_override("font_color", Color(0.84, 0.56, 0.58, 1))

	_name_lbl.text = d.display_name
	if d.type == CardData.Type.SPELL:
		_desc_lbl.text = "Ability: %s" % d.description if d.description != "" else "Tidak ada deskripsi."
	else:
		_desc_lbl.text = d.description if d.description != "" else "Tidak ada deskripsi."

	_build_stats(d)

	if d.type == CardData.Type.SPECIAL and d.recipe.size() == 2:
		var a: CardData = CardDB.get_card(d.recipe[0])
		var b: CardData = CardDB.get_card(d.recipe[1])
		if a != null and b != null:
			_recipe_lbl.text = "Resep Sintesis: %s (%s) + %s (%s)" % [
				a.symbol, a.display_name, b.symbol, b.display_name]
		else:
			_recipe_lbl.text = "Resep Sintesis: %s + %s" % [d.recipe[0], d.recipe[1]]
		_recipe_panel.visible = true
	else:
		_recipe_panel.visible = false

	if d.ct_note != "":
		_ct_title.text = "PENJELASAN ALAT" if d.type == CardData.Type.SPELL else "CATATAN SAINS"
		_ct_lbl.text = d.ct_note
		_ct_panel.visible = true
	else:
		_ct_panel.visible = false
	_resize_modal()
	_root.show()

func close() -> void:
	_root.hide()

func is_open() -> bool:
	return _root.visible

func _build_stats(d: CardData) -> void:
	for ch in _stats_row.get_children():
		_stats_row.remove_child(ch)
		ch.queue_free()
	if d.symbol != "":
		_add_stat_pill("Simbol: %s" % d.symbol)
	if d.atomic_number > 0:
		_add_stat_pill("No. Atom: %d" % d.atomic_number)
	if d.type != CardData.Type.SPELL:
		_add_stat_pill("Poin: %d" % d.points)
	if d.type == CardData.Type.SPECIAL:
		_add_stat_pill("Stok Senyawa: %d" % CardDB.rules.compound_copies)
	elif d.deck_copies > 0:
		_add_stat_pill("Jumlah di Deck: %d" % d.deck_copies)

func _add_stat_pill(txt: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	sb.bg_color = Color(0.145, 0.175, 0.215, 1)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.26, 0.32, 0.40, 1)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	p.add_theme_stylebox_override("panel", sb)

	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", Color(0.86, 0.91, 0.96, 1))
	l.add_theme_font_size_override("font_size", 14)
	p.add_child(l)
	_stats_row.add_child(p)

func _resize_modal() -> void:
	if not is_instance_valid(_card_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(vp.x * 0.70, 780.0, 1060.0)
	var h := clampf(vp.y * 0.74, 520.0, 680.0)
	_card_panel.custom_minimum_size = Vector2(w, h)

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()
