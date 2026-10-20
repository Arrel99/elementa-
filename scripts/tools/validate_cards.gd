@tool
extends EditorScript

## Validator data kartu (bab 11.2).
## Buka di editor script lalu File > Run (Ctrl+Shift+X).

func _run() -> void:
    var errors: Array[String] = []
    var ids := {}
    var recipes := {}
    var cards: Array[CardData] = []
    for f in DirAccess.get_files_at("res://data/cards"):
        if f.ends_with(".tres"):
            var c: CardData = load("res://data/cards/" + f)
            cards.append(c)
            if ids.has(c.id):
                errors.append("Id ganda: %s" % c.id)
            ids[c.id] = true
    for c in cards:
        if c.type == CardData.Type.SPECIAL:
            if c.recipe.size() != 2:
                errors.append("%s: resep harus 2 kartu dasar" % c.id)
                continue
            for r in c.recipe:
                if not ids.has(r):
                    errors.append("%s: bahan %s tidak ada" % [c.id, r])
            var pair := [str(c.recipe[0]), str(c.recipe[1])]
            pair.sort()
            var key: String = pair[0] + "|" + pair[1]
            if recipes.has(key):
                errors.append("Resep ganda: %s dan %s" % [c.id, recipes[key]])
            recipes[key] = c.id
        if c.type == CardData.Type.SPELL and c.spell_effect == "":
            errors.append("%s: spell tanpa efek" % c.id)
        if c.art == null:
            print("Peringatan: %s belum punya ilustrasi" % c.id)
    print("Semua kartu valid." if errors.is_empty() else "\n".join(errors))
