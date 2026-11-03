extends PopupPanel

## Pengaturan saat di tengah permainan (ikon gear di kolom kanan).
##
## Menyimpan volume (memakai autoload `Settings` yang sama dengan menu utama)
## dan tombol **Menyerah**, yang sebelumnya menempel langsung di kolom kanan.
## Panel ini hanya memancarkan sinyal; keputusan keluar/menyerah tetap di
## `game.gd`, supaya aturan permainan tidak ikut di sini.

signal give_up_requested
signal back_to_menu_requested

@onready var _volume: HSlider = $V/VolRow/Volume

func _ready() -> void:
    _volume.value_changed.connect(_on_volume)
    $V/GiveUp.pressed.connect(func() -> void:
        hide()
        give_up_requested.emit())
    $V/ToMenu.pressed.connect(func() -> void:
        hide()
        back_to_menu_requested.emit())
    $V/Close.pressed.connect(hide)

## Buka panel dengan nilai volume terkini.
func open() -> void:
    _volume.set_value_no_signal(Settings.get_value("audio", "master", 0.8))
    popup_centered(Vector2i(380, 300))

func _on_volume(v: float) -> void:
    Settings.set_value("audio", "master", v)
    AudioServer.set_bus_volume_db(0, linear_to_db(v))
