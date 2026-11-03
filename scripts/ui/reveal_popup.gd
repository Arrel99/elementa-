extends PopupPanel

## Popup efek Spektrometer (bagian 8 / Lampiran C):
## lihat 3 kartu teratas deck sendiri, ambil 1 ke tangan.
## Setelah efek selesai, deck diacak kembali.
## Efek hanya dikirim ke pemain yang memainkannya, jadi popup ini hanya
## muncul di layar pemilik efek.

signal resolved(take_uid: int)

@onready var _list: VBoxContainer = $V/List

var _cards: Array = []

func show_spektrometer(cards: Array) -> void:
	_cards = cards.duplicate(true)
	for ch in _list.get_children():
		ch.queue_free()
	_add_label("Spektrometer: 3 kartu teratas deck kamu.")
	_add_label("Pilih 1 kartu untuk diambil ke tangan. Deck lalu diacak kembali.")
	for c in _cards:
		var b := Button.new()
		b.text = _label(c)
		b.pressed.connect(_choose.bind(int(c.uid)))
		_list.add_child(b)
	popup_centered(Vector2i(440, 320))

func _choose(uid: int) -> void:
	resolved.emit(uid)
	hide()

func _add_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(l)

func _label(c) -> String:
	var d: CardData = CardDB.get_card(c.get("id", ""))
	if d != null:
		return "%s (%s)" % [d.display_name, d.symbol]
	return String(c.get("id", "?"))
