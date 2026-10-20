extends PopupPanel

## Popup menampilkan isi tangan lawan (Spektrometer, bab 5.1).
## Hasilnya hanya dikirim ke pemain yang memainkan spell.

@onready var _list: VBoxContainer = $V/List

func show_cards(cards: Array) -> void:
    for ch in _list.get_children():
        ch.queue_free()
    if cards.is_empty():
        var l := Label.new()
        l.text = "Tangan lawan kosong."
        _list.add_child(l)
    for c in cards:
        var d: CardData = CardDB.get_card(c.get("id", ""))
        var l := Label.new()
        if d != null:
            l.text = "%s (%s, %d poin)" % [d.display_name, d.symbol, d.points]
        else:
            l.text = String(c.get("id", "?"))
        _list.add_child(l)
    popup_centered(Vector2i(360, 320))
