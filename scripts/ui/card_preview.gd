extends CanvasLayer

## Pratinjau kartu besar (hover di sisi kiri, klik kanan di tengah layar).
## Mendukung tumpukan kartu menempel (kartu senyawa + 2 unsur dasarnya):
## kartu di belakang bisa diklik langsung atau digeser dengan tombol < / >
## untuk dibawa ke depan seperti di Pokemon TCG Live.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HOVER_DELAY := 0.2
const BASE_SIZE := Vector2(360, 480)
const MIN_SCALE := 0.55
const MAX_SCALE := 1.35
const MAX_WIDTH_RATIO := 0.44
const MAX_HEIGHT_RATIO := 0.80
const HINT_SPACE := 76.0

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _center: CenterContainer = $Root/Center
@onready var _box: VBoxContainer = $Root/Center/Box
@onready var _hint: Label = $Root/Center/Box/Hint

var _stack: Control
var _slots: Array[Control] = []
var _badges: Array[Label] = []
var _nav_bar: HBoxContainer
var _nav_prev: Button
var _nav_lbl: Label
var _nav_next: Button

var _timer: Timer
var _source: Node = null
var _data := {}
var _stack_cards: Array = []        # [kartu utama, unsur 1, unsur 2]
var _active_idx := 0
var _pinned := false
var _open := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = HOVER_DELAY
	_timer.timeout.connect(_on_timer)
	add_child(_timer)

	# Wadah tumpukan kartu interaktif (maks 3 kartu: 1 senyawa + 2 unsur menempel)
	_stack = Control.new()
	_stack.name = "CardStack"
	_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_box.add_child(_stack)
	_box.move_child(_stack, 0)

	for i in 3:
		var slot: Control = CARD_SCENE.instantiate()
		slot.visible = false
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_slot_input.bind(i))
		_stack.add_child(slot)
		_slots.append(slot)

		# Lencana simbol di pojok kanan atas supaya kartu di belakang tetap terbaca
		var badge := Label.new()
		badge.name = "PeekBadge"
		badge.visible = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
		badge.add_theme_font_size_override("font_size", 18)
		var bsb := StyleBoxFlat.new()
		bsb.content_margin_left = 8.0
		bsb.content_margin_right = 8.0
		bsb.content_margin_top = 4.0
		bsb.content_margin_bottom = 4.0
		bsb.bg_color = Color(0.16, 0.24, 0.34, 0.96)
		bsb.border_width_left = 1
		bsb.border_width_top = 1
		bsb.border_width_right = 1
		bsb.border_width_bottom = 1
		bsb.border_color = Color(0.45, 0.68, 0.85, 1.0)
		bsb.corner_radius_top_left = 6
		bsb.corner_radius_top_right = 6
		bsb.corner_radius_bottom_right = 6
		bsb.corner_radius_bottom_left = 6
		badge.add_theme_stylebox_override("normal", bsb)
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.anchor_top = 0.0
		badge.anchor_bottom = 0.0
		badge.offset_left = -64.0
		badge.offset_top = 8.0
		badge.offset_right = -8.0
		badge.offset_bottom = 38.0
		var ov: Node = slot.get_node_or_null("Overlay")
		if ov != null:
			ov.add_child(badge)
		else:
			slot.add_child(badge)
		_badges.append(badge)

	_build_nav_bar()

	_dim.gui_input.connect(_on_dim_input)
	_root.hide()
	set_process(false)

func _build_nav_bar() -> void:
	_nav_bar = HBoxContainer.new()
	_nav_bar.name = "StackNav"
	_nav_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_nav_bar.add_theme_constant_override("separation", 12)
	_nav_bar.visible = false

	_nav_prev = _make_nav_btn("<")
	_nav_prev.pressed.connect(_step_active.bind(-1))
	_nav_bar.add_child(_nav_prev)

	_nav_lbl = Label.new()
	_nav_lbl.text = "1 / 3"
	_nav_lbl.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98, 1.0))
	_nav_lbl.add_theme_font_size_override("font_size", 15)
	_nav_bar.add_child(_nav_lbl)

	_nav_next = _make_nav_btn(">")
	_nav_next.pressed.connect(_step_active.bind(1))
	_nav_bar.add_child(_nav_next)

	_box.add_child(_nav_bar)
	_box.move_child(_nav_bar, 1)

func _make_nav_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(40, 32)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.17, 0.22, 0.96)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.32, 0.44, 0.56, 1.0)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.20, 0.26, 0.34, 1.0)
	b.add_theme_stylebox_override("hover", sbh)
	return b

# --- API untuk papan ---------------------------------------------------------

func hover(data: Dictionary, source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	if _pinned:
		return
	if _open and _source == source:
		_timer.stop()
		return
	_source = source
	_data = data.duplicate(true)
	_timer.start()

func unhover(source: Node) -> void:
	if _pinned or _source != source:
		return
	if _open and _is_mouse_over_preview():
		return
	_timer.stop()
	hide_preview()

func pin(data: Dictionary, source: Node) -> void:
	if _open and _pinned and _source == source:
		hide_preview()
		return
	_timer.stop()
	_source = source
	_data = data.duplicate(true)
	_pinned = true
	_show()

func hide_preview() -> void:
	_timer.stop()
	_open = false
	_pinned = false
	_source = null
	_stack_cards.clear()
	_active_idx = 0
	set_process(false)
	if is_instance_valid(_root):
		_root.hide()

func is_open() -> bool:
	return _open

# --- Isi & Interaksi Tumpukan Kartu ------------------------------------------

func _on_timer() -> void:
	if _source == null or not is_instance_valid(_source):
		return
	_show()

func _show() -> void:
	if _data.is_empty():
		return
	_stack_cards = [_data]
	var attached: Array = _data.get("attached", [])
	for i in mini(attached.size(), 2):
		_stack_cards.append(attached[i])
	_active_idx = 0

	_apply_position()
	_render_stack(false)

	_dim.visible = _pinned
	_hint.visible = _pinned
	_root.show()
	_open = true
	set_process(true)

func _render_stack(animate: bool) -> void:
	var target := _target_size()
	var count := _stack_cards.size()
	var has_multi := count > 1
	var peek_step := target.x * 0.24
	var extra_w := peek_step * float(maxi(count - 1, 0))
	_stack.custom_minimum_size = Vector2(target.x + extra_w, target.y + (16.0 if has_multi else 0.0))

	# Susun urutan tampilan: kartu aktif di depan (order 0), sisanya mengintip rapi ke kanan
	var order: Array[int] = [_active_idx]
	for i in count:
		if i != _active_idx:
			order.append(i)

	for i in _slots.size():
		var slot: Control = _slots[i]
		var badge: Label = _badges[i]
		if i >= count:
			slot.visible = false
			continue
		var cdata: Dictionary = _stack_cards[i]
		var depth := order.find(i)       # 0 = paling depan, 1..2 = di belakang
		var is_front := (depth == 0)
		var sz := target if is_front else (target * (0.94 - float(depth - 1) * 0.03)).round()
		var pos := Vector2(float(depth) * peek_step, float(depth) * (target.y * 0.03))

		slot.setup(cdata, true, false, false)
		slot.tooltip_text = ""
		slot.fit(sz)
		slot.size = sz
		slot.visible = true
		slot.z_index = 10 - depth
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if has_multi else Control.MOUSE_FILTER_IGNORE
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (has_multi and not is_front) else Control.CURSOR_ARROW
		_append_recipe_to(slot, cdata)

		var target_mod := Color.WHITE if is_front else Color(0.82, 0.86, 0.92, 1.0)
		if animate:
			var tw := slot.create_tween().set_parallel(true)
			tw.tween_property(slot, "position", pos, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(slot, "modulate", target_mod, 0.16)
		else:
			slot.position = pos
			slot.modulate = target_mod

		# Tampilkan lencana simbol di sisi kanan atas kartu belakang agar langsung terbaca
		if has_multi and not is_front:
			var d: CardData = CardDB.get_card(String(cdata.get("id", "")))
			badge.text = d.symbol if (d != null and d.symbol != "") else String(cdata.get("id", ""))
			badge.visible = true
		else:
			badge.visible = false

	_nav_bar.visible = has_multi
	if has_multi:
		var active_d: CardData = CardDB.get_card(String(_stack_cards[_active_idx].get("id", "")))
		var active_name := active_d.display_name if active_d != null else ""
		_nav_lbl.text = "%d / %d  •  %s" % [_active_idx + 1, count, active_name]

func _on_slot_input(e: InputEvent, idx: int) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	var mb := e as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and idx < _stack_cards.size():
		if _stack_cards.size() > 1:
			# Klik kartu di belakang: bawa kartu itu ke depan dan tahan pratinjau agar mudah dibaca
			_active_idx = idx
			if not _pinned:
				_pinned = true
				_dim.visible = true
				_hint.visible = true
				_apply_position()
			_render_stack(true)
			get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and _pinned:
		hide_preview()
		get_viewport().set_input_as_handled()

func _step_active(dir: int) -> void:
	if _stack_cards.size() <= 1:
		return
	_active_idx = (_active_idx + dir + _stack_cards.size()) % _stack_cards.size()
	if not _pinned:
		_pinned = true
		_dim.visible = true
		_hint.visible = true
		_apply_position()
	_render_stack(true)

func _unhandled_input(e: InputEvent) -> void:
	if not _open or not _pinned or _stack_cards.size() <= 1:
		return
	if e.is_action_pressed("ui_right"):
		_step_active(1)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_left"):
		_step_active(-1)
		get_viewport().set_input_as_handled()

func _apply_position() -> void:
	if _pinned:
		_center.anchor_left = 0.0
		_center.anchor_right = 1.0
		_center.anchor_top = 0.0
		_center.anchor_bottom = 1.0
		_center.offset_left = 0.0
		_center.offset_top = 0.0
	else:
		_center.anchor_left = 0.0
		_center.anchor_right = 0.38
		_center.anchor_top = 0.08
		_center.anchor_bottom = 0.96
		_center.offset_left = 18.0
		_center.offset_top = 0.0

func _append_recipe_to(card_node: Control, cdata: Dictionary) -> void:
	var d: CardData = CardDB.get_card(String(cdata.get("id", "")))
	if d == null or d.type != CardData.Type.SPECIAL or d.recipe.size() != 2:
		return
	var a := CardDB.get_card(d.recipe[0])
	var b := CardDB.get_card(d.recipe[1])
	if a == null or b == null:
		return
	var desc: Label = card_node.get_node("V/Desc")
	desc.text = "%s\n\nResep: %s + %s" % [d.description, a.symbol, b.symbol]

func _is_mouse_over_preview() -> bool:
	var mp: Vector2 = _stack.get_global_mouse_position()
	if _stack.get_global_rect().has_point(mp):
		return true
	if _nav_bar.visible and _nav_bar.get_global_rect().has_point(mp):
		return true
	return false

func _process(_dt: float) -> void:
	if not _open or _pinned:
		return
	if _source == null or not is_instance_valid(_source):
		hide_preview()
		return
	var mp: Vector2 = _stack.get_global_mouse_position()
	if _source is Control and (_source as Control).get_global_rect().has_point(mp):
		return
	if _source.has_method("is_hovered_3d") and _source.is_hovered_3d():
		return
	if _is_mouse_over_preview():
		return
	hide_preview()

func _target_size() -> Vector2:
	var area := _root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	var w_ratio := MAX_WIDTH_RATIO if _pinned else 0.28
	var h_ratio := MAX_HEIGHT_RATIO if _pinned else 0.72
	var max_w := area.x * w_ratio
	var max_h := area.y * h_ratio - HINT_SPACE
	var s := minf(max_w / BASE_SIZE.x, max_h / BASE_SIZE.y)
	s = clampf(s, MIN_SCALE, MAX_SCALE if _pinned else 1.12)
	return (BASE_SIZE * s).round()

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		hide_preview()
