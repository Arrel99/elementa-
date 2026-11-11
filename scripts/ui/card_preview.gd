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
const BASE_SIZE := Vector2(320, 430)    # ukuran acuan, diskalakan sesuai layar
const MIN_SCALE := 0.45
const MAX_SCALE := 1.15
const MAX_WIDTH_RATIO := 0.42
const MAX_HEIGHT_RATIO := 0.76
const HINT_SPACE := 40.0                # ruang untuk label petunjuk

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _box: VBoxContainer = $Root/Center/Box
@onready var _hint: Label = $Root/Center/Box/Hint

var _card: Node
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

	_card = CARD_SCENE.instantiate()
	_box.add_child(_card)
	_box.move_child(_card, 0)

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
	var target := _target_size()
	_card.setup(_data, true, false, false)
	_card.tooltip_text = ""             # kartu besar tidak perlu tooltip
	_card.fit(target)
	_append_recipe()

	_dim.visible = _pinned
	_hint.visible = _pinned
	_root.show()
	_open = true
	set_process(true)

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
	if _source.get_global_rect().has_point(mp):
		return
	if _card.get_global_rect().has_point(mp):
		return
	hide_preview()

func _target_size() -> Vector2:
	var area := _root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	var max_w := area.x * MAX_WIDTH_RATIO
	var max_h := area.y * MAX_HEIGHT_RATIO - HINT_SPACE
	var s := minf(max_w / BASE_SIZE.x, max_h / BASE_SIZE.y)
	s = clampf(s, MIN_SCALE, MAX_SCALE)
	return (BASE_SIZE * s).round()

## Latar gelap saat dipin menelan klik supaya kartu di bawahnya tidak
## ikut terpakai; klik di mana saja menutup pratinjau.
func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		hide_preview()
