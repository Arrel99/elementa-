extends PanelContainer

## Kartu di papan (bab 4.1). UI hanya membaca data dan mengirim sinyal klik.

signal clicked(uid: int)

var uid := -1

func setup(card: Dictionary, face_up := true) -> void:
    uid = int(card.get("uid", -1))
    var id := String(card.get("id", ""))
    var show_face := face_up and id != "back" and CardDB.cards.has(id)
    if not show_face:
        $V/Name.text = "?" if id == "back" else id
        $V/Info.text = ""
        $V/Desc.text = ""
        $V/Art.texture = null
        return
    var data: CardData = CardDB.get_card(id)
    $V/Name.text = data.display_name
    $V/Info.text = "%s  (%d poin)" % [data.symbol, data.points]
    $V/Desc.text = data.description
    $V/Art.texture = data.art

func _gui_input(e: InputEvent) -> void:
    if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
        clicked.emit(uid)
