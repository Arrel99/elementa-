extends PanelContainer

## Kartu full-art di tangan, pratinjau, Discard Pile, dan Library.
## Menampilkan gambar kartu lengkap (data.art) tanpa teks placeholder.

signal clicked(uid: int)
signal info_clicked(card_id: String)
signal drag_started(uid: int, card_node: Control, global_pos: Vector2)
signal drag_moved(uid: int, card_node: Control, global_pos: Vector2)
signal drag_ended(uid: int, card_node: Control, global_pos: Vector2)
signal preview_hover(data: Dictionary, source: Node)
signal preview_exit(source: Node)
signal preview_pin(data: Dictionary, source: Node)

var uid := -1
var interactive := false
var draggable := false
var previewable := false

var _hovered := false
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _data := {}
var _play_tween: Tween

func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	var info_btn: Button = get_node_or_null("Overlay/InfoBtn")
	if info_btn != null:
		info_btn.pressed.connect(func():
			var cid := String(_data.get("id", ""))
			if cid != "":
				info_clicked.emit(cid))
	resized.connect(refresh_hover)

func setup(card: Dictionary, face_up := true, can_click := true,
		can_preview := true) -> void:
	uid = int(card.get("uid", -1))
	interactive = can_click
	var id := String(card.get("id", ""))
	var show_face := face_up and id != "back" and CardDB.cards.has(id)
	previewable = can_preview and show_face
	_data = card.duplicate(true)
	mouse_filter = (
		MOUSE_FILTER_STOP if can_click or previewable else MOUSE_FILTER_IGNORE)
	mouse_default_cursor_shape = (
		CURSOR_POINTING_HAND if can_click else CURSOR_ARROW)
	tooltip_text = ""

	var art_rect: TextureRect = $Art
	var back_node: Control = $CardBack
	if not show_face:
		art_rect.visible = false
		art_rect.texture = null
		back_node.visible = true
		refresh_hover()
		return

	var data: CardData = CardDB.get_card(id)
	art_rect.visible = true
	art_rect.texture = data.art
	back_node.visible = false
	tooltip_text = "%s — %s" % [data.display_name, data.description]
	refresh_hover()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and interactive:
				if draggable:
					_pressed = true
					_dragging = false
					_press_pos = get_global_mouse_position()
					accept_event()
				else:
					clicked.emit(uid)
				return
			if not mb.pressed and _pressed:
				_pressed = false
				if _dragging:
					_dragging = false
					drag_ended.emit(uid, self, get_global_mouse_position())
				else:
					clicked.emit(uid)
				accept_event()
				return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and previewable:
			preview_pin.emit(_data, self)
			accept_event()
			return
	elif e is InputEventMouseMotion and _pressed and draggable:
		var gp := get_global_mouse_position()
		if not _dragging and gp.distance_to(_press_pos) >= 12.0:
			_dragging = true
			drag_started.emit(uid, self, gp)
		if _dragging:
			drag_moved.emit(uid, self, gp)
			accept_event()

func _on_mouse_entered() -> void:
	if previewable:
		preview_hover.emit(_data, self)

func _on_mouse_exited() -> void:
	if previewable:
		preview_exit.emit(self)

func refresh_hover() -> void:
	if not (interactive or previewable) or not is_inside_tree():
		return
	var on := get_global_rect().has_point(get_global_mouse_position())
	var changed := on != _hovered
	_set_hovered(on)
	if changed and on and previewable:
		preview_hover.emit(_data, self)

func _set_hovered(on: bool) -> void:
	if on == _hovered:
		return
	_hovered = on
	var art_rect: TextureRect = $Art
	art_rect.self_modulate = Color(1.08, 1.08, 1.08, 1.0) if on else Color.WHITE

func fit(target_size: Vector2) -> void:
	custom_minimum_size = target_size
	size = target_size

func set_playable(on: bool) -> void:
	var glow: Control = get_node_or_null("Glow")
	if glow == null:
		return
	if _play_tween != null and _play_tween.is_valid():
		_play_tween.kill()
	_play_tween = null
	if not on:
		glow.visible = false
		glow.modulate.a = 0.0
		return
	glow.visible = true
	glow.modulate.a = 0.95
	_play_tween = create_tween().set_loops()
	_play_tween.tween_property(glow, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
	_play_tween.tween_property(glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

## Menampilkan tombol kecil (i) di sudut kanan atas kartu (dipakai di Library).
func set_info_button(on: bool) -> void:
	var info_btn: Button = get_node_or_null("Overlay/InfoBtn")
	if info_btn != null:
		info_btn.visible = on
