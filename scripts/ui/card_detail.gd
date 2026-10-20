extends PopupPanel

## Popup detail kartu untuk Library (bab 7.2).

func show_card(id: String) -> void:
    var d: CardData = CardDB.get_card(id)
    if d == null:
        return
    $V/Name.text = d.display_name
    $V/Symbol.text = "Simbol: %s | Nomor atom: %d | Poin: %d" % [d.symbol, d.atomic_number, d.points]
    $V/Desc.text = d.description
    var recipe := ""
    if d.type == CardData.Type.SPECIAL and d.recipe.size() == 2:
        recipe = "Resep: %s + %s" % [CardDB.get_card(d.recipe[0]).symbol, CardDB.get_card(d.recipe[1]).symbol]
    elif d.type == CardData.Type.SPELL:
        recipe = "Efek: %s" % d.spell_effect
    $V/Recipe.text = recipe
    $V/CT.text = d.ct_note if d.ct_note != "" else "Catatan Computational Thinking belum diisi."
    popup_centered(Vector2i(440, 380))
