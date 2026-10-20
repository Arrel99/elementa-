class_name GameState
extends RefCounted

## Logika game murni (bab 3). Tidak tahu apa-apa soal Node/UI/tampilan.
## Semua aksi mengembalikan String: kosong = sukses, selain itu pesan error.

var players: Array = []          # 2 Dictionary pemain
var compound_pile: Array = []    # id senyawa yang masih tersedia di Tabel Senyawa
var current: int = 0             # index pemain aktif
var turn_no: int = 1
var synth_left: int = 1
var final_turn_for: int = -1     # pemain yang mendapat giliran terakhir
var final_triggered: bool = false
var winner: int = -2             # -2 belum selesai, -1 seri, 0/1 pemenang
var win_reason: String = ""      # surrender | deck_out | special_full
var reveal: Dictionary = {}      # info privat untuk satu pemain (Spektrometer)

var _next_uid: int = 1
var _effects: Dictionary = {}

func _init() -> void:
    _effects = {
        "katalis": _fx_katalis,
        "bilas": _fx_bilas,
        "elektrolisis": _fx_elektrolisis,
        "elektrolisis_paksa": _fx_elektrolisis_paksa,
        "korosi": _fx_korosi,
        "spektrometer": _fx_spektrometer,
        "perisai_inert": _fx_perisai,
    }

func _rules() -> GameRules:
    return CardDB.rules

func _new_card(id: String) -> Dictionary:
    var c := {"uid": _next_uid, "id": id, "placed_turn": -1}
    _next_uid += 1
    return c

# --- Setup ------------------------------------------------------------------

func setup(rng_seed: int) -> void:
    seed(rng_seed)
    players.clear()
    compound_pile = CardDB.ids_of(CardData.Type.SPECIAL)
    for i in 2:
        players.append({
            "deck": _build_deck(), "hand": [], "base": [], "special": [],
            "discard": [], "points": 0, "shield": false,
        })
        for k in _rules().start_hand:
            draw(i)
    current = 0
    synth_left = 1
    final_turn_for = -1
    final_triggered = false
    winner = -2
    win_reason = ""
    reveal = {}
    draw(current)

func _build_deck() -> Array:
    var r := _rules()
    var n_basic := roundi(r.deck_size * r.basic_share)
    var d: Array = []
    d.append_array(_pick_weighted(CardData.Type.BASIC, n_basic))
    d.append_array(_pick_weighted(CardData.Type.SPELL, r.deck_size - n_basic))
    d.shuffle()
    return d

func _pick_weighted(t: CardData.Type, count: int) -> Array:
    var bag: Array = []
    for c in CardDB.cards.values():
        if c.type == t and c.in_deck:
            for i in maxi(1, c.weight):
                bag.append(c.id)
    var out: Array = []
    if bag.is_empty():
        return out
    for i in count:
        out.append(_new_card(bag.pick_random()))
    return out

# --- Bantuan ----------------------------------------------------------------

func draw(p: int) -> bool:
    var pl = players[p]
    if pl.deck.is_empty():
        _end_game_deck_out(p)
        return false
    var c = pl.deck.pop_back()
    if pl.hand.size() >= _rules().hand_max:
        # Tangan penuh: kartu dibakar ke tumpukan buang supaya deck tetap
        # menyusut dan kondisi "deck habis" bisa tercapai (menghindari buntu).
        pl.discard.append(c)
        return true
    pl.hand.append(c)
    return true

func _take(arr: Array, uid: int) -> Dictionary:
    for i in arr.size():
        if arr[i].uid == uid:
            return arr.pop_at(i)
    return {}

func _peek(arr: Array, uid: int) -> Dictionary:
    for c in arr:
        if c.uid == uid:
            return c
    return {}

# --- Aksi dasar -------------------------------------------------------------

func place_base(p: int, uid: int) -> String:
    if p != current:
        return "Bukan giliranmu."
    var pl = players[p]
    if pl.base.size() >= _rules().base_max:
        return "Zona dasar penuh. Lakukan sintesis atau Bilas dulu."
    var c := _take(pl.hand, uid)
    if c.is_empty():
        return "Kartu tidak ada di tangan."
    if CardDB.get_card(c.id).type != CardData.Type.BASIC:
        pl.hand.append(c)
        return "Hanya kartu dasar yang boleh dipasang ke zona dasar."
    c.placed_turn = turn_no      # cooldown 1 giliran
    pl.base.append(c)
    return ""

func synthesize(p: int, uid_a: int, uid_b: int) -> String:
    if p != current:
        return "Bukan giliranmu."
    if synth_left <= 0:
        return "Jatah sintesis giliran ini habis."
    var pl = players[p]
    if pl.special.size() >= _rules().special_max:
        return "Slot senyawa penuh."
    var a := _peek(pl.base, uid_a)
    var b := _peek(pl.base, uid_b)
    if a.is_empty() or b.is_empty() or uid_a == uid_b:
        return "Pilih 2 kartu dasar berbeda."
    if a.placed_turn == turn_no or b.placed_turn == turn_no:
        return "Kartu yang baru dipasang belum bisa dipakai sintesis (cooldown)."
    var result := CardDB.find_recipe(a.id, b.id)
    if result == "":
        return "Kombinasi ini tidak ada di Tabel Senyawa."
    if not compound_pile.has(result):
        return "Senyawa itu sudah diambil."
    _take(pl.base, uid_a)
    _take(pl.base, uid_b)
    pl.discard.append(a)
    pl.discard.append(b)
    compound_pile.erase(result)
    var sc := _new_card(result)
    sc["parts"] = [a.id, b.id]   # dipakai Elektrolisis Paksa
    pl.special.append(sc)
    pl.points += CardDB.get_card(result).points
    synth_left -= 1
    _check_special_full(p)
    return ""

# --- Spell dan efek (bab 5) -------------------------------------------------

func play_spell(p: int, uid: int, args: Dictionary) -> String:
    if p != current:
        return "Bukan giliranmu."
    var pl = players[p]
    var c := _peek(pl.hand, uid)
    if c.is_empty():
        return "Kartu tidak ada di tangan."
    var data := CardDB.get_card(c.id)
    if data == null or data.type != CardData.Type.SPELL:
        return "Bukan spell."
    var fn: Callable = _effects.get(data.spell_effect, Callable())
    if fn.is_null():
        return "Efek belum diimplementasi."
    var err: String = fn.call(p, args)
    if err != "":
        return err
    pl.discard.append(_take(pl.hand, uid))
    return ""

func _blocked_by_shield(i: int) -> bool:
    if players[i].shield:
        players[i].shield = false   # Perisai Inert terpakai
        return true
    return false

func _fx_katalis(p: int, _a: Dictionary) -> String:
    synth_left += 1       # tambahan sintesis; TIDAK membebaskan cooldown
    return ""

func _fx_bilas(p: int, a: Dictionary) -> String:
    var c := _take(players[p].base, int(a.get("target_uid", -1)))
    if c.is_empty():
        return "Pilih kartu di zona dasarmu."
    players[p].discard.append(c)
    return ""

func _fx_perisai(p: int, _a: Dictionary) -> String:
    players[p].shield = true
    return ""

func _fx_korosi(p: int, a: Dictionary) -> String:
    if _blocked_by_shield(1 - p):
        return ""
    var c := _take(players[1 - p].base, int(a.get("target_uid", -1)))
    if c.is_empty():
        return "Pilih kartu di zona dasar lawan."
    players[1 - p].discard.append(c)
    return ""

func _fx_elektrolisis(p: int, a: Dictionary) -> String:
    var pl = players[p]
    var sc := _peek(pl.special, int(a.get("target_uid", -1)))
    if sc.is_empty():
        return "Pilih senyawa milikmu."
    if pl.base.size() + 2 > _rules().base_max:
        return "Zona dasar tidak cukup untuk 2 kartu."
    _take(pl.special, sc.uid)
    pl.points -= CardDB.get_card(sc.id).points
    compound_pile.append(sc.id)
    for part in sc.get("parts", []):
        var nc := _new_card(part)
        nc.placed_turn = turn_no     # cooldown berlaku
        pl.base.append(nc)
    return ""

func _fx_elektrolisis_paksa(p: int, a: Dictionary) -> String:
    if _blocked_by_shield(1 - p):
        return ""
    var opp = players[1 - p]
    var sc := _take(opp.special, int(a.get("target_uid", -1)))
    if sc.is_empty():
        return "Pilih senyawa milik lawan."
    opp.points -= CardDB.get_card(sc.id).points
    compound_pile.append(sc.id)
    for part in sc.get("parts", []):
        if opp.hand.size() < _rules().hand_max:
            opp.hand.append(_new_card(part))
        else:
            opp.discard.append(_new_card(part))   # tangan penuh: dibuang
    return ""

func _fx_spektrometer(p: int, _a: Dictionary) -> String:
    reveal = {"to": p, "cards": players[1 - p].hand.duplicate(true)}
    return ""

# --- Giliran dan kondisi menang (bab 3.3) -----------------------------------

func _check_special_full(p: int) -> void:
    if players[p].special.size() >= _rules().special_max and not final_triggered:
        final_triggered = true
        final_turn_for = 1 - p   # lawan mendapat 1 giliran terakhir

func end_turn(p: int) -> String:
    if p != current:
        return "Bukan giliranmu."
    if winner != -2:
        return "Game sudah selesai."
    # Giliran terakhir lawan baru saja selesai: hitung poin.
    if final_triggered and final_turn_for == p:
        win_reason = "special_full"
        _finish_by_points()
        return ""
    current = 1 - current
    turn_no += 1
    synth_left = 1
    draw(current)
    return ""

func surrender(p: int) -> void:
    winner = 1 - p
    win_reason = "surrender"

func _end_game_deck_out(_p: int) -> void:
    win_reason = "deck_out"
    _finish_by_points()

func _finish_by_points() -> void:
    var a: int = players[0].points
    var b: int = players[1].points
    winner = 0 if a > b else (1 if b > a else -1)

# --- Tampilan aman per pemain (bab 6.3) -------------------------------------

func view_for(p: int) -> Dictionary:
    var me = players[p]
    var op = players[1 - p]
    return {
        "turn_no": turn_no, "my_turn": current == p, "winner": winner,
        "synth_left": synth_left, "me_index": p, "win_reason": win_reason,
        "compound_pile": compound_pile.duplicate(),
        "me": {
            "hand": me.hand.duplicate(true), "base": me.base.duplicate(true),
            "special": me.special.duplicate(true), "points": me.points,
            "deck_count": me.deck.size(), "discard": me.discard.duplicate(true),
        },
        "opp": {
            "hand_backs": _backs(op.hand.size()), "base": op.base.duplicate(true),
            "special": op.special.duplicate(true), "points": op.points,
            "deck_count": op.deck.size(),
        },
    }

func _backs(n: int) -> Array:
    var arr: Array = []
    for i in n:
        arr.append({"uid": -1, "id": "back", "placed_turn": -1})
    return arr
