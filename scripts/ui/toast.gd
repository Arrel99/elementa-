extends PanelContainer

## Toast pesan error/informasi di tengah layar (bab 4.5).

@onready var _label: Label = $Label

func _ready() -> void:
    hide()
    modulate.a = 0.0

func show_text(msg: String) -> void:
    _label.text = msg
    show()
    modulate.a = 1.0
    var t := create_tween()
    t.tween_interval(2.0)
    t.tween_property(self, "modulate:a", 0.0, 0.4)
    t.tween_callback(hide)
