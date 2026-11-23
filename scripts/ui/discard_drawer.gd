extends CanvasLayer

## Drawer Discard Pile bergaya Pokemon TCG Live (muncul di sisi kiri layar).
## Kedua pemain bebas melihat seluruh kartu yang ada di discard milik sendiri maupun lawan.

signal preview_hover(data: Dictionary, source: Node)
signal preview_exit(source: Node)
signal preview_pin(data: Dictionary, source: Node)

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HEADER_ME := Color(0.18, 0.34, 0.54, 1.0)
const HEADER_OPP := Color(0.56, 0.20, 0.22, 1.0)

@onready var _root: Control = $Root
@onready var _drawer: PanelContainer = $Root/Drawer
@onready var _header_panel: PanelContainer = $Root/Drawer/V/HeaderPanel
@onready var _owner_lbl: Label = $Root/Drawer/V/HeaderPanel/H/Titles/Owner
@onready var _grid: GridContainer = $Root/Drawer/V/Scroll/Grid
@onready var _empty_lbl: Label = $Root/Drawer/V/Empty
@onready var _btn_all: Button = $Root/Drawer/V/FilterBar/All
@onready var _btn_basic: Button = $Root/Drawer/V/FilterBar/Basic
@onready var _btn_spell: Button = $Root/Drawer/V/FilterBar/Spell
@onready var _btn_special: Button = $Root/Drawer/V/FilterBar/Special

var _cards: Array = []
var _viewing_me := true
var _filter := "all"       # all | basic | spell | special
var _thumb_size := Vector2(180, 244)

func _ready() -> void:
	_root.hide()
	$Root/Drawer/V/HeaderPanel/H/Close.pressed.connect(close)
	$Root/Dim.gui_input.connect(_on_dim_input)
	_btn_all.pressed.connect(_set_filter.bind("all"))
	_btn_basic.pressed.connect(_set_filter.bind("basic"))
	_btn_spell.pressed.connect(_set_filter.bind("spell"))
	_btn_special.pressed.connect(_set_filter.bind("special"))
	get_viewport().size_changed.connect(_on_viewport_resized)
	_resize_drawer()

func _on_viewport_resized() -> void:
	_resize_drawer()
	if _root.visible:
		_render_grid()

func _resize_drawer() -> void:
	if not is_instance_valid(_drawer):
		return
	var vp := get_viewport().get_visible_rect().size
	var w := roundf(clampf(vp.x / 3.0, 420.0, 760.0))
	_drawer.offset_left = 0.0
	_drawer.offset_right = w
	_grid.columns = 3
	var avail_w := maxf(w - 52.0, 300.0)
	var card_w := floorf(avail_w / 3.0)
	_thumb_size = Vector2(card_w, roundf(card_w * 1.36))

func open(cards: Array, owner_title: String, is_me: bool) -> void:
	_resize_drawer()
	_cards = cards.duplicate(true)
	_viewing_me = is_me
	_filter = "all"
	_owner_lbl.text = owner_title
	_apply_header_color(is_me)
	_update_counts()
	_refresh_filter_styles()
	_render_grid()
	_root.show()

func refresh_if_open(v: Dictionary, is_local_test := false) -> void:
	if not _root.visible or v.is_empty():
		return
	var cards: Array = v.me.discard if _viewing_me else v.opp.get("discard", [])
	var me_idx := int(v.get("me_index", 0))
	var title := _owner_title(_viewing_me, me_idx, is_local_test)
	_cards = cards.duplicate(true)
	_owner_lbl.text = title
	_update_counts()
	_render_grid()

func close() -> void:
	_root.hide()

func is_open() -> bool:
	return _root.visible

func _owner_title(is_me: bool, me_idx: int, is_local_test: bool) -> String:
	if is_local_test:
		var p := me_idx if is_me else (1 - me_idx)
		return "Pemain %d" % (p + 1)
	return "Kamu" if is_me else "Lawan"

func _apply_header_color(is_me: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 14.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.bg_color = HEADER_ME if is_me else HEADER_OPP
	_header_panel.add_theme_stylebox_override("panel", sb)

func _set_filter(f: String) -> void:
	_filter = f
	_refresh_filter_styles()
	_render_grid()

func _update_counts() -> void:
	var n_basic := 0
	var n_spell := 0
	var n_special := 0
	for c in _cards:
		var d: CardData = CardDB.get_card(String(c.get("id", "")))
		if d == null:
			continue
		match d.type:
			CardData.Type.BASIC: n_basic += 1
			CardData.Type.SPELL: n_spell += 1
			CardData.Type.SPECIAL: n_special += 1
	_btn_all.text = "SEMUA\n%d" % _cards.size()
	_btn_basic.text = "DASAR\n%d" % n_basic
	_btn_spell.text = "SPELL\n%d" % n_spell
	_btn_special.text = "SENYAWA\n%d" % n_special

func _refresh_filter_styles() -> void:
	var btns := {"all": _btn_all, "basic": _btn_basic, "spell": _btn_spell, "special": _btn_special}
	var active_line := Color(0.88, 0.78, 0.34, 1.0)
	for k in btns:
		var b: Button = btns[k]
		var on: bool = (k == _filter)
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		sb.bg_color = Color(0.14, 0.17, 0.21, 1.0) if on else Color(0.09, 0.11, 0.14, 1.0)
		sb.border_width_bottom = 3 if on else 0
		sb.border_color = active_line
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0) if on else Color(0.62, 0.68, 0.76))

func _render_grid() -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()

	# Tampilkan dari kartu terbaru dibuang di paling atas (urutan balik)
	var shown: Array = []
	for i in range(_cards.size() - 1, -1, -1):
		var c: Dictionary = _cards[i]
		var d: CardData = CardDB.get_card(String(c.get("id", "")))
		if d == null:
			continue
		if _filter == "basic" and d.type != CardData.Type.BASIC:
			continue
		if _filter == "spell" and d.type != CardData.Type.SPELL:
			continue
		if _filter == "special" and d.type != CardData.Type.SPECIAL:
			continue
		shown.append(c)

	_empty_lbl.visible = shown.is_empty()
	for c in shown:
		var n: Control = CARD_SCENE.instantiate()
		_grid.add_child(n)
		n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.fit(_thumb_size)
		n.setup(c, true, false, true)
		n.preview_hover.connect(func(d, s): preview_hover.emit(d, s))
		n.preview_exit.connect(func(s): preview_exit.emit(s))
		n.preview_pin.connect(func(d, s): preview_pin.emit(d, s))

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()
