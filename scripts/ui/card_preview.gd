extends CanvasLayer

## Pratinjau kartu besar di tengah layar.
##
## Dua pemicu dari papan permainan:
##   - hover     : kartu muncul setelah kursor berhenti ~0,2 detik
##   - klik kanan: kartu "dipin" supaya tetap terbuka (klik kanan lagi,
##                 klik di latar, atau Esc menutupnya)
##
## Node ini sengaja bukan autoload: Library sudah punya popup Detail sendiri,
## jadi pratinjau hanya hidup selama scene papan ada.
##
## Seluruh lapisan memakai mouse_filter IGNORE (kecuali latar gelap saat
## dipin) supaya papan di bawahnya tetap bisa diklik seperti biasa.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

const HOVER_DELAY := 0.2
const BASE_SIZE := Vector2(360, 480)    # ukuran acuan lebih besar agar teks mudah dibaca
const MIN_SCALE := 0.55
const MAX_SCALE := 1.35
const MAX_WIDTH_RATIO := 0.44
const MAX_HEIGHT_RATIO := 0.82
const HINT_SPACE := 40.0                # ruang untuk label petunjuk

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _center: CenterContainer = $Root/Center
@onready var _box: VBoxContainer = $Root/Center/Box
@onready var _hint: Label = $Root/Center/Box/Hint

var _stack: Control
var _card: Node
var _attached_cards: Array[Node] = []
var _timer: Timer
var _source: Node = null
var _data := {}
var _pinned := false
var _open := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = HOVER_DELAY
	_timer.timeout.connect(_on_timer)
	add_child(_timer)

	# Wadah tumpukan: kartu unsur yang menempel mengintip di belakang/kanan kartu senyawa (gaya Pokemon TCG Live)
	_stack = Control.new()
	_stack.name = "CardStack"
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_stack)
	_box.move_child(_stack, 0)

	for i in 2:
		var ac: Control = CARD_SCENE.instantiate()
		ac.visible = false
		ac.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stack.add_child(ac)
		_attached_cards.append(ac)

	_card = CARD_SCENE.instantiate()
	_stack.add_child(_card)

	_dim.gui_input.connect(_on_dim_input)
	_root.hide()
	set_process(false)

# --- API untuk papan ---------------------------------------------------------

## Kursor masuk ke kartu: mulai hitung mundur sebelum pratinjau tampil.
func hover(data: Dictionary, source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	if _pinned:
		return                          # jangan ganggu pratinjau yang dipin
	if _open and _source == source:
		_timer.stop()
		return
	_source = source
	_data = data.duplicate()
	_timer.start()

## Kursor keluar dari kartu: tutup bila pratinjau belum dipin.
func unhover(source: Node) -> void:
	if _pinned or _source != source:
		return                          # masih di kartu lain
	# Bila kartu pratinjau menutupi kartu sumber, kursor "keluar" dari kartu
	# tapi sebenarnya masih di atas pratinjau: jangan tutup supaya tidak
	# berkedip buka-tutup.
	if _open and _card.get_global_rect().has_point(_card.get_global_mouse_position()):
		return
	_timer.stop()
	hide_preview()

## Klik kanan: buka dan tahan. Klik kanan pada kartu yang sama menutupnya.
func pin(data: Dictionary, source: Node) -> void:
	if _open and _pinned and _source == source:
		hide_preview()
		return
	_timer.stop()
	_source = source
	_data = data.duplicate()
	_pinned = true
	_show()

func hide_preview() -> void:
	_timer.stop()
	_open = false
	_pinned = false
	_source = null
	set_process(false)
	if is_instance_valid(_root):
		_root.hide()

func is_open() -> bool:
	return _open

# --- Isi pratinjau -----------------------------------------------------------

func _on_timer() -> void:
	if _source == null or not is_instance_valid(_source):
		return
	_show()

func _show() -> void:
	if _data.is_empty():
		return
	_apply_position()
	var target := _target_size()
	_card.setup(_data, true, false, false)
	_card.tooltip_text = ""             # kartu besar tidak perlu tooltip
	_card.fit(target)
	_card.position = Vector2.ZERO
	_card.size = target
	_append_recipe()
	_render_attached_preview(target)

	_dim.visible = _pinned
	_hint.visible = _pinned
	_root.show()
	_open = true
	set_process(true)

## Menampilkan kartu unsur yang menempel di belakang kartu senyawa (mengintip ke kanan seperti Pokemon TCG Live).
func _render_attached_preview(target: Vector2) -> void:
	var attached: Array = _data.get("attached", [])
	var shown := mini(attached.size(), _attached_cards.size())
	var extra_w := 0.0
	for i in _attached_cards.size():
		var ac: Control = _attached_cards[i]
		if i < shown:
			var sub_sz := (target * 0.94).round()
			ac.setup(attached[i], true, false, false)
			ac.fit(sub_sz)
			ac.size = sub_sz
			ac.position = Vector2(target.x * (0.20 + float(i) * 0.16), target.y * (0.03 + float(i) * 0.02))
			ac.modulate = Color(0.88, 0.91, 0.95, 1.0)
			ac.visible = true
			extra_w = maxf(extra_w, ac.position.x + sub_sz.x - target.x)
		else:
			ac.visible = false
	_stack.custom_minimum_size = Vector2(target.x + extra_w, target.y + (16.0 if shown > 0 else 0.0))

## Saat hover: tampilkan pratinjau di sisi kiri agar tengah papan tetap terlihat.
## Saat dipin (klik kanan): tampilkan di tengah layar dengan latar redup.
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
		_center.anchor_right = 0.34
		_center.anchor_top = 0.10
		_center.anchor_bottom = 0.96
		_center.offset_left = 18.0
		_center.offset_top = 0.0

## Kartu senyawa di papan menampilkan resepnya; di pratinjau resep itu
## ditambahkan ke deskripsi supaya bahan pembuatnya langsung terbaca.
func _append_recipe() -> void:
	var d: CardData = CardDB.get_card(String(_data.get("id", "")))
	if d == null or d.type != CardData.Type.SPECIAL or d.recipe.size() != 2:
		return
	var a := CardDB.get_card(d.recipe[0])
	var b := CardDB.get_card(d.recipe[1])
	if a == null or b == null:
		return
	var desc: Label = _card.get_node("V/Desc")
	desc.text = "%s\n\nResep: %s + %s" % [d.description, a.symbol, b.symbol]

## Pratinjau hover ikut ditutup bila kartu sumbernya hilang (mis. papan
## dirender ulang) atau kursor sudah keluar dari kartu sumber dan dari
## pratinjau tanpa memicu mouse_exited.
func _process(_dt: float) -> void:
	if not _open or _pinned:
		return
	if _source == null or not is_instance_valid(_source):
		hide_preview()
		return
	var mp: Vector2 = _card.get_global_mouse_position()
	if _source is Control and (_source as Control).get_global_rect().has_point(mp):
		return
	if _source.has_method("is_hovered_3d") and _source.is_hovered_3d():
		return
	if _card.get_global_rect().has_point(mp):
		return
	hide_preview()

func _target_size() -> Vector2:
	var area := _root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	var w_ratio := MAX_WIDTH_RATIO if _pinned else 0.30
	var h_ratio := MAX_HEIGHT_RATIO if _pinned else 0.76
	var max_w := area.x * w_ratio
	var max_h := area.y * h_ratio - HINT_SPACE
	var s := minf(max_w / BASE_SIZE.x, max_h / BASE_SIZE.y)
	s = clampf(s, MIN_SCALE, MAX_SCALE if _pinned else 1.18)
	return (BASE_SIZE * s).round()

## Latar gelap saat dipin menelan klik supaya kartu di bawahnya tidak
## ikut terpakai; klik di mana saja menutup pratinjau.
func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		hide_preview()
