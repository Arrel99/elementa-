extends CanvasLayer

## Pengaturan saat di tengah permainan.
##
## Sejak v0.7.0 panel ini adalah OVERLAY (CanvasLayer layer 80) supaya tidak
## memengaruhi tata letak/skala papan sama sekali: tombol gear kecil di pojok
## kanan bawah membuka panel yang menggeser masuk dari tepi kanan, dengan latar
## gelap yang bisa diklik untuk menutup. Tombol **Menyerah** ada di paling bawah.
##
## Panel hanya memancarkan sinyal; keputusan keluar/menyerah tetap di `game.gd`
## supaya aturan permainan tidak ikut di sini.

signal give_up_requested
signal back_to_menu_requested

const PANEL_W := 360.0          # lebar panel (harus sama dengan offset di .tscn)
const ANIM := 0.22              # durasi geser masuk/keluar (detik)

@onready var _dim: ColorRect = $Dim
@onready var _gear: Button = $Gear
@onready var _slide: PanelContainer = $Slide
@onready var _status: Label = $Slide/V/Status
@onready var _volume: HSlider = $Slide/V/VolRow/Volume

var _open := false
var _extra := PANEL_W           # geseran tambahan: 0 = terbuka penuh
var _tween: Tween

func _ready() -> void:
	_dim.visible = false
	_slide.visible = false
	_extra = PANEL_W
	_apply_offset()

	_gear.pressed.connect(toggle)
	_dim.gui_input.connect(_on_dim_input)
	_volume.value_changed.connect(_on_volume)
	$Slide/V/GiveUp.pressed.connect(func() -> void:
		close()
		give_up_requested.emit())
	$Slide/V/ToMenu.pressed.connect(func() -> void:
		close()
		back_to_menu_requested.emit())
	$Slide/V/Close.pressed.connect(close)

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open:
		return
	_open = true
	_volume.set_value_no_signal(Settings.get_value("audio", "master", 0.8))
	_dim.visible = true
	_slide.visible = true
	_gear.visible = false
	_animate(0.0)

func close() -> void:
	if not _open:
		return
	_open = false
	_dim.visible = false
	_gear.visible = true
	_animate(PANEL_W)

## Status singkat di dalam panel (menggantikan teks Turn/Deck yang dulu di HUD).
func set_status(turn_text: String, deck_text: String) -> void:
	_status.text = turn_text if deck_text == "" else "%s\n%s" % [turn_text, deck_text]

# --- Animasi geser -----------------------------------------------------------

func _animate(target_extra: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_extra, _extra, target_extra, ANIM)
	if target_extra > 0.0:
		_tween.tween_callback(func() -> void: _slide.visible = false)

func _set_extra(v: float) -> void:
	_extra = v
	_apply_offset()

## Panel menempel di tepi kanan; `_extra` menggesernya ke luar layar.
func _apply_offset() -> void:
	_slide.offset_left = -PANEL_W + _extra
	_slide.offset_right = _extra

# --- Masukan ----------------------------------------------------------------

## Klik di mana saja pada latar gelap menutup panel.
func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()

func _on_volume(v: float) -> void:
	Settings.set_value("audio", "master", v)
	AudioServer.set_bus_volume_db(0, linear_to_db(v))
