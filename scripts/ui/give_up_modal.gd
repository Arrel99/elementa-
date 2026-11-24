extends CanvasLayer

## Modal konfirmasi Menyerah bergaya matte minimalis (seragam dengan ResultModal & CoinFlipOverlay).

signal confirmed

@onready var _card: PanelContainer = $Root/Center/Card

func _ready() -> void:
	hide()
	$Root/Center/Card/V/Buttons/Cancel.pressed.connect(close)
	$Root/Center/Card/V/Buttons/Confirm.pressed.connect(_on_confirm)
	$Root/Dim.gui_input.connect(_on_dim_input)

func popup_centered() -> void:
	show()
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.88, 0.88)
	_card.modulate.a = 0.0
	var tw := _card.create_tween().set_parallel(true)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.16)

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _on_confirm() -> void:
	hide()
	confirmed.emit()

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()
