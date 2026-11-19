extends Control

## Papan permainan 2.5D (Arena 3D + HUD & Tangan 2D).
## Satu skrip untuk host dan klien.
## Host = pemain 0 (menjalankan GameState), klien = pemain 1.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

# Ukuran kartu tangan di overlay 2D (skala dasar untuk tinggi jendela 1080)
const SIZE_HAND := Vector2(114, 152)
const SIZE_OPP_HAND := Vector2(76, 102)
const HUD_BASE_SIZE := Vector2(150, 320)
const HUD_PAD := 8.0

# efek spell -> zona tempat target dipilih; efek yang tidak ada di sini tanpa target
const SPELL_TARGET := {
	"bilas": "my_base",
	"korosi": "opp_base",
	"elektrolisis": "my_special",
	"elektrolisis_paksa": "opp_special",
}

const REASON_TEXT := {
	"surrender": "Salah satu pemain menyerah.",
	"deck_out": "Deck salah satu pemain tidak cukup untuk menarik 2 kartu.",
	"special_full": "Zona senyawa menyentuh 8 slot; hitungan mundur 3 giliran selesai.",
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
var easy_mode := true
var turn_timer := Timer.new()
var _pending_key := ""          # penanda efek interaktif yang sedang ditampilkan
var _glow_tween: Tween          # denyut glow zona tangan
var _playable := {}             # uid kartu yang bisa dimainkan (dari state)
var _ui_scale := 1.0

# Status animasi drag & drop kartu dari tangan
var _drag_uid := -1
var _drag_source: Control = null
var _drag_ghost: Control = null
var _drag_target_pos := Vector2.ZERO
var _drag_last_pos := Vector2.ZERO

# --- Siklus hidup (bab 4.5 / 6.2) -------------------------------------------

func _ready() -> void:
	local_test = Net.local_test
	resized.connect(_layout)
	_layout()

	board3d.card_clicked.connect(_on_card_clicked)
	board3d.card_preview_hover.connect(_on_preview_hover)
	board3d.card_preview_exit.connect(_on_preview_exit)
	board3d.card_preview_pin.connect(_on_preview_pin)

	$Hud/EndTurn.pressed.connect(func(): submit({"type": "end"}))
	$InGameSettings.give_up_requested.connect($GiveUpDialog.popup_centered)
	$InGameSettings.back_to_menu_requested.connect(_back_to_menu)
	$TutorialCoach.open_full_guide_requested.connect(func(): $TutorialModal.open(0))
	$GiveUpDialog.confirmed.connect(func(): submit({"type": "give_up"}))
	$RevealPopup.resolved.connect(_on_spektrometer_resolved)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.server_disconnected.connect(_on_server_gone)
	_setup_timer()

	# Godot memakai OfflineMultiplayerPeer saat tidak ada jaringan, dan peer
	# itu melaporkan is_server() = true. Deteksi tipe peer-nya lebih dulu.
	var offline := multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	if local_test or offline:
		# Mode uji lokal satu layar (bab 4.8): dua pemain bergantian.
		local_test = true
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

func start_as_host() -> void:
	state = GameState.new()
	state.setup(randi())
	my_index = 0
	_broadcast()

# --- Tata letak responsif (Overlay 2D di atas Arena 3D) ----------------------

func _layout() -> void:
	var w := maxf(size.x, 320.0)
	var h := maxf(size.y, 240.0)
	_ui_scale = clampf(minf(w / 1920.0, h / 1080.0), 0.35, 1.35)

	# HUD di sisi kanan tengah (Skor Lawan + END TURN + Skor Kamu)
	var hud_w := HUD_BASE_SIZE.x * _ui_scale
	var hud_h := HUD_BASE_SIZE.y * _ui_scale
	var hud_x := w - hud_w - 18.0 * _ui_scale
	var hud_y := (h - hud_h) * 0.5

	var hudbg: Control = $HudBg
	hudbg.position = Vector2(hud_x, hud_y)
	hudbg.size = HUD_BASE_SIZE
	hudbg.scale = Vector2(_ui_scale, _ui_scale)

	var hud: Control = $Hud
	hud.position = Vector2(hud_x + HUD_PAD * _ui_scale, hud_y + HUD_PAD * _ui_scale)
	hud.size = HUD_BASE_SIZE - Vector2(HUD_PAD, HUD_PAD) * 2.0
	hud.scale = Vector2(_ui_scale, _ui_scale)

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
	if local_test:
		_handle(1 if state.current == 0 else 2, action)   # pemain aktif yang bertindak
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
		"place":   err = state.place_base(p, int(a.get("uid", -1)))
		"synth":   err = state.synthesize(p, int(a.get("a", -1)), int(a.get("b", -1)))
		"spell":   err = state.play_spell(p, int(a.get("uid", -1)), a.get("args", {}))
		"discard": err = state.discard_from_hand(p, int(a.get("uid", -1)))
		"spektro": err = state.resolve_spektrometer(p, int(a.get("take", -1)))
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
	if not local_test and multiplayer.is_server() and state.winner == -2:
		turn_timer.start(60)

@rpc("authority", "call_remote", "reliable")
func show_error(msg: String) -> void:
	$Toast.show_text(msg)

@rpc("authority", "call_remote", "reliable")
func receive_view(v: Dictionary) -> void:
	render(v)

func _on_spektrometer_resolved(take_uid: int) -> void:
	submit({"type": "spektro", "take": take_uid})

func _broadcast() -> void:
	if local_test:
		render(state.view_for(state.current))   # layar menampilkan sudut pandang pemain aktif
		return
	render(state.view_for(0))
	for id in multiplayer.get_peers():
		receive_view.rpc_id(id, state.view_for(1))

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
	if over and v.my_turn and v.winner == -2:
		_highlight_zone("hand")     # tangan melebihi batas: sorot zona tangan
	$InGameSettings.set_status(
		"Giliran %d  (sintesis %d, spell %d)%s" % [
			v.turn_no, v.synth_left, v.spell_left, extra],
		"Deck %d | Buang %d  •  Lawan deck %d" % [
			v.me.deck_count, v.me.discard.size(), v.opp.deck_count])
	_sync_pending(v)
	_sync_coach()
	if v.winner != -2:
		_show_result()

## Menampilkan efek interaktif (Spektrometer) hanya untuk pemiliknya.
func _sync_pending(v: Dictionary) -> void:
	var key := ""
	if not v.pending.is_empty():
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
	$CardPreview.hover(data, source)

func _on_preview_exit(source: Node) -> void:
	$CardPreview.unhover(source)

func _on_preview_pin(data: Dictionary, source: Node) -> void:
	if _drag_ghost != null:
		return
	$CardPreview.pin(data, source)

# --- Drag & Drop kartu tangan -----------------------------------------------

func _on_hand_drag_started(uid: int, card_node: Control, global_pos: Vector2) -> void:
	if view.is_empty() or view.winner != -2 or not view.my_turn or not view.pending.is_empty():
		return
	var card := _card_by_uid(uid)
	if card.is_empty():
		return
	_cancel_drag_immediate()
	$CardPreview.hide_preview()

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

func _on_hand_drag_moved(_uid: int, _card_node: Control, global_pos: Vector2) -> void:
	_drag_target_pos = global_pos

func _on_hand_drag_ended(uid: int, card_node: Control, global_pos: Vector2) -> void:
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

	# Animasi singkat kartu masuk ke papan saat dilepas
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "scale", Vector2(0.72, 0.72), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
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
			if hit_uid != -1 and _zone_of(hit_uid) == zone:
				_clear_glow()
				submit({"type": "spell", "uid": uid, "args": {"target_uid": hit_uid}})
			else:
				mode = Mode.PICK_TARGET
				pending_spell_uid = uid
				pending_zone = zone
				_highlight_zone(zone)
				_sync_coach()

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
		return                      # efek Spektrometer harus diselesaikan dulu
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
				_sync_coach()
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
		var zone: String = SPELL_TARGET.get(String(data.spell_effect), "")
		if zone == "":
			submit({"type": "spell", "uid": uid, "args": {}})
		else:
			mode = Mode.PICK_TARGET
			pending_spell_uid = uid
			pending_zone = zone
			_highlight_zone(zone)           # sorot zona target (efek, bukan teks)
			_sync_coach()

func _reset_mode() -> void:
	mode = Mode.IDLE
	synth_first = -1
	pending_spell_uid = -1
	pending_zone = ""
	_clear_glow()
	_sync_coach()

func _sync_coach() -> void:
	if is_instance_valid($TutorialCoach) and not view.is_empty():
		$TutorialCoach.update_state(view, int(mode), synth_first, pending_zone)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if $TutorialModal.is_open():
			$TutorialModal.close()
			return
		if $InGameSettings.is_open():
			$InGameSettings.close()         # tutup panel pengaturan lebih dulu
			return
		if $CardPreview.is_open():
			$CardPreview.hide_preview()     # lalu pratinjau kartu
			return
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
	var w: int = view.winner
	$Result/Title.text = "Seri!" if w == -1 else ("Kamu menang!" if w == view.me_index else "Kamu kalah.")
	$Result/Reason.text = REASON_TEXT.get(view.win_reason, "")
	$Result/Score.text = "Poin kamu %d : %d poin lawan" % [view.me.points, view.opp.points]
	$Result.show()
	if not $Result/Back.pressed.is_connected(_back_to_menu):
		$Result/Back.pressed.connect(_back_to_menu)

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
				var cs: Array = state.pending.get("cards", [])
				state.resolve_spektrometer(state.current, int(cs[0].uid) if not cs.is_empty() else -1)
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
