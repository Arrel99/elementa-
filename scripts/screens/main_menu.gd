extends Control

## Menu utama (bab 7.1).

func _ready() -> void:
    $V/Play.pressed.connect(_go.bind("lobby"))
    $V/Library.pressed.connect(_go.bind("library"))
    $V/HowTo.pressed.connect($HowToDialog.popup_centered)
    $V/Settings.pressed.connect($SettingsPanel.show)
    $V/Quit.pressed.connect(get_tree().quit)
    $Version.text = "v" + Net.GAME_VERSION
    $SettingsPanel.hide()
    $SettingsPanel/Volume.value = Settings.get_value("audio", "master", 0.8)
    $SettingsPanel/Volume.value_changed.connect(
        func(v: float) -> void:
            Settings.set_value("audio", "master", v)
            AudioServer.set_bus_volume_db(0, linear_to_db(v))
    )
    # tombol uji lokal (bab 4.8) hanya ada di build debug
    $V/LocalTest.visible = OS.is_debug_build()
    $V/LocalTest.pressed.connect(
        func() -> void:
            Net.local_test = true
            _go("game")
    )
    # Tutorial singkat satu kali saat pertama bermain (bab 7.3)
    if not bool(Settings.get_value("ui", "seen_tutorial", false)):
        $HowToDialog.popup_centered()
        Settings.set_value("ui", "seen_tutorial", true)

func _go(screen: String) -> void:
    get_tree().change_scene_to_file("res://scenes/screens/%s.tscn" % screen)
