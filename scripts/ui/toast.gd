extends PanelContainer

## Toast pesan error/informasi bergaya matte minimalis di tengah layar.

@onready var _label: Label = $Label

var _tween: Tween

func _ready() -> void:
	hide()
	modulate.a = 0.0

func show_text(msg: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.text = msg
	show()
	reset_size()
	pivot_offset = size * 0.5
	scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.14)
	_tween.chain().tween_interval(2.0)
	_tween.chain().tween_property(self, "modulate:a", 0.0, 0.35)
	_tween.chain().tween_callback(hide)
