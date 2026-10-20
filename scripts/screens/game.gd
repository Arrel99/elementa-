extends Control

## Papan permainan (bab 4 sampai 6). Satu skrip untuk host dan klien.
## Host = pemain 0 (menjalankan GameState), klien = pemain 1.

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

# efek spell -> zona tempat target dipilih; efek yang tidak ada di sini tanpa target
const SPELL_TARGET := {
    "bilas": "my_base",
    "korosi": "opp_base",
    "elektrolisis": "my_special",
    "elektrolisis_paksa": "opp_special",
}

const REASON_TEXT := {
    "surrender": "Salah satu pemain menyerah.",
    "deck_out": "Deck salah satu pemain habis.",
    "special_full": "10 slot senyawa terisi dan giliran terakhir selesai.",
}

enum Mode { IDLE, PICK_SYNTH, PICK_TARGET }

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

# --- Siklus hidup (bab 4.5 / 6.2) -------------------------------------------

func _ready() -> void:
    local_test = Net.local_test
    $Hud/EndTurn.pressed.connect(func(): submit({"type": "end"}))
    $Hud/GiveUp.pressed.connect($GiveUpDialog.popup_centered)
    $GiveUpDialog.confirmed.connect(func(): submit({"type": "give_up"}))
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

func start_as_host() -> void:
    state = GameState.new()
    state.setup(randi())
    my_index = 0
    _broadcast()

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
    # Spektrometer: kirim info privat hanya ke pemain yang memainkannya (bab 5.1)
    if not state.reveal.is_empty():
        var r: Dictionary = state.reveal
        state.reveal = {}
        if r.to == my_index or local_test:
            _show_reveal(r.cards)
        else:
            var peers := multiplayer.get_peers()
            if not peers.is_empty():
                receive_reveal.rpc_id(peers[0], r.cards)
    _broadcast()
    if not local_test and multiplayer.is_server() and state.winner == -2:
        turn_timer.start(60)

@rpc("authority", "call_remote", "reliable")
func show_error(msg: String) -> void:
    $Toast.show_text(msg)

@rpc("authority", "call_remote", "reliable")
func receive_view(v: Dictionary) -> void:
    render(v)

@rpc("authority", "call_remote", "reliable")
func receive_reveal(cards: Array) -> void:
    _show_reveal(cards)

func _show_reveal(cards: Array) -> void:
    $RevealPopup.show_cards(cards)

func _broadcast() -> void:
    if local_test:
        render(state.view_for(state.current))   # layar menampilkan sudut pandang pemain aktif
        return
    render(state.view_for(0))
    for id in multiplayer.get_peers():
        receive_view.rpc_id(id, state.view_for(1))

# --- Render (bab 4.3 / 4.5) -------------------------------------------------

func render(v: Dictionary) -> void:
    view = v
    _reset_mode()
    _fill($Me/Hand, v.me.hand, true)
    _fill($Me/Base, v.me.base, true)
    _fill($Me/Special, v.me.special, true)
    _fill($Opp/Hand, v.opp.hand_backs, false)   # hanya jumlah, bukan isi
    _fill($Opp/Base, v.opp.base, true)
    _fill($Opp/Special, v.opp.special, true)
    _render_compound_table(v.compound_pile)
    $Hud/Turn.text = "Giliran %d" % v.turn_no
    $Hud/Points.text = "%d : %d" % [v.me.points, v.opp.points]
    $Hud/DeckInfo.text = "Deck %d | Buang %d  •  Lawan deck %d" % [
        v.me.deck_count, v.me.discard.size(), v.opp.deck_count]
    $Hud/EndTurn.disabled = (not v.my_turn) or v.winner != -2
    if v.winner != -2:
        _show_result()

func _fill(box: Container, cards: Array, face_up: bool) -> void:
    for ch in box.get_children():
        ch.queue_free()
    for c in cards:
        var n := CARD_SCENE.instantiate()
        box.add_child(n)
        n.setup(c, face_up)
        n.clicked.connect(_on_card_clicked)
        if box == $Me/Base and int(c.get("placed_turn", -1)) == view.turn_no:
            n.modulate = Color(0.6, 0.6, 0.6)   # masih cooldown

func _render_compound_table(ids: Array) -> void:
    var list: VBoxContainer = $TablePanel/List
    for ch in list.get_children():
        ch.queue_free()
    var mine := {}
    for c in view.me.base:
        mine[c.id] = true
    for id in ids:
        var d := CardDB.get_card(id)
        if d == null or d.recipe.size() != 2:
            continue
        var a := CardDB.get_card(d.recipe[0])
        var b := CardDB.get_card(d.recipe[1])
        var l := Label.new()
        l.text = "%s  =  %s + %s   (%d poin)" % [d.symbol, a.symbol, b.symbol, d.points]
        var have := int(mine.has(d.recipe[0])) + int(mine.has(d.recipe[1]))
        if have == 2:
            l.modulate = Color(0.45, 1.0, 0.45)
        elif have == 1 and easy_mode:
            l.modulate = Color(1.0, 0.9, 0.4)
        list.add_child(l)

# --- Interaksi (bab 4.4 / 4.5) ---------------------------------------------

func _zone_box(z: String) -> Container:
    return {
        "hand": $Me/Hand, "my_base": $Me/Base, "my_special": $Me/Special,
        "opp_base": $Opp/Base, "opp_special": $Opp/Special,
    }[z]

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
                $Hud/Hint.text = "Pilih bahan kedua di zona dasarmu (Esc untuk batal)"
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
            for n in _zone_box(zone).get_children():
                n.modulate = Color(1.0, 0.9, 0.4)   # sorot zona target
            $Hud/Hint.text = "Pilih target di zona yang disorot (Esc untuk batal)"

func _reset_mode() -> void:
    mode = Mode.IDLE
    synth_first = -1
    pending_spell_uid = -1
    pending_zone = ""
    if not view.is_empty():
        $Hud/Hint.text = "Giliranmu" if view.my_turn else "Menunggu lawan..."

func _unhandled_input(e: InputEvent) -> void:
    if e.is_action_pressed("ui_cancel"):
        _reset_mode()

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
