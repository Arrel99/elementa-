class_name GameState
extends RefCounted

## Logika game murni (Buku Peraturan Elementa: Kartu Reaksi).
## Tidak tahu apa-apa soal Node/UI/tampilan.
## Semua aksi mengembalikan String: kosong = sukses, selain itu pesan error.

var players: Array = []          # 2 Dictionary pemain
var compound_pile: Array = []    # id senyawa yang masih tersedia di Tabel Senyawa
var current: int = 0             # index pemain aktif
var turn_no: int = 1
var synth_left: int = 1          # sisa aksi sintesis giliran ini (Katalis menambah)
var spell_left: int = 1          # sisa jatah spell giliran ini (Katalis tidak memakai)
var countdown: int = -1          # hitungan mundur zona spesial; -1 = belum dipicu
var winner: int = -2             # -2 belum selesai, -1 seri, 0/1 pemenang
var win_reason: String = ""      # surrender | deck_out | special_full
var pending: Dictionary = {}     # efek interaktif yang menunggu penyelesaian (Spektrometer)

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

# --- Setup (bagian 5) -------------------------------------------------------

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
			_draw_one(i)
	current = randi() % 2        # pemain pertama ditentukan acak (bagian 5)
	turn_no = 1
	synth_left = 1
	spell_left = 1
	countdown = -1
	winner = -2
	win_reason = ""
	pending = {}

## Deck 60 kartu: jumlah salinan tiap kartu ada di field deck_copies (Lampiran A/C).
## Kartu spesial (senyawa) tidak pernah masuk deck.
func _build_deck() -> Array:
	var d: Array = []
	for c in CardDB.cards.values():
		if not c.in_deck:
			continue
		for i in c.deck_copies:
			d.append(_new_card(c.id))
	d.shuffle()
	return d

# --- Bantuan ----------------------------------------------------------------

func _draw_one(p: int) -> Dictionary:
	var pl = players[p]
	if pl.deck.is_empty():
		return {}
	var c = pl.deck.pop_back()
	pl.hand.append(c)
	return c

## Fase menarik kartu (bagian 6). Bila sisa deck kurang dari draw_per_turn,
## pemain menarik seluruh sisanya lalu permainan berakhir (bagian 9).
func _draw_phase(p: int) -> void:
	var pl = players[p]
	var want: int = _rules().draw_per_turn
	if pl.deck.size() < want:
		while not pl.deck.is_empty():
			_draw_one(p)
		win_reason = "deck_out"
		_finish_by_points()
		return
	for i in want:
		_draw_one(p)

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

func _turn_guard(p: int) -> String:
	if p != current:
		return "Bukan giliranmu."
	if winner != -2:
		return "Game sudah selesai."
	if not pending.is_empty():
		return "Selesaikan efek Spektrometer dulu."
	return ""

# --- Aksi dasar -------------------------------------------------------------

func place_base(p: int, uid: int) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	if pl.base.size() >= _rules().base_max:
		return "Zona dasar penuh. Lakukan sintesis atau pakai Bilas dulu."
	var c := _take(pl.hand, uid)
	if c.is_empty():
		return "Kartu tidak ada di tangan."
	if CardDB.get_card(c.id).type != CardData.Type.BASIC:
		pl.hand.append(c)
		return "Hanya kartu dasar yang boleh dipasang ke zona dasar."
	c.placed_turn = turn_no      # cooldown 1 giliran (bagian 7)
	pl.base.append(c)
	return ""

## Membuang kelebihan kartu di akhir giliran (bagian 4 & 6). Pemain memilih sendiri.
func discard_from_hand(p: int, uid: int) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	if pl.hand.size() <= _rules().hand_max:
		return "Tangan belum melebihi batas."
	var c := _take(pl.hand, uid)
	if c.is_empty():
		return "Kartu tidak ada di tangan."
	pl.discard.append(c)
	return ""

## Kemudahan untuk bot/pewaktu: buang kartu bernilai terendah sampai batas aman.
func auto_discard_excess(p: int) -> void:
	var pl = players[p]
	while pl.hand.size() > _rules().hand_max:
		var worst_i := 0
		var worst := 1 << 30
		for i in pl.hand.size():
			var cd = CardDB.get_card(pl.hand[i].id)
			var v: int = cd.points if cd != null else 0
			if v < worst:
				worst = v
				worst_i = i
		pl.discard.append(pl.hand.pop_at(worst_i))

func synthesize(p: int, uid_a: int, uid_b: int) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	if synth_left <= 0:
		return "Jatah sintesis giliran ini habis (Katalis bisa menambah)."
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
		return "Senyawa itu sudah diambil pemain lain."
	_take(pl.base, uid_a)
	_take(pl.base, uid_b)
	pl.discard.append(a)          # kedua kartu dasar dibuang (bagian 7.4)
	pl.discard.append(b)
	compound_pile.erase(result)   # senyawa diambil dari Tabel Senyawa bersama
	var sc := _new_card(result)
	sc["parts"] = [a.id, b.id]    # dipakai Elektrolisis / Elektrolisis Paksa
	pl.special.append(sc)
	pl.points += CardDB.get_card(result).points
	synth_left -= 1
	_check_special_trigger(p)
	return ""

# --- Spell dan efek (bagian 8) ----------------------------------------------

func play_spell(p: int, uid: int, args: Dictionary) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	var c := _peek(pl.hand, uid)
	if c.is_empty():
		return "Kartu tidak ada di tangan."
	var data := CardDB.get_card(c.id)
	if data == null or data.type != CardData.Type.SPELL:
		return "Bukan spell."
	var is_katalis: bool = data.spell_effect == "katalis"
	if not is_katalis and spell_left <= 0:
		return "Spell giliran ini sudah dipakai."
	var fn: Callable = _effects.get(data.spell_effect, Callable())
	if fn.is_null():
		return "Efek belum diimplementasi."
	var err: String = fn.call(p, args)
	if err != "":
		return err
	pl.discard.append(_take(pl.hand, uid))
	if not is_katalis:
		spell_left -= 1           # Katalis tidak mengurangi jatah spell (bagian 8)
	return ""

func _fx_katalis(p: int, _a: Dictionary) -> String:
	synth_left += 1               # aksi sintesis tambahan; tidak membebaskan cooldown
	return ""

func _fx_bilas(p: int, a: Dictionary) -> String:
	var c := _take(players[p].base, int(a.get("target_uid", -1)))
	if c.is_empty():
		return "Pilih kartu di zona dasarmu."
	players[p].discard.append(c)
	_draw_one(p)                  # lalu tarik 1 kartu baru (bagian 8)
	return ""

func _fx_perisai(p: int, _a: Dictionary) -> String:
	players[p].shield = true      # berlaku sampai awal giliran sendiri berikutnya
	return ""

func _fx_korosi(p: int, a: Dictionary) -> String:
	if players[1 - p].shield:
		return ""                 # ditangkal Perisai Inert
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
	_take(pl.special, sc.uid)
	pl.points -= CardDB.get_card(sc.id).points
	compound_pile.append(sc.id)          # senyawa kembali ke Tabel Senyawa
	for part in sc.get("parts", []):
		pl.hand.append(_new_card(part))  # 2 unsur kembali ke tangan pemilik
	return ""

func _fx_elektrolisis_paksa(p: int, a: Dictionary) -> String:
	if players[1 - p].shield:
		return ""                 # ditangkal Perisai Inert
	var opp = players[1 - p]
	var sc := _take(opp.special, int(a.get("target_uid", -1)))
	if sc.is_empty():
		return "Pilih senyawa milik lawan."
	opp.points -= CardDB.get_card(sc.id).points
	compound_pile.append(sc.id)          # senyawa kembali ke Tabel Senyawa
	for part in sc.get("parts", []):
		opp.hand.append(_new_card(part)) # 2 unsur kembali ke tangan lawan
	return ""

func _fx_spektrometer(p: int, _a: Dictionary) -> String:
	var pl = players[p]
	var top: Array = []
	for i in mini(3, pl.deck.size()):
		top.append(pl.deck.pop_back())    # 3 kartu teratas deck sendiri
	pending = {"type": "spektrometer", "to": p, "cards": top}
	return ""

## Menyelesaikan Spektrometer: ambil 1 kartu ke tangan, sisa dikembalikan ke
## deck, lalu deck diacak kembali (aturan tim: hasil intip tidak bisa dilacak).
func resolve_spektrometer(p: int, take_uid: int) -> String:
	if pending.is_empty() or String(pending.get("type", "")) != "spektrometer":
		return "Tidak ada efek Spektrometer yang menunggu."
	if int(pending.get("to", -1)) != p:
		return "Bukan efek milikmu."
	var cards: Array = pending.get("cards", [])
	var take := _peek(cards, take_uid)
	if take.is_empty():
		return "Pilih satu kartu untuk diambil."
	for c in cards:
		if c.uid != take_uid:
			players[p].deck.append(c)
	players[p].deck.shuffle()     # deck diacak lagi setelah efek selesai
	players[p].hand.append(take)
	pending = {}
	return ""

# --- Giliran dan kondisi menang (bagian 6 & 9) ------------------------------

## Zona spesial menyentuh ambang: mulai hitungan mundur sekali saja (bagian 9.3).
func _check_special_trigger(p: int) -> void:
	if countdown < 0 and players[p].special.size() >= _rules().special_win_threshold:
		countdown = _rules().special_win_countdown

func end_turn(p: int) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	if pl.hand.size() > _rules().hand_max:
		return "Tangan melebihi %d kartu. Buang dulu (klik kartunya)." % _rules().hand_max
	# hitungan mundur berjalan tiap akhir giliran kedua pemain (bagian 9.3)
	if countdown > 0:
		countdown -= 1
	current = 1 - current
	turn_no += 1
	synth_left = 1
	spell_left = 1
	players[current].shield = false   # perisai berakhir di awal giliran sendiri (bagian 8)
	if countdown == 0:
		win_reason = "special_full"
		_finish_by_points()
		return ""
	_draw_phase(current)
	return ""

func surrender(p: int) -> void:
	winner = 1 - p
	win_reason = "surrender"

## Poin sama -> kartu spesial terbanyak menang; masih sama -> seri (bagian 9).
func _finish_by_points() -> void:
	var a: int = players[0].points
	var b: int = players[1].points
	if a != b:
		winner = 0 if a > b else 1
		return
	var sa: int = players[0].special.size()
	var sb: int = players[1].special.size()
	if sa != sb:
		winner = 0 if sa > sb else 1
		return
	winner = -1

# --- Tampilan aman per pemain (bagian 6.3) ---------------------------------

func view_for(p: int) -> Dictionary:
	var me = players[p]
	var op = players[1 - p]
	return {
		"turn_no": turn_no, "my_turn": current == p, "winner": winner,
		"synth_left": synth_left, "spell_left": spell_left,
		"countdown": countdown, "me_index": p, "win_reason": win_reason,
		"compound_pile": compound_pile.duplicate(),
		"rules": {
			"hand_max": _rules().hand_max, "base_max": _rules().base_max,
			"special_max": _rules().special_max,
			"special_win_threshold": _rules().special_win_threshold,
		},
		"pending": _pending_view(p),
		"me": {
			"hand": me.hand.duplicate(true), "base": me.base.duplicate(true),
			"special": me.special.duplicate(true), "points": me.points,
			"deck_count": me.deck.size(), "discard": me.discard.duplicate(true),
			"shield": me.shield,
		},
		"opp": {
			"hand_backs": _backs(op.hand.size()), "base": op.base.duplicate(true),
			"special": op.special.duplicate(true), "points": op.points,
			"deck_count": op.deck.size(), "discard_count": op.discard.size(),
			"shield": op.shield,
		},
	}

func _pending_view(p: int) -> Dictionary:
	if pending.is_empty() or int(pending.get("to", -1)) != p:
		return {}
	return {"type": pending.get("type", ""), "cards": pending.get("cards", []).duplicate(true)}

func _backs(n: int) -> Array:
	var arr: Array = []
	for i in n:
		arr.append({"uid": -1, "id": "back", "placed_turn": -1})
	return arr
