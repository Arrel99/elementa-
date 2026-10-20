extends Node

## Autoload EventLog (bab 13.1). Menulis satu baris JSON per aksi
## ke user://logs supaya bisa dipakai untuk evaluasi (kurva belajar).
## Sengaja tidak mencatat nama atau identitas pemain.

var _file: FileAccess

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute("user://logs")
    var stamp := Time.get_datetime_string_from_system().replace(":", "-")
    _file = FileAccess.open("user://logs/%s.jsonl" % stamp, FileAccess.WRITE)

func log_event(kind: String, data := {}) -> void:
    if _file == null:
        return
    data["t"] = Time.get_ticks_msec()
    data["kind"] = kind
    _file.store_line(JSON.stringify(data))
    _file.flush()
