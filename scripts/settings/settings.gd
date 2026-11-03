extends Node

## Autoload Settings (bab 7.6). Menyimpan volume dan bahasa antar sesi.

const PATH := "user://settings.cfg"

var cfg := ConfigFile.new()

func _ready() -> void:
    cfg.load(PATH)   # tidak error jika file belum ada
    AudioServer.set_bus_volume_db(0, linear_to_db(get_value("audio", "master", 0.8)))
    TranslationServer.set_locale(get_value("ui", "locale", "id"))

func get_value(sec: String, key: String, default: Variant) -> Variant:
    return cfg.get_value(sec, key, default)

func set_value(sec: String, key: String, value: Variant) -> void:
    cfg.set_value(sec, key, value)
    cfg.save(PATH)
