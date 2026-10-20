@tool
extends EditorScript

## Pengisi ilustrasi otomatis (opsional).
## Taruh gambar di res://art/cards/ dengan nama = id kartu, lalu jalankan:
## buka skrip ini di editor skrip -> File > Run (Ctrl+Shift+X).

const EXTS := ["png", "webp", "jpg", "jpeg", "svg"]

func _run() -> void:
    if DirAccess.open("res://art/cards") == null:
        print("Folder res://art/cards belum ada.")
        return
    var updated: Array[String] = []
    var missing: Array[String] = []
    for f in DirAccess.get_files_at("res://data/cards"):
        if not f.ends_with(".tres"):
            continue
        var path := "res://data/cards/" + f
        var c: CardData = load(path)
        if c == null:
            continue
        var tex := _find_texture(c.id)
        if tex == null:
            missing.append(c.id)
            continue
        c.art = tex
        ResourceSaver.save(c, path)
        updated.append(c.id)
    print("Terpasang: %d kartu -> %s" % [updated.size(), ", ".join(updated)])
    if not missing.is_empty():
        missing.sort()
        print("Belum ada gambar (%d): %s" % [missing.size(), ", ".join(missing)])

func _find_texture(id: String) -> Texture2D:
    for e in EXTS:
        var p := "res://art/cards/%s.%s" % [id, e]
        if ResourceLoader.exists(p):
            return load(p)
    return null
