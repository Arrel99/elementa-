extends Node

## Autoload Audio: pengelola musik latar (BGM) dan efek suara (SFX).
##
## Menyediakan bus terpisah ("Master", "Music", "SFX"), transisi crossfade
## antar trek musik, pool polifonik untuk SFX agar tidak terpotong, serta
## bunyi klik otomatis untuk semua tombol UI.

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

const SFX_POOL_SIZE := 10
const CROSSFADE_SEC := 0.75

const MUSIC_PATHS := {
	"menu": "res://audio/music/menu_bgm.wav",
	"game": "res://audio/music/game_bgm.wav",
}

const SFX_PATHS := {
	"ui_click": "res://audio/sfx/ui_click.wav",
	"ui_hover": "res://audio/sfx/ui_hover.wav",
	"card_draw": "res://audio/sfx/card_draw.wav",
	"card_place": "res://audio/sfx/card_place.wav",
	"card_shuffle": "res://audio/sfx/card_shuffle.wav",
	"synth_success": "res://audio/sfx/synth_success.wav",
	"spell_cast": "res://audio/sfx/spell_cast.wav",
	"card_discard": "res://audio/sfx/card_discard.wav",
	"coin_flip": "res://audio/sfx/coin_flip.wav",
	"coin_land": "res://audio/sfx/coin_land.wav",
	"turn_start": "res://audio/sfx/turn_start.wav",
	"error": "res://audio/sfx/error.wav",
	"win_fanfare": "res://audio/sfx/win_fanfare.wav",
	"lose_jingle": "res://audio/sfx/lose_jingle.wav",
}

var _music_streams := {}
var _sfx_streams := {}
var _bgm_players: Array[AudioStreamPlayer] = []
var _bgm_active_idx := 0
var _current_track := ""
var _fade_tween: Tween

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _last_hover_ms := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_apply_saved_volumes()
	_setup_players()
	_preload_streams()

	# Pasang bunyi klik halus pada semua tombol UI di seluruh scene
	_hook_buttons_recursive(get_tree().root)
	get_tree().node_added.connect(_on_node_added)

func _ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_MUSIC)
		AudioServer.set_bus_send(idx, BUS_MASTER)
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_SFX)
		AudioServer.set_bus_send(idx, BUS_MASTER)

func _apply_saved_volumes() -> void:
	set_master_volume(float(Settings.get_value("audio", "master", 0.8)), false)
	set_music_volume(float(Settings.get_value("audio", "music", 0.6)), false)
	set_sfx_volume(float(Settings.get_value("audio", "sfx", 0.85)), false)

func _setup_players() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		_bgm_players.append(p)

	for i in SFX_POOL_SIZE:
		var s := AudioStreamPlayer.new()
		s.bus = BUS_SFX
		add_child(s)
		_sfx_pool.append(s)

func _preload_streams() -> void:
	for k in MUSIC_PATHS:
		var path: String = MUSIC_PATHS[k]
		if ResourceLoader.exists(path):
			var res: AudioStream = load(path)
			if res is AudioStreamWAV:
				var wav := (res as AudioStreamWAV).duplicate() as AudioStreamWAV
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				var sample_bytes := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				var channels := 2 if wav.stereo else 1
				wav.loop_end = wav.data.size() / maxi(sample_bytes * channels, 1)
				_music_streams[k] = wav
			elif res != null:
				_music_streams[k] = res

	for k in SFX_PATHS:
		var path: String = SFX_PATHS[k]
		if ResourceLoader.exists(path):
			var res: AudioStream = load(path)
			if res != null:
				_sfx_streams[k] = res

# --- Kontrol Volume ----------------------------------------------------------

func set_master_volume(v: float, save := true) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if save:
		Settings.set_value("audio", "master", clamped)
	_set_bus_linear(BUS_MASTER, clamped)

func set_music_volume(v: float, save := true) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if save:
		Settings.set_value("audio", "music", clamped)
	_set_bus_linear(BUS_MUSIC, clamped)

func set_sfx_volume(v: float, save := true) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if save:
		Settings.set_value("audio", "sfx", clamped)
	_set_bus_linear(BUS_SFX, clamped)

func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))

# --- Musik Latar (Crossfade) -------------------------------------------------

func play_music(track: String, fade_sec := CROSSFADE_SEC) -> void:
	if track == _current_track:
		var cur_p: AudioStreamPlayer = _bgm_players[_bgm_active_idx]
		if cur_p.playing:
			return
	if not _music_streams.has(track):
		return

	_current_track = track
	var prev_player: AudioStreamPlayer = _bgm_players[_bgm_active_idx]
	_bgm_active_idx = 1 - _bgm_active_idx
	var next_player: AudioStreamPlayer = _bgm_players[_bgm_active_idx]

	next_player.stream = _music_streams[track]
	next_player.volume_db = -36.0
	next_player.play()

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(next_player, "volume_db", -5.0, fade_sec).set_trans(Tween.TRANS_SINE)
	if prev_player.playing:
		_fade_tween.tween_property(prev_player, "volume_db", -42.0, fade_sec).set_trans(Tween.TRANS_SINE)
		_fade_tween.chain().tween_callback(prev_player.stop)

func stop_music(fade_sec := 0.5) -> void:
	_current_track = ""
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	for p in _bgm_players:
		if p.playing:
			_fade_tween.tween_property(p, "volume_db", -42.0, fade_sec).set_trans(Tween.TRANS_SINE)
			_fade_tween.chain().tween_callback(p.stop)

# --- Efek Suara (SFX) --------------------------------------------------------

func play_sfx(sfx_name: String, vol_db := 0.0, pitch_jitter := 0.0) -> void:
	if not _sfx_streams.has(sfx_name):
		return
	if sfx_name == "ui_hover":
		var now := Time.get_ticks_msec()
		if now - _last_hover_ms < 55:
			return
		_last_hover_ms = now

	var player: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = _sfx_streams[sfx_name]
	player.volume_db = vol_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	player.play()

# --- Auto-hook Klik Tombol UI ------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var btn := node as BaseButton
		if not btn.has_meta("_audio_click_hooked"):
			btn.set_meta("_audio_click_hooked", true)
			btn.pressed.connect(func(): play_sfx("ui_click", -3.0, 0.03))

func _hook_buttons_recursive(node: Node) -> void:
	_on_node_added(node)
	for ch in node.get_children():
		_hook_buttons_recursive(ch)
