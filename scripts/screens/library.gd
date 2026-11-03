extends Control

## Library tiga tab: Kartu Dasar, Spell, Spesial (bab 7.2).

func _ready() -> void:
    _fill($Tabs/Dasar/Grid, CardDB.ids_of(CardData.Type.BASIC))
    _fill($Tabs/Spell/Grid, CardDB.ids_of(CardData.Type.SPELL))
    _fill($Tabs/Spesial/Grid, CardDB.ids_of(CardData.Type.SPECIAL))
    $Back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn"))

func _fill(grid: Container, ids: Array) -> void:
    for id in ids:
        var n := preload("res://scenes/ui/card.tscn").instantiate()
        grid.add_child(n)
        n.setup({"uid": -1, "id": id, "placed_turn": -1}, true)
        n.clicked.connect(func(_u): $Detail.show_card(id))
