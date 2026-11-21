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
var history: Array = []          # riwayat kronologis kartu yang dimainkan per giliran

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
	# Deck Senyawa bersama: tiap senyawa punya beberapa salinan (aturan
	# compound_copies) supaya kedua pemain bisa menyintesis senyawa yang sama.
	compound_pile = []
	for id in CardDB.ids_of(CardData.Type.SPECIAL):
		for i in _rules().compound_copies:
			compound_pile.append(id)
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
	history = []

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

func place_base(p: int, uid: int, slot: int = -1) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	var max_slots: int = _rules().base_max
	if pl.base.size() >= max_slots:
		return "Zona dasar penuh. Lakukan sintesis atau pakai Bilas dulu."
	var used := {}
	for i in pl.base.size():
		used[int(pl.base[i].get("slot", i))] = true
	var chosen := slot
	if chosen >= 0:
		if chosen >= max_slots:
			return "Slot zona dasar tidak valid."
		if used.has(chosen):
			return "Slot itu sudah terisi."
	else:
		for i in max_slots:
			if not used.has(i):
				chosen = i
				break
	var c := _take(pl.hand, uid)
	if c.is_empty():
		return "Kartu tidak ada di tangan."
	if CardDB.get_card(c.id).type != CardData.Type.BASIC:
		pl.hand.append(c)
		return "Hanya kartu dasar yang boleh dipasang ke zona dasar."
	c.placed_turn = turn_no      # cooldown 1 giliran (bagian 7)
	c["slot"] = chosen
	pl.base.append(c)
	_record(p, "place", c.id, "Pasang %s (Slot %d)" % [_card_label(c.id), chosen + 1])
	return ""

## Membuang kelebihan kartu di akhir giliran (bagian 4 & 6). Pemain memilih sendiri.
func discard_from_hand(p: int, uid: int) -> String:
	var g := _turn_guard(p)
	if g != "":
		return g
	var pl = players[p]
	if _rules().hand_max <= 0 or pl.hand.size() <= _rules().hand_max:
		return "Tangan belum melebihi batas."
	var c := _take(pl.hand, uid)
	if c.is_empty():
		return "Kartu tidak ada di tangan."
	pl.discard.append(c)
	_record(p, "discard", c.id, "Buang %s" % _card_label(c.id))
	return ""

## Kemudahan untuk bot/pewaktu: buang kartu bernilai terendah sampai batas aman.
func auto_discard_excess(p: int) -> void:
	if _rules().hand_max <= 0:
		return
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
	# Kedua kartu dasar asli menempel di belakang kartu senyawa (bukan ke discard),
	# sehingga saat Elektrolisis kartu asli tersebut kembali ke tangan tanpa duplikasi.
	a.placed_turn = -1
	b.placed_turn = -1
	a.erase("slot")
	b.erase("slot")
	# Hanya 1 salinan yang diambil; senyawa yang sama masih bisa disintesis
	# pemain lain selama salinannya di Deck Senyawa masih tersisa.
	var pile_i := compound_pile.find(result)
	if pile_i >= 0:
		compound_pile.remove_at(pile_i)
	var sc := _new_card(result)
	sc["attached"] = [a, b]       # 2 kartu dasar asli menempel di belakang senyawa
	sc["parts"] = [a.id, b.id]    # daftar id bahan untuk kompatibilitas
	pl.special.append(sc)
	var pts: int = CardDB.get_card(result).points
	pl.points += pts
	synth_left -= 1
	_record(p, "synth", result, "Sintesis %s + %s -> %s (+%d)" % [
		_card_sym(a.id), _card_sym(b.id), _card_label(result), pts])
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
	var spell_detail := _describe_spell_before(p, data, args)
	var err: String = fn.call(p, args)
	if err != "":
		return err
	pl.discard.append(_take(pl.hand, uid))
	if not is_katalis:
		spell_left -= 1           # Katalis tidak mengurangi jatah spell (bagian 8)
	_record(p, "spell", c.id, spell_detail)
	return ""

func _describe_spell_before(p: int, data: CardData, args: Dictionary) -> String:
	var target_uid := int(args.get("target_uid", -1))
	match data.spell_effect:
		"katalis":
			return "Katalis (+1 sintesis)"
		"perisai_inert":
			return "Perisai Inert (aktif)"
		"spektrometer":
			return "Spektrometer (intip 3 kartu)"
		"bilas":
			var tc := _peek(players[p].base, target_uid)
			return "Bilas -> %s" % (_card_label(tc.id) if not tc.is_empty() else "-")
		"korosi":
			if players[1 - p].shield:
				return "Korosi (ditangkal Perisai)"
			var tc := _peek(players[1 - p].base, target_uid)
			return "Korosi -> %s" % (_card_label(tc.id) if not tc.is_empty() else "-")
		"elektrolisis":
			var sc := _peek(players[p].special, target_uid)
			return "Elektrolisis -> %s" % (_card_label(sc.id) if not sc.is_empty() else "-")
		"elektrolisis_paksa":
			if players[1 - p].shield:
				return "Elektrolisis Paksa (ditangkal Perisai)"
			var sc := _peek(players[1 - p].special, target_uid)
			return "Elektrolisis Paksa -> %s" % (_card_label(sc.id) if not sc.is_empty() else "-")
		_:
			return data.display_name

func _card_label(id: String) -> String:
	var d := CardDB.get_card(id)
	if d == null:
		return id
	return "%s (%s)" % [d.display_name, d.symbol] if d.symbol != "" else d.display_name

func _card_sym(id: String) -> String:
	var d := CardDB.get_card(id)
	return d.symbol if (d != null and d.symbol != "") else id

func _record(p: int, action: String, card_id: String, detail: String) -> void:
	history.append({
		"turn": turn_no,
		"player": p,
		"action": action,
		"card_id": card_id,
		"detail": detail,
	})

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
	_return_attached_to_hand(pl, sc)
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
	_return_attached_to_hand(opp, sc)
	return ""

## Mengembalikan 2 kartu dasar asli yang menempel di belakang senyawa ke tangan
## pemiliknya tanpa menggandakan jumlah kartu di dalam permainan.
func _return_attached_to_hand(pl: Dictionary, sc: Dictionary) -> void:
	var attached: Array = sc.get("attached", [])
	if not attached.is_empty():
		for base_card in attached:
			base_card["placed_turn"] = -1
			base_card.erase("slot")
			pl.hand.append(base_card)
		sc["attached"] = []
		return
	for part in sc.get("parts", []):
		pl.hand.append(_new_card(part))

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

# --- Predikat "bisa dimainkan" untuk UI (bagian 4.4) -------------------------
#
# Papan perlu tahu kartu mana yang bisa dimainkan SEKARANG tanpa harus mencoba
# aksinya (yang akan mengubah state). Predikat di bawah menyalin syarat fungsi
# aksi di atas tanpa efek samping, supaya aturan tetap hidup di satu tempat.

## Spell dengan target: true bila targetnya ada sekarang.
func _spell_has_target(p: int, effect: String) -> bool:
	var me = players[p]
	var op = players[1 - p]
	match effect:
		"bilas":
			return not me.base.is_empty()
		"korosi":
			return not op.shield and not op.base.is_empty()
		"elektrolisis":
			return not me.special.is_empty()
		"elektrolisis_paksa":
			return not op.shield and not op.special.is_empty()
		_:
			return true             # katalis / perisai_inert / spektrometer tanpa target

## Kartu dasar di tangan boleh dipasang ke zona dasar.
func can_place_base(p: int, uid: int) -> bool:
	if _turn_guard(p) != "":
		return false
	var pl = players[p]
	if pl.base.size() >= _rules().base_max:
		return false
	var c := _peek(pl.hand, uid)
	if c.is_empty():
		return false
	var d := CardDB.get_card(c.id)
	return d != null and d.type == CardData.Type.BASIC

## Spell di tangan boleh dimainkan (jatah spell cukup & targetnya tersedia).
func can_cast_spell(p: int, uid: int) -> bool:
	if _turn_guard(p) != "":
		return false
	var c := _peek(players[p].hand, uid)
	if c.is_empty():
		return false
	var d := CardDB.get_card(c.id)
	if d == null or d.type != CardData.Type.SPELL:
		return false
	if not _effects.has(d.spell_effect):
		return false
	if d.spell_effect != "katalis" and spell_left <= 0:
		return false                # Katalis tidak memakai jatah spell
	return _spell_has_target(p, d.spell_effect)

## Kartu dasar bisa dipakai sintesis: ada pasangan (id beda, tidak cooldown)
## yang membentuk senyawa yang masih tersedia di Deck Senyawa.
func can_synth_with(p: int, uid: int) -> bool:
	if _turn_guard(p) != "":
		return false
	if synth_left <= 0:
		return false
	var pl = players[p]
	if pl.special.size() >= _rules().special_max:
		return false
	var a := _peek(pl.base, uid)
	if a.is_empty() or a.placed_turn == turn_no:
		return false
	for b in pl.base:
		if b.uid == uid or b.id == a.id or b.placed_turn == turn_no:
			continue
		var result := CardDB.find_recipe(a.id, b.id)
		if result != "" and compound_pile.has(result):
			return true
	return false

## Kumpulan uid kartu yang bisa dimainkan, untuk ditandai di papan.
func playable_ids(p: int) -> Dictionary:
	var hand: Array = []
	var base: Array = []
	if _turn_guard(p) == "":
		for c in players[p].hand:
			if can_place_base(p, c.uid) or can_cast_spell(p, c.uid):
				hand.append(c.uid)
		for c in players[p].base:
			if can_synth_with(p, c.uid):
				base.append(c.uid)
	return {"hand": hand, "base": base}

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
	if _rules().hand_max > 0 and pl.hand.size() > _rules().hand_max:
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
		"playable": playable_ids(p),
		"history": history.duplicate(true),
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
