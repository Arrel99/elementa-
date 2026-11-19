extends Control

## Menu utama bertema sains / kimia (bab 7.1).

@onready var _v: VBoxContainer = $CenterWrap/Column/MenuCard/V
@onready var _volume: HSlider = $SettingsPanel/Box/Volume
@onready var _volume_lbl: Label = $SettingsPanel/Box/VolumeLabel

func _ready() -> void:
	_v.get_node("Play").pressed.connect(_go.bind("lobby"))
	_v.get_node("Library").pressed.connect(_go.bind("library"))
	_v.get_node("HowTo").pressed.connect(func(): $TutorialModal.open(0))
	_v.get_node("Settings").pressed.connect($SettingsPanel.show)
	_v.get_node("Quit").pressed.connect(get_tree().quit)
	$SettingsPanel/Box/Close.pressed.connect($SettingsPanel.hide)
	$TutorialModal.start_practice_requested.connect(_start_practice)
	$Version.text = "v" + Net.GAME_VERSION
	$SettingsPanel.hide()

	var vol: float = float(Settings.get_value("audio", "master", 0.8))
	_volume.value = vol
	_update_volume_label(vol)
	_volume.value_changed.connect(
		func(v: float) -> void:
			Settings.set_value("audio", "master", v)
			AudioServer.set_bus_volume_db(0, linear_to_db(v))
			_update_volume_label(v)
	)

	# tombol uji lokal (bab 4.8) hanya ada di build debug
	var local_btn: Button = _v.get_node("LocalTest")
	local_btn.visible = OS.is_debug_build()
	local_btn.pressed.connect(_start_practice)

	# Tutorial bertahap satu kali saat pertama bermain (bab 7.3)
	if not bool(Settings.get_value("ui", "seen_tutorial", false)):
		$TutorialModal.open(0)
		Settings.set_value("ui", "seen_tutorial", true)

func _start_practice() -> void:
	Settings.set_value("ui", "show_coach", true)
	Net.local_test = true
	_go("game")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and $SettingsPanel.visible:
		$SettingsPanel.hide()

func _update_volume_label(v: float) -> void:
	_volume_lbl.text = "Volume Master: %d%%" % int(round(v * 100.0))

func _go(screen: String) -> void:
	get_tree().change_scene_to_file("res://scenes/screens/%s.tscn" % screen)
