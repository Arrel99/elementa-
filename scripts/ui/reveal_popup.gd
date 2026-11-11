extends PopupPanel

## Popup efek Spektrometer (bagian 8 / Lampiran C):
## lihat 3 kartu teratas deck sendiri, ambil 1 ke tangan, lalu deck diacak.
## Efek hanya dikirim ke pemain yang memainkannya, jadi popup ini hanya
## muncul di layar pemilik efek.
##
## Sejak v0.8.0 ketiga kartu ditampilkan sebagai kartu sungguhan
## (`card.tscn`) yang dijejer kiri-tengah-kanan. Pemain MEMILIH dulu — kartu
## terpilih menyala seperti kartu yang bisa dimainkan — baru menekan
## Konfirmasi, jadi pilihan masih bisa dibatalkan dengan mengklik ulang.
## Tombol Konfirmasi **selalu bisa diklik**; bila belum ada yang dipilih,
## kartu paling kiri yang diambil (aturan tetap: harus ambil 1 kartu).

signal resolved(take_uid: int)

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_SIZE := Vector2(140, 187)
const POPUP_SIZE := Vector2i(500, 440)

@onready var _row: HBoxContainer = $V/Row

var _cards: Array = []
var _nodes: Array = []
var _picked := -1

func _ready() -> void:
	$V/Confirm.pressed.connect(_on_confirm)

func show_spektrometer(cards: Array) -> void:
	_cards = cards.duplicate(true)
	_picked = -1
	_nodes.clear()
	for ch in _row.get_children():
		ch.queue_free()
	for c in _cards:
		var n := CARD_SCENE.instantiate()
		_row.add_child(n)
		n.fit(CARD_SIZE)
		n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.setup(c, true, true, false)     # bisa diklik, tanpa pratinjau besar
		n.clicked.connect(_on_card_clicked)
		_nodes.append(n)
	# Popup (Window) ikut memanjang kalau isinya full-rect, jadi ukurannya
	# dikunci eksplisit: min = max = POPUP_SIZE.
	min_size = POPUP_SIZE
	max_size = POPUP_SIZE
	popup_centered(POPUP_SIZE)

## Klik kartu = memilih; klik kartu yang sama lagi = membatalkan pilihan.
func _on_card_clicked(uid: int) -> void:
	_picked = -1 if _picked == uid else uid
	_refresh_glow()

func _refresh_glow() -> void:
	for n in _nodes:
		n.set_playable(int(n.uid) == _picked)

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
