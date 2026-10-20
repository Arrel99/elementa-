extends Node

## Autoload CardDB (bab 2.3). Memuat semua kartu .tres dan GameRules.
## Id kartu disimpan sebagai String (bukan StringName) agar aman lewat jaringan
## (lihat bab 6.7 butir 2).

var cards: Dictionary = {}   # String id -> CardData
var rules: GameRules

func _ready() -> void:
    var rp := "res://data/game_rules.tres"
    if ResourceLoader.exists(rp):
        rules = load(rp)
    if rules == null:
        rules = GameRules.new()
    var dir := DirAccess.open("res://data/cards")
    if dir == null:
        return
    for f in dir.get_files():
        var path := "res://data/cards/" + f.trim_suffix(".remap")
        if path.ends_with(".tres"):
            var c: CardData = load(path)
            if c != null:
                cards[String(c.id)] = c

func get_card(id) -> CardData:
    return cards.get(String(id))

func has_card(id) -> bool:
    return cards.has(String(id))

func ids_of(type: CardData.Type) -> Array:
    var out: Array = []
    for c in cards.values():
        if c.type == type:
            out.append(c.id)
    out.sort()
    return out

func find_recipe(a, b) -> String:
    a = String(a)
    b = String(b)
    for c in cards.values():
        if c.type == CardData.Type.SPECIAL and c.recipe.size() == 2:
            if (c.recipe[0] == a and c.recipe[1] == b) or \
               (c.recipe[0] == b and c.recipe[1] == a):
                return c.id
    return ""

## Jejak data kartu untuk cek versi antar pemain (bab 6.7 butir 3).
func cards_hash() -> int:
    var keys := cards.keys()
    keys.sort()
    var s := ""
    for k in keys:
        var c: CardData = cards[k]
        s += "%s|%d|%d|%d|%s;" % [k, c.type, c.points, c.deck_copies, ",".join(PackedStringArray(c.recipe))]
    return s.hash()
