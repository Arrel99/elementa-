extends Control

## Papan permainan 2.5D (Arena 3D + HUD & Tangan 2D).
## Satu skrip untuk host dan klien.
## Host = pemain 0 (menjalankan GameState), klien = pemain 1.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const AI_SCRIPT := preload("res://scripts/core/ai_player.gd")

# Ukuran kartu tangan di overlay 2D (skala dasar untuk tinggi jendela 1080)
const SIZE_HAND := Vector2(114, 152)
const SIZE_OPP_HAND := Vector2(76, 102)
const HUD_BASE_SIZE := Vector2(142, 376)
const HUD_PAD := 8.0
const LOG_BTN_SIZE := Vector2(66, 66)

# efek spell -> zona tempat target dipilih; efek yang tidak ada di sini tanpa target
const SPELL_TARGET := {
	"bilas": "my_base",
	"korosi": "opp_base",
	"elektrolisis": "my_special",
	"elektrolisis_paksa": "opp_special",
}

const REASON_TEXT := {
	"surrender": "Salah satu pemain menyerah.",
	"deck_out": "Salah satu pemain tidak bisa menarik kartu dari deck (Deck Out).",
	"special_full": "Salah satu pemain berhasil mengisi 8 senyawa dan langsung menang!",
	"timeout": "Waktu 15 menit salah satu pemain habis.",
}

enum Mode { IDLE, PICK_SYNTH, PICK_TARGET }

@onready var board3d: Node3D = $BoardViewport/Viewport3D/Board3D

var state: GameState            # hanya ada di host
var my_index := 0
var mode := Mode.IDLE
var view: Dictionary = {}
var synth_first := -1
var pending_spell_uid := -1
var pending_zone := ""
var local_test := false
var vs_ai := false
var tutorial_mode := false
var ai_difficulty := "normal"
var easy_mode := true
var turn_timer := Timer.new()
var _ai_timer := Timer.new()
var _pending_key := ""          # penanda efek interaktif yang sedang ditampilkan
var _glow_tween: Tween          # denyut glow zona tangan
var _playable := {}             # uid kartu yang bisa dimainkan (dari state)
var _prev_hand_uids := {}       # uid kartu di tangan sebelumnya (untuk animasi masuk kartu baru)
var _last_turn_no := 0          # melacak pergantian giliran untuk bunyi turn_start
var _result_sfx_played := false # mencegah bunyi hasil diputar berulang
var _ui_scale := 1.0
var _disp_me_time := 900.0      # tampilan jam lokal pemain (15:00)
var _disp_opp_time := 900.0     # tampilan jam lokal lawan (15:00)

# Status animasi drag & drop kartu dari tangan
var _drag_uid := -1
var _drag_source: Control = null
var _drag_ghost: Control = null
var _drag_target_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO

# --- Siklus hidup (bab 4.5 / 6.2) -------------------------------------------

func _ready() -> void:
	Audio.play_music("game")
	local_test = Net.local_test
	vs_ai = Net.vs_ai
	tutorial_mode = Net.tutorial_mode
	ai_difficulty = Net.ai_difficulty
	resized.connect(_layout)
	_layout()

	board3d.card_clicked.connect(_on_card_clicked)
	board3d.discard_clicked.connect(_on_discard_clicked)
	board3d.card_preview_hover.connect(_on_preview_hover)
	board3d.card_preview_exit.connect(_on_preview_exit)
	board3d.card_preview_pin.connect(_on_preview_pin)

	$DiscardDrawer.preview_hover.connect(_on_preview_hover)
	$DiscardDrawer.preview_exit.connect(_on_preview_exit)
	$DiscardDrawer.preview_pin.connect(_on_preview_pin)

	$Hud/EndTurn.pressed.connect(func(): submit({"type": "end"}))
	$BattleLogBtn.pressed.connect(func(): $TurnHistory.toggle())
	$InGameSettings.give_up_requested.connect($GiveUpDialog.popup_centered)
	$Result.back_to_menu_requested.connect(_back_to_menu)
	$Result.rematch_requested.connect(_rematch)
	$EmbeddedTutorial.back_to_menu_requested.connect(_back_to_menu)
	$CoinFlipOverlay.coin_call_chosen.connect(func(side: String): submit({"type": "coin_call", "side": side}))
	$CoinFlipOverlay.turn_order_chosen.connect(func(first: bool): submit({"type": "coin_order", "first": first}))
	$GiveUpDialog.confirmed.connect(func(): submit({"type": "give_up"}))
	$RevealPopup.resolved.connect(_on_spektrometer_resolved)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.server_disconnected.connect(_on_server_gone)
	_setup_timer()
	_ai_timer.one_shot = true
	_ai_timer.timeout.connect(_on_ai_step)
	add_child(_ai_timer)

	# Godot memakai OfflineMultiplayerPeer saat tidak ada jaringan, dan peer
	# itu melaporkan is_server() = true. Deteksi tipe peer-nya lebih dulu.
	var offline := multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if vs_ai or (offline and not local_test):
		# Mode VS. AI: Pemain 0 = Kamu, Pemain 1 = AI.
		vs_ai = true
		Net.vs_ai = true
		local_test = false
		start_as_host()
	elif local_test:
		# Mode uji lokal satu layar: dua pemain bergantian.
		Net.local_test = true
		start_as_host()
	elif multiplayer.is_server():
		if not Net.client_loaded:
			await Net.client_ready          # tunggu klien selesai memuat scene
		start_as_host()
	else:
		Net.game_loaded.rpc_id(1)           # klien memberi tahu host: scene sudah siap

func _process(delta: float) -> void:
	if _drag_ghost != null and is_instance_valid(_drag_ghost):
		var target := _drag_target_pos - _drag_ghost.size * 0.5
		_drag_ghost.position = _drag_ghost.position.lerp(target, clampf(delta * 22.0, 0.0, 1.0))
		var vx := (_drag_target_pos.x - _drag_last_pos.x) / maxf(delta, 0.001)
		var tilt := clampf(vx * 0.012, -16.0, 16.0)
		_drag_ghost.rotation_degrees = lerpf(_drag_ghost.rotation_degrees, tilt, clampf(delta * 14.0, 0.0, 1.0))
		_drag_last_pos = _drag_target_pos

	# Sistem jam catur 15 menit per pemain (hanya berjalan setelah koin flip selesai)
	var in_coin: bool = not view.get("coin_phase", {}).is_empty()
	if not view.is_empty() and int(view.winner) == -2 and not in_coin:
		if state != null and (vs_ai or local_test or multiplayer.is_server()):
			if state.tick_clock(delta):
				_broadcast()
				return
			var my_i := state.current if local_test else 0
			_disp_me_time = float(state.players[my_i].time_left)
			_disp_opp_time = float(state.players[1 - my_i].time_left)
		else:
			if bool(view.my_turn):
				_disp_me_time = maxf(0.0, _disp_me_time - delta)
			else:
				_disp_opp_time = maxf(0.0, _disp_opp_time - delta)
		_refresh_clock_labels()

func _refresh_clock_labels() -> void:
	$Hud/MyClock.text = _fmt_clock(_disp_me_time)
	$Hud/OppClock.text = _fmt_clock(_disp_opp_time)
	$Hud/MyClock.add_theme_color_override("font_color", _clock_color(_disp_me_time))
	$Hud/OppClock.add_theme_color_override("font_color", _clock_color(_disp_opp_time))

func _fmt_clock(sec: float) -> String:
	var s := maxi(0, int(ceil(sec)))
	return "%02d:%02d" % [s / 60, s % 60]

func _clock_color(sec: float) -> Color:
	if sec <= 30.0:
		return Color(0.96, 0.42, 0.44, 1.0)
	if sec <= 120.0:
		return Color(0.96, 0.78, 0.36, 1.0)
	return Color(0.92, 0.94, 0.97, 1.0)

func start_as_host() -> void:
	state = GameState.new()
	if tutorial_mode:
		state.setup_tutorial()
		$EmbeddedTutorial.start()
	else:
		state.setup(randi(), true)        # mulai dengan lempar koin sebelum draw kartu pertama
		$EmbeddedTutorial.stop()
	my_index = 0
	_prev_hand_uids.clear()
	_last_turn_no = 0
	_result_sfx_played = false
	_broadcast()

# --- Tata letak responsif (Overlay 2D di atas Arena 3D) ----------------------

func _layout() -> void:
	var w := maxf(size.x, 320.0)
	var h := maxf(size.y, 240.0)
	_ui_scale = clampf(minf(w / 1920.0, h / 1080.0), 0.35, 1.35)

	# HUD di sisi kanan tengah (Jam & Skor Lawan + END TURN + Skor & Jam Kamu)
	var hud_w := HUD_BASE_SIZE.x * _ui_scale
	var hud_h := HUD_BASE_SIZE.y * _ui_scale
	var log_h := LOG_BTN_SIZE.y * _ui_scale
	var total_h := hud_h + 12.0 * _ui_scale + log_h
	var hud_x := w - hud_w - 14.0 * _ui_scale
	var hud_y := (h - total_h) * 0.5

	var hudbg: Control = $HudBg
	hudbg.position = Vector2(hud_x, hud_y)
	hudbg.size = HUD_BASE_SIZE
	hudbg.scale = Vector2(_ui_scale, _ui_scale)

	var hud: Control = $Hud
	hud.position = Vector2(hud_x + HUD_PAD * _ui_scale, hud_y + HUD_PAD * _ui_scale)
	hud.size = HUD_BASE_SIZE - Vector2(HUD_PAD, HUD_PAD) * 2.0
	hud.scale = Vector2(_ui_scale, _ui_scale)

	# Tombol heksagonal Battle Log tepat di bawah panel skor & jam
	var log_btn: Control = $BattleLogBtn
	log_btn.size = LOG_BTN_SIZE
	log_btn.scale = Vector2(_ui_scale, _ui_scale)
	log_btn.position = Vector2(
		hud_x + (hud_w - LOG_BTN_SIZE.x * _ui_scale) * 0.5,
		hud_y + hud_h + 12.0 * _ui_scale)

	# Dock tangan pemain (bawah tengah, sedikit melengkung ala Yu-Gi-Oh! / Pokemon)
	var me_w := minf(w * 0.72, 1080.0 * _ui_scale)
	var me_h := (SIZE_HAND.y + 24.0) * _ui_scale
	var me_dock: Control = $MeHandDock
	me_dock.position = Vector2((w - me_w) * 0.5 - 32.0 * _ui_scale, h - me_h + 6.0 * _ui_scale)
	me_dock.size = Vector2(me_w, me_h)

	var me_glow: Control = $MeHandGlow
	me_glow.position = me_dock.position - Vector2(10.0, 8.0) * _ui_scale
	me_glow.size = me_dock.size + Vector2(20.0, 6.0) * _ui_scale

	# Dock tangan lawan (atas tengah, kartu tertutup rapat)
	var opp_w := minf(w * 0.56, 760.0 * _ui_scale)
	var opp_h := SIZE_OPP_HAND.y * _ui_scale
	var opp_dock: Control = $OppHandDock
	opp_dock.position = Vector2((w - opp_w) * 0.5 - 32.0 * _ui_scale, -24.0 * _ui_scale)
	opp_dock.size = Vector2(opp_w, opp_h)

	if not view.is_empty():
		_layout_hand_fan($MeHandDock, true)
		_layout_hand_fan($OppHandDock, false)

# --- Aksi (bab 4.8 / 6.2) ---------------------------------------------------

func submit(action: Dictionary) -> void:
	if vs_ai:
		_handle(1, action)
	elif local_test:
		var actor := state.current
		if not state.coin_phase.is_empty():
			if String(state.coin_phase.get("stage", "")) == "pick_call":
				actor = int(state.coin_phase.get("caller", 0))
			elif String(state.coin_phase.get("stage", "")) == "pick_order":
				actor = int(state.coin_phase.get("winner", 0))
		_handle(1 if actor == 0 else 2, action)
	elif multiplayer.is_server():
		_handle(1, action)
	else:
		request_action.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func request_action(action: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_handle(multiplayer.get_remote_sender_id(), action)

func _handle(sender_id: int, a: Dictionary) -> void:
	var p := 0 if sender_id == 1 else 1
	var err := ""
	match a.get("type", ""):
		"coin_call":  err = state.choose_coin_call(p, String(a.get("side", "")))
		"coin_order": err = state.choose_first_player(p, bool(a.get("first", true)))
		"place":        err = state.place_base(p, int(a.get("uid", -1)), int(a.get("slot", -1)))
		"synth":        err = state.synthesize(p, int(a.get("a", -1)), int(a.get("b", -1)))
		"spell":        err = state.play_spell(p, int(a.get("uid", -1)), a.get("args", {}))
		"spell_target": err = state.resolve_spell_target(p, int(a.get("target_uid", -1)))
		"discard":      err = state.discard_from_hand(p, int(a.get("uid", -1)))
		"spektro":      err = state.resolve_spektrometer(p, int(a.get("take", -1)))
		"end":     err = state.end_turn(p)
		"give_up": state.surrender(p)
		_:         err = "Aksi tidak dikenal."
	EventLog.log_event("action", {"p": p, "type": a.get("type", ""), "ok": err == "", "err": err})
	if err != "":
		if sender_id == 1 or local_test:
			show_error(err)
		else:
			show_error.rpc_id(sender_id, err)
		return
	_broadcast()
	if not local_test and not vs_ai and multiplayer.is_server() and state.winner == -2:
		turn_timer.start(60)

@rpc("authority", "call_remote", "reliable")
func show_error(msg: String) -> void:
	Audio.play_sfx("error", -2.0)
	$Toast.show_text(msg)

@rpc("authority", "call_remote", "reliable")
func receive_view(v: Dictionary) -> void:
	render(v)

func _on_spektrometer_resolved(take_uid: int) -> void:
	submit({"type": "spektro", "take": take_uid})

func _broadcast() -> void:
	if vs_ai:
		render(state.view_for(0))   # sudut pandang selalu Kamu (Pemain 0) vs AI (Pemain 1)
		_schedule_ai_if_needed()
		return
	if local_test:
		render(state.view_for(state.current))   # layar menampilkan sudut pandang pemain aktif
		return
	render(state.view_for(0))
	for id in multiplayer.get_peers():
		receive_view.rpc_id(id, state.view_for(1))

func _schedule_ai_if_needed() -> void:
	if not vs_ai or state == null or state.winner != -2:
		_ai_timer.stop()
		return
	var delay := -1.0
	if not state.coin_phase.is_empty():
		var stage := String(state.coin_phase.get("stage", ""))
		if stage == "pick_call" and int(state.coin_phase.get("caller", -1)) == 1:
			delay = 0.95
		elif stage == "pick_order" and int(state.coin_phase.get("winner", -1)) == 1:
			delay = 2.20   # tunggu animasi koin 3D selesai berputar
	elif not state.pending.is_empty():
		if int(state.pending.get("to", -1)) == 1:
			delay = 0.90
	elif state.current == 1:
		match ai_difficulty:
			"easy": delay = 1.05
			"hard": delay = 0.78
			"extreme": delay = 0.68
			_: delay = 0.90
	if delay > 0.0:
		_ai_timer.start(delay)
	else:
		_ai_timer.stop()

func _on_ai_step() -> void:
	if not vs_ai or state == null or state.winner != -2:
		return
	var act: Dictionary = AI_SCRIPT.choose_action(state, 1, ai_difficulty)
	if not act.is_empty():
		_handle(2, act)

# --- Render (Arena 3D + Tangan 2D + HUD) ------------------------------------

func render(v: Dictionary) -> void:
	view = v
	_cancel_drag_immediate()
	$CardPreview.hide_preview()     # kartu lama akan dibuang
	_reset_mode()
	_playable = v.get("playable", {})

	# Render seluruh papan 2.5D di 3D
	board3d.render_board(v, _playable, easy_mode)

	# Render tangan pemain & lawan di overlay 2D
	_fill_hand($MeHandDock, v.me.hand, true, SIZE_HAND, true, "hand")
	_fill_hand($OppHandDock, v.opp.hand_backs, false, SIZE_OPP_HAND, false, "")

	var hand_max := int(v.rules.hand_max)
	var over: bool = hand_max > 0 and v.me.hand.size() > hand_max
	var extra := ""
	if v.countdown > 0:
		extra = "  •  Hitung mundur %d" % v.countdown
	$Hud/OppBadge/Num.text = str(v.opp.points)
	$Hud/MyBadge/Num.text = str(v.me.points)
	$Hud/EndTurn.disabled = (not v.my_turn) or v.winner != -2 or over
	$Hud/MyTurnBar.modulate.a = 1.0 if (v.my_turn and v.winner == -2) else 0.14
	$Hud/OppTurnBar.modulate.a = 1.0 if ((not v.my_turn) and v.winner == -2) else 0.14
	_disp_me_time = float(v.me.get("time_left", GameState.MATCH_CLOCK_SECONDS))
	_disp_opp_time = float(v.opp.get("time_left", GameState.MATCH_CLOCK_SECONDS))
	_refresh_clock_labels()
	if over and v.my_turn and v.winner == -2:
		_highlight_zone("hand")     # tangan melebihi batas: sorot zona tangan
	$InGameSettings.set_status(
		"Giliran %d  (sintesis %d, spell %d)%s" % [
			v.turn_no, v.synth_left, v.spell_left, extra],
		"Deck %d | Buang %d  •  Lawan deck %d" % [
			v.me.deck_count, v.me.discard.size(), v.opp.deck_count])
	_sync_pending(v)
	$CoinFlipOverlay.sync(v, local_test)
	$TurnHistory.update_history(v, local_test)
	$DiscardDrawer.refresh_if_open(v, local_test)
	$EmbeddedTutorial.on_view_updated(v)
	if v.get("coin_phase", {}).is_empty() and int(v.winner) == -2:
		var tno := int(v.get("turn_no", 1))
		if _last_turn_no > 0 and tno != _last_turn_no:
			Audio.play_sfx("turn_start", -3.0)
		_last_turn_no = tno
	if v.winner != -2:
		_show_result()

## Menampilkan efek interaktif (Spektrometer atau pemilihan target Spell di Zona Spell).
func _sync_pending(v: Dictionary) -> void:
	var ptype := String(v.pending.get("type", ""))
	if ptype == "spell_target":
		if $RevealPopup.visible:
			$RevealPopup.hide()
		_pending_key = ""
		var z := String(v.pending.get("zone", ""))
		if z != "":
			_highlight_zone(z)
		return
	var key := ""
	if ptype == "spektrometer":
		for c in v.pending.cards:
			key += "%s," % c.uid
	if key == "":
		if $RevealPopup.visible:
			$RevealPopup.hide()
		_pending_key = ""
	elif key != _pending_key:
		_pending_key = key
		$RevealPopup.show_spektrometer(v.pending.cards)

## Mengisi dock tangan 2D dengan susunan kipas (fan) ala Yu-Gi-Oh! / Pokemon.
func _fill_hand(dock: Control, cards: Array, face_up: bool, base_size: Vector2,
		interactive: bool, playable_key: String) -> void:
	for ch in dock.get_children():
		dock.remove_child(ch)
		ch.queue_free()
	var playable: Array = _playable.get(playable_key, []) if playable_key != "" else []
	var card_sz := (base_size * _ui_scale).round()
	for i in cards.size():
		var c: Dictionary = cards[i]
		var n: Control = CARD_SCENE.instantiate()
		dock.add_child(n)
		n.fit(card_sz)
		n.size = card_sz
		n.pivot_offset = card_sz * 0.5
		n.setup(c, face_up, interactive, face_up)
		n.preview_hover.connect(_on_preview_hover)
		n.preview_exit.connect(_on_preview_exit)
		n.preview_pin.connect(_on_preview_pin)
		if interactive:
			n.draggable = true
			n.clicked.connect(_on_card_clicked)
			n.drag_started.connect(_on_hand_drag_started)
			n.drag_moved.connect(_on_hand_drag_moved)
			n.drag_ended.connect(_on_hand_drag_ended)
			n.mouse_entered.connect(_on_hand_card_hover.bind(n, true))
			n.mouse_exited.connect(_on_hand_card_hover.bind(n, false))
		if playable.has(int(c.get("uid", -1))):
			n.set_playable(true)
	_layout_hand_fan(dock, face_up)

	# Animasi masuk halus untuk kartu baru yang baru ditarik ke tangan pemain
	if face_up:
		var next_hand_uids := {}
		var new_idx := 0
		for n in dock.get_children():
			var u := int(n.uid)
			next_hand_uids[u] = true
			if not _prev_hand_uids.is_empty() and not _prev_hand_uids.has(u):
				var dest_pos: Vector2 = n.position
				var dest_rot: float = n.rotation_degrees
				n.position = dest_pos + Vector2(90.0 * _ui_scale, 75.0 * _ui_scale)
				n.rotation_degrees = dest_rot + 14.0
				n.modulate.a = 0.0
				var tw := n.create_tween()
				if new_idx > 0:
					tw.tween_interval(float(new_idx) * 0.10)
				tw.chain().set_parallel(true)
				tw.tween_property(n, "position", dest_pos, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(n, "rotation_degrees", dest_rot, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(n, "modulate:a", 1.0, 0.28)
				new_idx += 1
		_prev_hand_uids = next_hand_uids

func _layout_hand_fan(dock: Control, is_me: bool) -> void:
	var cards := dock.get_children()
	var count := cards.size()
	if count == 0:
		return
	var base_sz := (SIZE_HAND if is_me else SIZE_OPP_HAND) * _ui_scale
	var card_w := base_sz.x
	var max_span := maxf(dock.size.x - card_w, 40.0)
	var ideal_step := card_w * (0.94 if is_me else 0.72)
	var step := ideal_step if count <= 1 else minf(ideal_step, max_span / float(count - 1))
	var total_w := card_w + step * float(maxi(count - 1, 0))
	var start_x := (dock.size.x - total_w) * 0.5
	var mid := float(count - 1) * 0.5

	for i in count:
		var n: Control = cards[i]
		n.fit(base_sz.round())
		n.size = base_sz.round()
		n.pivot_offset = n.size * 0.5
		var t := 0.0 if count <= 1 else (float(i) - mid) / maxf(mid, 1.0)   # -1..1
		var arch_y := (t * t) * (16.0 if is_me else -10.0) * _ui_scale
		var base_y := (18.0 * _ui_scale + arch_y) if is_me else (arch_y)
		var rot := t * (5.5 if is_me else -4.0)
		n.position = Vector2(start_x + float(i) * step, base_y)
		n.rotation_degrees = rot
		n.z_index = i
		n.set_meta("base_y", base_y)
		n.set_meta("base_rot", rot)
		n.set_meta("base_z", i)

func _on_hand_card_hover(n: Control, on: bool) -> void:
	if not is_instance_valid(n) or not n.has_meta("base_y"):
		return
	if on:
		Audio.play_sfx("ui_hover", -9.0, 0.05)
	var base_y: float = n.get_meta("base_y")
	var base_rot: float = n.get_meta("base_rot")
	var base_z: int = n.get_meta("base_z")
	n.z_index = 40 if on else base_z
	var tw := n.create_tween().set_parallel(true)
	tw.tween_property(n, "position:y", base_y - 26.0 * _ui_scale if on else base_y, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "rotation_degrees", 0.0 if on else base_rot, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2(1.08, 1.08) if on else Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# --- Pratinjau kartu (hover / klik kanan) ----------------------------------

func _on_preview_hover(data: Dictionary, source: Node) -> void:
	if _drag_ghost != null:
		return
	var z := _zone_of(int(data.get("uid", -1)))
	var on_right := (z == "my_special" or z == "opp_special")
	$CardPreview.hover(data, source, on_right)

func _on_preview_exit(source: Node) -> void:
	$CardPreview.unhover(source)

func _on_preview_pin(data: Dictionary, source: Node) -> void:
	if _drag_ghost != null:
		return
	$CardPreview.pin(data, source)
	$EmbeddedTutorial.on_preview_pinned()

# --- Drag & Drop kartu tangan -----------------------------------------------

func _on_hand_drag_started(uid: int, card_node: Control, global_pos: Vector2) -> void:
	if view.is_empty() or view.winner != -2 or not view.my_turn or not view.pending.is_empty():
		return
	var card := _card_by_uid(uid)
	if card.is_empty():
		return
	_cancel_drag_immediate()
	$CardPreview.hide_preview()
	Audio.play_sfx("card_draw", -5.0, 0.06)

	_drag_uid = uid
	_drag_source = card_node
	_drag_source.modulate.a = 0.25
	_drag_target_pos = global_pos
	_drag_last_pos = global_pos

	var ghost: Control = CARD_SCENE.instantiate()
	add_child(ghost)
	var sz := (SIZE_HAND * _ui_scale).round()
	ghost.fit(sz)
	ghost.size = sz
	ghost.pivot_offset = sz * 0.5
	ghost.setup(card, true, false, false)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 120
	ghost.position = card_node.global_position
	ghost.scale = Vector2(1.0, 1.0)
	_drag_ghost = ghost

	var tw := ghost.create_tween()
	tw.tween_property(ghost, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Sorot zona tujuan yang sesuai di papan 3D
	var d := CardDB.get_card(String(card.id))
	if d != null:
		if d.type == CardData.Type.BASIC:
			_highlight_zone("my_base")
		elif d.type == CardData.Type.SPELL:
			var tz: String = SPELL_TARGET.get(String(d.spell_effect), "")
			_highlight_zone(tz if tz != "" else "my_spell")

func _on_hand_drag_moved(uid: int, _card_node: Control, global_pos: Vector2) -> void:
	_drag_target_pos = global_pos
	# Saat menyeret kartu dasar, sorot slot kosong spesifik di bawah kursor
	var card := _card_by_uid(uid)
	if not card.is_empty():
		var d := CardDB.get_card(String(card.id))
		if d != null and d.type == CardData.Type.BASIC:
			var slot: int = board3d.pick_base_slot_at(global_pos)
			if slot != -1 and _is_my_base_slot_free(slot):
				board3d.highlight_base_slot(slot)
			else:
				board3d.clear_slot_highlight()

func _is_my_base_slot_free(slot: int) -> bool:
	if view.is_empty():
		return false
	for i in view.me.base.size():
		if int(view.me.base[i].get("slot", i)) == slot:
			return false
	return true

func _on_hand_drag_ended(uid: int, _card_node: Control, global_pos: Vector2) -> void:
	if _drag_ghost == null or uid != _drag_uid:
		return
	var ghost := _drag_ghost
	var src := _drag_source
	_drag_ghost = null
	_drag_source = null
	_drag_uid = -1

	var hand_dock: Control = $MeHandDock
	var dropped_on_board: bool = global_pos.y < hand_dock.position.y - 12.0
	if not dropped_on_board:
		_clear_glow()
		_animate_ghost_return(ghost, src)
		return

	# Khusus kartu dasar: harus dijatuhkan di atas salah satu slot kosong (0..5)
	var card := _card_by_uid(uid)
	var data := CardDB.get_card(String(card.id)) if not card.is_empty() else null
	if data != null and data.type == CardData.Type.BASIC:
		var slot: int = board3d.pick_base_slot_at(global_pos)
		if slot == -1 or not _is_my_base_slot_free(slot):
			_clear_glow()
			_animate_ghost_return(ghost, src)
			if slot != -1:
				$Toast.show_text("Slot itu sudah terisi. Pilih slot kosong.")
			return
		var tw_b := ghost.create_tween().set_parallel(true)
		tw_b.tween_property(ghost, "scale", Vector2(0.72, 0.72), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_b.tween_property(ghost, "modulate:a", 0.0, 0.14)
		tw_b.finished.connect(ghost.queue_free)
		if is_instance_valid(src):
			src.modulate.a = 1.0
		_clear_glow()
		submit({"type": "place", "uid": uid, "slot": slot})
		return

	# Kartu Spell: animasi masuk ke zona papan lalu eksekusi spell
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "scale", Vector2(0.76, 0.76), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.14)
	tw.finished.connect(ghost.queue_free)

	if is_instance_valid(src):
		src.modulate.a = 1.0
	_execute_dropped_card(uid, global_pos)

func _animate_ghost_return(ghost: Control, src: Control) -> void:
	var dest := src.global_position if is_instance_valid(src) else ghost.position
	var dest_rot: float = src.rotation_degrees if is_instance_valid(src) else 0.0
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "position", dest, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "rotation_degrees", dest_rot, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func():
		if is_instance_valid(src):
			src.modulate.a = 1.0
		if is_instance_valid(ghost):
			ghost.queue_free())

func _cancel_drag_immediate() -> void:
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	if is_instance_valid(_drag_source):
		_drag_source.modulate.a = 1.0
	_drag_ghost = null
	_drag_source = null
	_drag_uid = -1

func _execute_dropped_card(uid: int, global_pos: Vector2) -> void:
	var card := _card_by_uid(uid)
	if card.is_empty():
		_clear_glow()
		return
	var data := CardDB.get_card(String(card.id))
	if data == null:
		_clear_glow()
		return
	if data.type == CardData.Type.BASIC:
		_clear_glow()
		submit({"type": "place", "uid": uid})
	elif data.type == CardData.Type.SPELL:
		var zone: String = SPELL_TARGET.get(String(data.spell_effect), "")
		if zone == "":
			_clear_glow()
			submit({"type": "spell", "uid": uid, "args": {}})
		else:
			# Cek apakah dijatuhkan langsung di atas kartu target 3D yang sah
			var hit_uid: int = board3d.pick_card_uid_at(global_pos)
			_clear_glow()
			if hit_uid != -1 and _zone_of(hit_uid) == zone:
				submit({"type": "spell", "uid": uid, "args": {"target_uid": hit_uid}})
			else:
				# Masukkan & kunci Spell ke Zona Spell (tidak bisa kembali ke tangan), lalu pilih target
				submit({"type": "spell", "uid": uid, "args": {}})

# --- Interaksi (bab 4.4 / 4.5) ---------------------------------------------

func _zone_of(uid: int) -> String:
	var zones := {
		"hand": view.me.hand, "my_base": view.me.base, "my_special": view.me.special,
		"opp_base": view.opp.base, "opp_special": view.opp.special,
	}
	for z in zones:
		for c in zones[z]:
			if int(c.uid) == uid:
				return z
	return ""

func _card_by_uid(uid: int) -> Dictionary:
	for c in view.me.hand:
		if int(c.uid) == uid:
			return c
	return {}

func _on_card_clicked(uid: int) -> void:
	if view.is_empty() or view.winner != -2:
		return
	if not view.pending.is_empty():
		if String(view.pending.get("type", "")) == "spell_target":
			var req_zone := String(view.pending.get("zone", ""))
			if _zone_of(uid) == req_zone:
				submit({"type": "spell_target", "target_uid": uid})
			else:
				$Toast.show_text("Pilih kartu di zona yang disorot.")
		return                      # efek pending harus diselesaikan dulu
	if not view.my_turn:
		$Toast.show_text("Bukan giliranmu.")
		return
	var zone := _zone_of(uid)
	match mode:
		Mode.IDLE:
			if zone == "hand":
				_click_hand(uid)
			elif zone == "my_base":
				mode = Mode.PICK_SYNTH
				synth_first = uid
				_highlight_zone("my_base")
		Mode.PICK_SYNTH:
			if zone == "my_base" and uid != synth_first:
				submit({"type": "synth", "a": synth_first, "b": uid})
			_reset_mode()
		Mode.PICK_TARGET:
			if zone == pending_zone:
				submit({"type": "spell", "uid": pending_spell_uid, "args": {"target_uid": uid}})
				_reset_mode()
			else:
				$Toast.show_text("Pilih kartu di zona yang disorot.")

func _click_hand(uid: int) -> void:
	var card := _card_by_uid(uid)
	if card.is_empty():
		return
	# Tangan melebihi batas akhir giliran (jika hand_max > 0): klik kartu = membuangnya.
	var hand_max := int(view.rules.hand_max)
	if hand_max > 0 and view.me.hand.size() > hand_max:
		submit({"type": "discard", "uid": uid})
		return
	var data := CardDB.get_card(card.id)
	if data == null:
		return
	if data.type == CardData.Type.BASIC:
		submit({"type": "place", "uid": uid})
	elif data.type == CardData.Type.SPELL:
		# Semua Spell langsung masuk & terkunci di Zona Spell (jika butuh target, lanjut pilih target)
		submit({"type": "spell", "uid": uid, "args": {}})

func _reset_mode() -> void:
	mode = Mode.IDLE
	synth_first = -1
	pending_spell_uid = -1
	pending_zone = ""
	_clear_glow()

func _on_discard_clicked(is_me: bool) -> void:
	if view.is_empty():
		return
	var cards: Array = view.me.discard if is_me else view.opp.get("discard", [])
	var me_idx := int(view.get("me_index", 0))
	var owner_title := ""
	if local_test:
		var p := me_idx if is_me else (1 - me_idx)
		owner_title = "Pemain %d" % (p + 1)
	else:
		owner_title = "Kamu" if is_me else "Lawan"
	$DiscardDrawer.open(cards, owner_title, is_me)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if $DiscardDrawer.is_open():
			$DiscardDrawer.close()
			return
		if $TurnHistory.is_open():
			$TurnHistory.close()
			return
		if $TutorialModal.is_open():
			$TutorialModal.close()
			return
		if $InGameSettings.is_open():
			$InGameSettings.close()         # tutup panel pengaturan lebih dulu
			return
		if $CardPreview.is_open():
			$CardPreview.hide_preview()     # lalu pratinjau kartu
			return
		if String(view.get("pending", {}).get("type", "")) == "spell_target":
			return                          # spell yang sudah di Zona Spell tidak bisa dibatalkan ke tangan
		_reset_mode()

# --- Efek zona (2D untuk tangan, 3D untuk zona arena) ------------------------

func _highlight_zone(zone: String) -> void:
	_clear_glow()
	if zone == "hand":
		var n: Control = $MeHandGlow
		n.visible = true
		n.modulate.a = 0.0
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(n, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_property(n, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	else:
		board3d.highlight_zone(zone)

func _clear_glow() -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null
	$MeHandGlow.visible = false
	if is_instance_valid(board3d):
		board3d.clear_glow()

# --- Hasil (bab 4.7) --------------------------------------------------------

func _show_result() -> void:
	if not _result_sfx_played:
		_result_sfx_played = true
		var me_idx := int(view.get("me_index", 0))
		if local_test or int(view.winner) == me_idx:
			Audio.play_sfx("win_fanfare", -1.0)
		else:
			Audio.play_sfx("lose_jingle", -1.0)
	$Result.show_result(view, REASON_TEXT.get(view.win_reason, ""), local_test, vs_ai, ai_difficulty)

func _rematch() -> void:
	$Result.hide()
	start_as_host()

func _back_to_menu() -> void:
	multiplayer.multiplayer_peer = null
	Net.reset()
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

# --- Jaringan putus dan pewaktu (bab 6.7) ----------------------------------

func _setup_timer() -> void:
	turn_timer.one_shot = true
	turn_timer.timeout.connect(func():
		if state and state.winner == -2:
			# Selesaikan efek yang menunggu dan buang kelebihan sebelum habis waktu.
			if not state.pending.is_empty():
				var ptype := String(state.pending.get("type", ""))
				if ptype == "spektrometer":
					var cs: Array = state.pending.get("cards", [])
					state.resolve_spektrometer(state.current, int(cs[0].uid) if not cs.is_empty() else -1)
				elif ptype == "spell_target":
					var z := String(state.pending.get("zone", ""))
					var arr: Array = []
					match z:
						"my_base": arr = state.players[state.current].base
						"opp_base": arr = state.players[1 - state.current].base
						"my_special": arr = state.players[state.current].special
						"opp_special": arr = state.players[1 - state.current].special
					if not arr.is_empty():
						state.resolve_spell_target(state.current, int(arr[0].uid))
					else:
						state.pending = {}
			state.auto_discard_excess(state.current)
			state.end_turn(state.current)
			_broadcast())
	add_child(turn_timer)

func _on_peer_gone(_id: int) -> void:      # terpicu di host saat klien keluar
	if state and state.winner == -2:
		state.winner = my_index            # host menang WO
		state.win_reason = "surrender"
		render(state.view_for(my_index))
		$Toast.show_text("Lawan terputus. Kamu menang.")

func _on_server_gone() -> void:            # terpicu di klien saat host hilang
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")
