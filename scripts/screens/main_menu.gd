extends Control

## Menu utama bertema sains / kimia dengan animasi masuk & interaksi tombol halus.

@onready var _header: VBoxContainer = $CenterWrap/Column/Header
@onready var _title: Label = $CenterWrap/Column/Header/Title
@onready var _subtitle: Label = $CenterWrap/Column/Header/Subtitle
@onready var _divider: Panel = $CenterWrap/Column/Header/Divider
@onready var _menu_card: PanelContainer = $CenterWrap/Column/MenuCard
@onready var _v: VBoxContainer = $CenterWrap/Column/MenuCard/V
@onready var _volume: HSlider = $SettingsPanel/Box/Volume
@onready var _volume_lbl: Label = $SettingsPanel/Box/VolumeLabel
@onready var _music_vol: HSlider = $SettingsPanel/Box/MusicVolume
@onready var _music_lbl: Label = $SettingsPanel/Box/MusicLabel
@onready var _sfx_vol: HSlider = $SettingsPanel/Box/SfxVolume
@onready var _sfx_lbl: Label = $SettingsPanel/Box/SfxLabel

func _ready() -> void:
	Audio.play_music("menu")
	_v.get_node("Play").pressed.connect(_go.bind("lobby"))
	_v.get_node("Library").pressed.connect(_go.bind("library"))
	_v.get_node("HowTo").pressed.connect(func(): $TutorialModal.open(0))
	_v.get_node("Settings").pressed.connect(_open_settings)
	_v.get_node("Quit").pressed.connect(get_tree().quit)
	$SettingsPanel/Box/Close.pressed.connect(_close_settings)
	$TutorialModal.start_practice_requested.connect(_start_practice)
	$Version.text = "v" + Net.GAME_VERSION
	$SettingsPanel.hide()

	var vol: float = float(Settings.get_value("audio", "master", 0.8))
	_volume.value = vol
	_update_volume_label(vol)
	_volume.value_changed.connect(
		func(v: float) -> void:
			Audio.set_master_volume(v)
			_update_volume_label(v)
	)

	var mvol: float = float(Settings.get_value("audio", "music", 0.6))
	_music_vol.value = mvol
	_music_lbl.text = "Musik: %d%%" % int(round(mvol * 100.0))
	_music_vol.value_changed.connect(
		func(v: float) -> void:
			Audio.set_music_volume(v)
			_music_lbl.text = "Musik: %d%%" % int(round(v * 100.0))
	)

	var svol: float = float(Settings.get_value("audio", "sfx", 0.85))
	_sfx_vol.value = svol
	_sfx_lbl.text = "Efek Suara: %d%%" % int(round(svol * 100.0))
	_sfx_vol.value_changed.connect(
		func(v: float) -> void:
			Audio.set_sfx_volume(v)
			_sfx_lbl.text = "Efek Suara: %d%%" % int(round(v * 100.0))
	)

	# tombol uji lokal (bab 4.8) hanya ada di build debug
	var local_btn: Button = _v.get_node("LocalTest")
	local_btn.visible = OS.is_debug_build()
	local_btn.pressed.connect(_start_practice)

	# Pasang animasi hover/tekan taktil pada semua tombol menu
	_setup_button_motion()

	# Jalankan animasi masuk bertahap setelah tata letak siap
	call_deferred("_play_entrance_anim")

	# Tutorial bertahap satu kali saat pertama bermain (bab 7.3)
	if not bool(Settings.get_value("ui", "seen_tutorial", false)):
		$TutorialModal.open(0)
		Settings.set_value("ui", "seen_tutorial", true)

func _setup_button_motion() -> void:
	for ch in _v.get_children():
		if ch is Button:
			var btn := ch as Button
			btn.mouse_entered.connect(_animate_btn.bind(btn, Vector2(1.03, 1.03), true))
			btn.mouse_exited.connect(_animate_btn.bind(btn, Vector2.ONE, false))
			btn.button_down.connect(_animate_btn.bind(btn, Vector2(0.97, 0.97), false))
			btn.button_up.connect(_animate_btn.bind(btn, Vector2(1.03, 1.03), false))

func _animate_btn(btn: Button, target_scale: Vector2, with_hover_sfx: bool) -> void:
	if not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	if with_hover_sfx:
		Audio.play_sfx("ui_hover", -10.0, 0.04)
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", target_scale, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_entrance_anim() -> void:
	# Header: judul, subjudul, dan garis pembatas masuk mulus
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_divider.pivot_offset = _divider.size * 0.5
	_divider.scale.x = 0.01
	_divider.modulate.a = 0.0

	_menu_card.pivot_offset = _menu_card.size * 0.5
	_menu_card.modulate.a = 0.0
	_menu_card.scale = Vector2(0.95, 0.95)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.45).set_delay(0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_divider, "scale:x", 1.0, 0.52).set_delay(0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_divider, "modulate:a", 1.0, 0.36).set_delay(0.16)
	tw.tween_property(_menu_card, "modulate:a", 1.0, 0.42).set_delay(0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_menu_card, "scale", Vector2.ONE, 0.46).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Setiap tombol muncul bergelombang
	var idx := 0
	for ch in _v.get_children():
		if ch is Button and ch.visible:
			var btn := ch as Button
			btn.pivot_offset = btn.size * 0.5
			btn.modulate.a = 0.0
			btn.scale = Vector2(0.92, 0.92)
			var btw := btn.create_tween().set_parallel(true)
			var d := 0.22 + float(idx) * 0.055
			btw.tween_property(btn, "modulate:a", 1.0, 0.28).set_delay(d)
			btw.tween_property(btn, "scale", Vector2.ONE, 0.32).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			idx += 1

func _open_settings() -> void:
	var panel: PanelContainer = $SettingsPanel
	panel.show()
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)

func _close_settings() -> void:
	var panel: PanelContainer = $SettingsPanel
	if not panel.visible:
		return
	panel.pivot_offset = panel.size * 0.5
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.94, 0.94), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(panel.hide)

func _start_practice() -> void:
	Settings.set_value("ui", "show_coach", true)
	Net.local_test = true
	_go("game")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and $SettingsPanel.visible:
		_close_settings()

func _update_volume_label(v: float) -> void:
	_volume_lbl.text = "Volume Master: %d%%" % int(round(v * 100.0))

func _go(screen: String) -> void:
	get_tree().change_scene_to_file("res://scenes/screens/%s.tscn" % screen)
