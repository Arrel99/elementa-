extends CanvasLayer

## Overlay pemilihan efek Spektrometer bergaya Pokemon TCG Live:
## - Baris atas: 3 kartu teratas deck (kiri/tengah) + kartu Spektrometer (kanan)
## - Banner horizontal tengah: instruksi + tombol KONFIRMASI + tombol LIHAT PAPAN
## - Slot bawah: menampilkan kartu yang sedang dipilih sebelum dikonfirmasi

signal resolved(take_uid: int)

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_SIZE := Vector2(186, 248)
const PICKED_SIZE := Vector2(158, 212)

@onready var _dim: ColorRect = $Root/Dim
@onready var _content: Control = $Root/Content
@onready var _row: HBoxContainer = $Root/Content/TopStage/Row
@onready var _source_slot: CenterContainer = $Root/Content/TopStage/SourceFrame/SourceSlot
@onready var _picked_placeholder: Label = $Root/Content/PickedWrap/PickedSlot/Placeholder
@onready var _picked_holder: CenterContainer = $Root/Content/PickedWrap/PickedSlot/CardHolder
@onready var _confirm_btn: Button = $Root/Content/Banner/H/Confirm
@onready var _inspect_btn: Button = $Root/InspectBtn

var _cards: Array = []
var _nodes: Array[Control] = []
var _picked := -1
var _inspecting := false
var _picked_card_node: Control = null

func _ready() -> void:
	hide()
	_confirm_btn.pressed.connect(_on_confirm)
	_inspect_btn.pressed.connect(_toggle_inspect)

	# Tampilkan kartu Spektrometer di sisi kanan atas (seperti kartu Trainer di Pokemon TCG Live)
	var src: Control = CARD_SCENE.instantiate()
	_source_slot.add_child(src)
	src.fit(CARD_SIZE)
	src.setup({"uid": -1, "id": "spektrometer", "placed_turn": -1}, true, false, false)

func show_spektrometer(cards: Array) -> void:
	_cards = cards.duplicate(true)
	_picked = -1
	_inspecting = false
	_apply_inspect()
	_nodes.clear()

	for ch in _row.get_children():
		_row.remove_child(ch)
		ch.queue_free()

	for c in _cards:
		var n: Control = CARD_SCENE.instantiate()
		_row.add_child(n)
		n.fit(CARD_SIZE)
		n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.setup(c, true, true, false)
		n.clicked.connect(_on_card_clicked)
		_nodes.append(n)

	_refresh_selection()
	show()

func _toggle_inspect() -> void:
	_inspecting = not _inspecting
	_apply_inspect()

func _apply_inspect() -> void:
	_dim.visible = not _inspecting
	_content.visible = not _inspecting
	if _inspecting:
		_inspect_btn.text = "<  KEMBALI KE SPEKTROMETER"
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		sb.bg_color = Color(0.18, 0.44, 0.42, 0.98)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(0.42, 0.78, 0.72, 1.0)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_right = 8
		sb.corner_radius_bottom_left = 8
		_inspect_btn.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate() as StyleBoxFlat
		sbh.bg_color = Color(0.22, 0.54, 0.50, 1.0)
		_inspect_btn.add_theme_stylebox_override("hover", sbh)
	else:
		_inspect_btn.text = "LIHAT PAPAN"
		_inspect_btn.remove_theme_stylebox_override("normal")
		_inspect_btn.remove_theme_stylebox_override("hover")

func _unhandled_input(e: InputEvent) -> void:
	if visible and _inspecting and e.is_action_pressed("ui_cancel"):
		_inspecting = false
		_apply_inspect()
		get_viewport().set_input_as_handled()

func _on_card_clicked(uid: int) -> void:
	_picked = -1 if _picked == uid else uid
	_refresh_selection()

func _refresh_selection() -> void:
	var picked_data: Dictionary = {}
	for i in _nodes.size():
		var n: Control = _nodes[i]
		var is_sel := (int(n.uid) == _picked)
		n.set_playable(is_sel)
		n.modulate = Color(0.55, 0.60, 0.68, 0.72) if is_sel else Color.WHITE
		if is_sel and i < _cards.size():
			picked_data = _cards[i]

	if is_instance_valid(_picked_card_node):
		_picked_card_node.queue_free()
		_picked_card_node = null

	if picked_data.is_empty():
		_picked_placeholder.visible = true
		return

	_picked_placeholder.visible = false
	var pn: Control = CARD_SCENE.instantiate()
	_picked_holder.add_child(pn)
	pn.fit(PICKED_SIZE)
	pn.pivot_offset = PICKED_SIZE * 0.5
	pn.setup(picked_data, true, true, false)
	pn.clicked.connect(func(_u): _on_card_clicked(_picked))
	pn.scale = Vector2(0.86, 0.86)
	var tw := pn.create_tween()
	tw.tween_property(pn, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_picked_card_node = pn

## Tombol konfirmasi selalu aktif. Bila belum ada pilihan, kartu paling kiri
## yang diambil supaya efek selalu selesai dan permainan tidak tersangkut.
func _on_confirm() -> void:
	var take := _picked
	if take == -1 and not _cards.is_empty():
		take = int(_cards[0].get("uid", -1))
	if take == -1:
		return
	resolved.emit(take)
	hide()
